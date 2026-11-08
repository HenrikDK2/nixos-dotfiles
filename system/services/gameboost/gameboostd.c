/* gameboostd: event-driven game detector for GameBoost.
 *
 *   gameboostd -m GAME_ERE [-x EXCLUDE_ERE] -d SCRIPT_DIR [-f FLAG_FILE]
 *   gameboostd -m GAME_ERE [-x EXCLUDE_ERE] -1     one scan, print matches
 *   gameboostd -m GAME_ERE [-x EXCLUDE_ERE] -n     validate patterns, exit
 *
 * Instead of reading every /proc/PID/cmdline on a timer, it subscribes to the
 * kernel's exec events (netlink proc connector) and only looks at processes
 * that just started a new program. While a game runs it unsubscribes and
 * sleeps on a pidfd until the game exits, so it never wakes up during play.
 *
 * Fallbacks: no proc connector (e.g. non-root, container) -> full scan every
 * FALLBACK_MS; no pidfd_open (< Linux 5.3) -> kill(pid, 0) every FALLBACK_MS.
 *
 * Matching: each top-level alternative of the ERE is compiled separately and
 * lazily, and gated by a literal it must contain (memmem). glibc builds its
 * DFA lazily during regexec, which costs 40-130 us per line on a cold
 * one-big-alternation regex; small per-alternative regexes avoid most of it.
 */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/cn_proc.h>
#include <linux/connector.h>
#include <linux/netlink.h>
#include <poll.h>
#include <regex.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef SYS_close_range
#define SYS_close_range 436
#endif
#ifndef SYS_pidfd_open
#define SYS_pidfd_open 434
#endif
#ifndef SYS_ioprio_set
#define SYS_ioprio_set 251 /* x86_64 */
#endif

#define CMD_MAX 4096          /* bytes of cmdline examined, as before */
#define FIRST_CHECK_MS 1000   /* exec -> first cmdline read */
#define FALLBACK_MS 20000     /* poll interval when events are unavailable */
#define MAX_PENDING 1024

/* Storm mode. Handling one exec event costs ~1.3 us; a full scan ~5 ms, so
 * polling every 20 s equals ~190 events/s. Above that rate (builds, scripts
 * in loops) polling is cheaper: unsubscribe, which also stops the kernel from
 * generating the events, and scan every FALLBACK_MS until things calm down. */
#define STORM_BATCH 400        /* events in one ~1-2 s batch */
#define STORM_WINDOW_MS 20000
#define STORM_EVENTS 4000      /* events per window (~200/s sustained) */
#define MAX_FOUND 256
#define MIN_LIT 3
#define CLOSE_BATCH 128

/* Wine rewrites argv to the Windows path shortly after exec. A process whose
 * cmdline still mentions wine at the first check is re-checked later. */
static const int64_t wine_retry_ms[] = {4000, 25000};

/* ------------------------------------------------------------------------- */
/* Pattern sets                                                               */
/* ------------------------------------------------------------------------- */

struct alt {
  char *pat;       /* this alternative alone, NUL-terminated */
  const char *lit; /* literal every match contains, or NULL */
  size_t litn;
  int compiled;
  regex_t re;
};

struct altset {
  struct alt *v;
  int n;
};

static struct altset games, excls;

/* p -> '[': returns the closing ']' of the bracket expression, or NULL. */
static const char *skip_bracket(const char *p) {
  ++p;
  if (*p == '^')
    ++p;
  if (*p == ']')
    ++p;
  for (; *p; ++p) {
    if (*p == '[' && (p[1] == ':' || p[1] == '.' || p[1] == '=')) {
      char t = p[1];
      for (p += 2; *p && !(*p == t && p[1] == ']'); ++p)
        ;
      if (!*p)
        return NULL;
      ++p;
    } else if (*p == ']') {
      return p;
    }
  }
  return NULL;
}

/* Longest literal run that any match of the single alternative `re` must
 * contain. Returns 0 (no prefilter) when unsure. `pool` has strlen(re)+1. */
static int extract_literal(const char *re, char *pool, const char **lit,
                           size_t *litn) {
  size_t run = 0, runn = 0, best = 0, bestn = 0;
  int depth = 0;

#define END_RUN()                                                              \
  do {                                                                         \
    if (runn > bestn)                                                          \
      best = run, bestn = runn;                                                \
    run += runn;                                                               \
    runn = 0;                                                                  \
  } while (0)

  for (const char *p = re; *p; ++p) {
    char c = *p;

    if (depth > 0) { /* inside a group: nothing in it is required */
      if (c == '\\') {
        if (!*++p)
          return 0;
      } else if (c == '[') {
        if (!(p = skip_bracket(p)))
          return 0;
      } else if (c == '(') {
        ++depth;
      } else if (c == ')') {
        --depth;
      }
      continue;
    }

    switch (c) {
    case '\\':
      if (!*++p)
        return 0;
      /* Only escaped punctuation is a plain literal (\w \b \< ... are not). */
      if (strchr(".\\/-+*?[](){}|^$ :_,=@#%&!~\";", *p))
        pool[run + runn++] = *p;
      else
        END_RUN();
      break;
    case '[':
      END_RUN();
      if (!(p = skip_bracket(p)))
        return 0;
      break;
    case '(':
      END_RUN();
      depth = 1;
      break;
    case ')':
    case '|':
      return 0;
    case '.':
    case '^':
    case '$':
    case '+':
      END_RUN();
      break;
    case '*':
    case '?':
    case '{':
      if (runn) /* the quantified atom is optional: not required */
        --runn;
      END_RUN();
      if (c == '{') {
        for (++p; *p && *p != '}'; ++p)
          if ((*p < '0' || *p > '9') && *p != ',')
            return 0;
        if (!*p)
          return 0;
      }
      break;
    default:
      pool[run + runn++] = c;
    }
  }
  END_RUN();
#undef END_RUN

  if (depth || bestn < MIN_LIT)
    return 0;
  *lit = pool + best;
  *litn = bestn;
  return 1;
}

static void *xalloc(void *p) {
  if (!p) {
    (void)!write(2, "gameboostd: out of memory\n", 26);
    _exit(1);
  }
  return p;
}

/* Split an ERE at its top-level '|' into separately compiled alternatives. */
static int split_alts(const char *re, struct altset *set) {
  int cap = 8;
  const char *start = re;
  int depth = 0;

  set->v = xalloc(calloc(cap, sizeof *set->v));
  set->n = 0;

  for (const char *p = re;; ++p) {
    if (*p == '\\' && p[1]) {
      ++p;
      continue;
    }
    if (*p == '[') {
      const char *q = skip_bracket(p);
      if (q) {
        p = q;
        continue;
      }
    }
    if (*p == '(')
      ++depth;
    else if (*p == ')')
      --depth;

    if (*p == '\0' || (*p == '|' && depth == 0)) {
      size_t len = (size_t)(p - start);
      if (set->n == cap)
        set->v = xalloc(realloc(set->v, (cap *= 2) * sizeof *set->v));
      struct alt *a = &set->v[set->n++];
      memset(a, 0, sizeof *a);
      a->pat = xalloc(strndup(start, len));
      char *pool = xalloc(malloc(len + 1));
      if (!extract_literal(a->pat, pool, &a->lit, &a->litn)) {
        free(pool);
        a->lit = NULL;
      }
      if (!*p)
        break;
      start = p + 1;
    }
  }
  return set->n;
}

static int compile_alt(struct alt *a) {
  if (!a->compiled) {
    if (regcomp(&a->re, a->pat, REG_EXTENDED | REG_NOSUB))
      return -1;
    a->compiled = 1;
  }
  return 0;
}

static int set_matches(struct altset *set, const char *s, size_t n) {
  for (int i = 0; i < set->n; ++i) {
    struct alt *a = &set->v[i];
    if (a->lit && !memmem(s, n, a->lit, a->litn))
      continue;
    if (compile_alt(a))
      _exit(2); /* validated at startup; cannot happen */
    if (!regexec(&a->re, s, 0, NULL, 0))
      return 1;
  }
  return 0;
}

/* ------------------------------------------------------------------------- */
/* /proc access                                                              */
/* ------------------------------------------------------------------------- */

static int procfd = -1;
static pid_t self;

/* Read /proc/PID/cmdline into buf as one line: NULs/newlines become spaces,
 * surrounding blanks trimmed (like `read -r pid cmdline`). Returns length or
 * -1 if the process is gone. *fdp receives the open fd (caller closes). */
static ssize_t read_cmdline_fd(const char *pid, char *buf, char **out,
                               int *fdp) {
  char path[32];
  size_t pl = strlen(pid);

  memcpy(path, pid, pl);
  memcpy(path + pl, "/cmdline", 9);

  int fd = openat(procfd, path, O_RDONLY | O_CLOEXEC);
  *fdp = fd;
  if (fd < 0)
    return -1;

  ssize_t n;
  do
    n = read(fd, buf, CMD_MAX - 1);
  while (n < 0 && errno == EINTR);
  if (n < 0)
    return -1;

  for (ssize_t i = 0; i < n; ++i)
    if (buf[i] == '\0' || buf[i] == '\n')
      buf[i] = ' ';

  char *s = buf, *e = buf + n;
  while (s < e && (*s == ' ' || *s == '\t'))
    ++s;
  while (e > s && (e[-1] == ' ' || e[-1] == '\t'))
    --e;
  *e = '\0';
  *out = s;
  return e - s;
}

static int is_game(const char *cmd, size_t n) {
  return set_matches(&games, cmd, n) && !set_matches(&excls, cmd, n);
}

static ssize_t read_cmdline(pid_t pid, char *buf, char **out) {
  char p[16];
  int fd;
  snprintf(p, sizeof p, "%d", (int)pid);
  ssize_t n = read_cmdline_fd(p, buf, out, &fd);
  if (fd >= 0)
    close(fd);
  return n;
}

/* Close fds lo..lo+*pending-1 with one close_range() (Linux 5.9+). The fds
 * are contiguous: openat() returns the lowest free fd and nothing else opens
 * files during a scan; a gap just starts a new batch. */
static void flush_closes(int lo, int *pending, int *use_close_range) {
  if (!*pending)
    return;
  if (!*use_close_range || syscall(SYS_close_range, lo, lo + *pending - 1, 0)) {
    *use_close_range = 0; /* ENOSYS / seccomp: plain close from now on */
    for (int i = lo; i < lo + *pending; ++i)
      close(i);
  }
  *pending = 0;
}

struct found {
  pid_t pid[MAX_FOUND];
  int n;
  char first_cmd[CMD_MAX];
};

/* Every running process that is a game. Single-threaded on purpose: this runs
 * at idle priority where wall time doesn't matter, and threads cost more total
 * CPU (measured: 6.1 ms vs 6.9-8.0 ms per scan at ~950 processes). */
static unsigned long stat_scans;

static void full_scan(struct found *f, int print) {
  static char dirbuf[32 * 1024];
  static char buf[CMD_MAX];
  int lo = -1, pending = 0;
  int use_close_range = 1;

  f->n = 0;
  ++stat_scans;
  lseek(procfd, 0, SEEK_SET);

  for (;;) {
    long nread = syscall(SYS_getdents64, procfd, dirbuf, sizeof dirbuf);
    if (nread <= 0) {
      if (nread < 0 && errno == EINTR)
        continue;
      break;
    }
    for (long pos = 0; pos < nread;) {
      struct {
        uint64_t ino;
        int64_t off;
        unsigned short reclen;
        unsigned char type;
        char name[];
      } *e = (void *)(dirbuf + pos);
      pos += e->reclen;

      const char *s = e->name;
      if (*s < '1' || *s > '9')
        continue;
      char *end;
      long pid = strtol(s, &end, 10);
      if (*end || pid == self)
        continue;

      char *cmd;
      int fd;
      ssize_t n = read_cmdline_fd(s, buf, &cmd, &fd);

      /* Batch closes into one close_range() while fds stay contiguous. */
      if (fd >= 0) {
        if (!use_close_range) {
          close(fd);
        } else {
          if (pending && fd != lo + pending) /* gap: flush, start anew */
            flush_closes(lo, &pending, &use_close_range);
          if (!pending)
            lo = fd;
          if (++pending >= CLOSE_BATCH)
            flush_closes(lo, &pending, &use_close_range);
        }
      }

      if (n <= 0 || !is_game(cmd, (size_t)n))
        continue;

      if (print)
        printf("%ld\t%s\n", pid, cmd);
      if (f->n == 0)
        snprintf(f->first_cmd, sizeof f->first_cmd, "%s", cmd);
      if (f->n < MAX_FOUND)
        f->pid[f->n++] = (pid_t)pid;
    }
  }

  flush_closes(lo, &pending, &use_close_range);
}

/* ------------------------------------------------------------------------- */
/* Proc connector                                                            */
/* ------------------------------------------------------------------------- */

static int cn_control(int sock, enum proc_cn_mcast_op op) {
  struct __attribute__((packed)) {
    struct nlmsghdr nl;
    struct cn_msg cn;
    struct proc_input in;
  } m;

  memset(&m, 0, sizeof m);
  m.nl.nlmsg_len = sizeof m;
  m.nl.nlmsg_type = NLMSG_DONE;
  m.cn.id.idx = CN_IDX_PROC;
  m.cn.id.val = CN_VAL_PROC;
  m.cn.len = sizeof m.in;
  m.in.mcast_op = op;
  m.in.event_type = PROC_EVENT_EXEC; /* 6.6+: exec only; older: ignored */
  return send(sock, &m, sizeof m, 0) == sizeof m ? 0 : -1;
}

static int cn_open(void) {
  int s = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK,
                 NETLINK_CONNECTOR);
  if (s < 0)
    return -1;

  struct sockaddr_nl a = {.nl_family = AF_NETLINK, .nl_groups = CN_IDX_PROC};
  int rcv = 1 << 20; /* room for ~2 s of exec bursts; overflow -> full scan */

  setsockopt(s, SOL_SOCKET, SO_RCVBUFFORCE, &rcv, sizeof rcv);
  if (bind(s, (void *)&a, sizeof a) || cn_control(s, PROC_CN_MCAST_LISTEN)) {
    close(s);
    return -1;
  }
  return s;
}

/* ------------------------------------------------------------------------- */
/* State                                                                     */
/* ------------------------------------------------------------------------- */

static const char *script_dir, *flag_file = "/run/gameboost/running.flag";
static int sock = -1, sigfd = -1, pidfd = -1;
static pid_t current, start_pid;
static int game_mode, need_scan;

static struct {
  pid_t pid;
  int tries;
  int64_t due;
} pending[MAX_PENDING];
static int npending;
static unsigned long stat_events, stat_checks, stat_storms;
static int64_t storm_until, win_start;
static unsigned win_events;
static int overflowed, stormy;

static int64_t now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void logmsg(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void logmsg(const char *fmt, ...) {
  char b[CMD_MAX + 128];
  va_list ap;
  va_start(ap, fmt);
  int n = vsnprintf(b, sizeof b - 1, fmt, ap);
  va_end(ap);
  if (n < 0)
    return;
  if (n > (int)sizeof b - 2)
    n = sizeof b - 2;
  b[n++] = '\n';
  for (char *p = b; p < b + n; ++p) /* show Windows paths with '/' */
    if (*p == '\\')
      *p = '/';
  (void)!write(1, b, (size_t)n);
}

/* Run a helper script at normal priority (we run SCHED_IDLE / nice 19 / idle
 * I/O, which children would otherwise inherit and starve under game load). */
static pid_t spawn(char *const argv[]) {
  pid_t pid = vfork();
  if (pid == 0) {
    struct sched_param sp = {0};
    sigset_t none;
    sigemptyset(&none);
    sigprocmask(SIG_SETMASK, &none, NULL);
    sched_setscheduler(0, SCHED_OTHER, &sp);
    setpriority(PRIO_PROCESS, 0, 0);
    syscall(SYS_ioprio_set, 1 /* WHO_PROCESS */, 0, (2 << 13) | 4 /* BE 4 */);
    execv(argv[0], argv);
    _exit(127);
  }
  return pid;
}

static void run_script(const char *name, const char *arg) {
  char path[4096];
  snprintf(path, sizeof path, "%s/%s", script_dir, name);
  char *argv[] = {path, (char *)arg, NULL};
  spawn(argv);
}

static void reap(void) {
  pid_t p;
  while ((p = waitpid(-1, NULL, WNOHANG)) > 0)
    if (p == start_pid)
      start_pid = 0;
}

static void track(pid_t pid) {
  if (pidfd >= 0)
    close(pidfd);
  current = pid;
  pidfd = (int)syscall(SYS_pidfd_open, pid, 0); /* -1 -> kill(0) polling */
  if (pidfd < 0 && errno == ESRCH)
    need_scan = 1; /* already gone: re-check right away */
}

/* The flag file marks game mode (auto-upgrade and the maintenance gate only
 * test that it exists) and holds what gameboost-status shows:
 *   pid=  since=  appid=  cmd=
 * Written to a temporary file and renamed, so it never appears half-written
 * or missing while game mode lasts. */
static time_t mode_since;

static void write_flag(pid_t pid, const char *cmd) {
  char tmp[4096];
  const char *a = strstr(cmd, "AppId=");
  long appid = a ? strtol(a + 6, NULL, 10) : 0;

  snprintf(tmp, sizeof tmp, "%s.tmp", flag_file);
  int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (fd >= 0) {
    dprintf(fd, "pid=%d\nsince=%lld\nappid=%ld\ncmd=%s\n", (int)pid,
            (long long)mode_since, appid, cmd);
    close(fd);
    if (!rename(tmp, flag_file))
      return;
    unlink(tmp);
  }
  /* Fallback: at least mark game mode. */
  fd = open(flag_file, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
  if (fd >= 0)
    close(fd);
}

static void enter_game_mode(struct found *f) {
  logmsg("Detected game process: PID=%d, CMD='%s'", (int)f->pid[0],
         f->first_cmd);

  mode_since = time(NULL);
  write_flag(f->pid[0], f->first_cmd);

  /* start.sh PID... */
  char path[4096], pids[MAX_FOUND][12];
  char *argv[MAX_FOUND + 2];
  int argc = 0;
  snprintf(path, sizeof path, "%s/start.sh", script_dir);
  argv[argc++] = path;
  for (int i = 0; i < f->n; ++i) {
    snprintf(pids[i], sizeof pids[i], "%d", (int)f->pid[i]);
    argv[argc++] = pids[i];
  }
  argv[argc] = NULL;
  start_pid = spawn(argv);
  run_script("notify.sh", "Switching to performance mode");

  game_mode = 1;
  npending = 0;
  if (sock >= 0)
    cn_control(sock, PROC_CN_MCAST_IGNORE); /* no events during play */
  track(f->pid[0]);
}

static void leave_game_mode(void) {
  if (start_pid > 0) {
    kill(start_pid, SIGTERM); /* still applying settings: stop it */
    waitpid(start_pid, NULL, 0);
    start_pid = 0;
  }
  unlink(flag_file);
  run_script("exit.sh", NULL);
  run_script("notify.sh", "Switching to power-saving mode");
  game_mode = 0;
  current = 0;
}

/* No duplicate check: a PID that exec'd twice in a second just gets checked
 * twice (one cheap kill(0) each), which is cheaper than a linear search per
 * event under exec bursts. */
static void add_pending(pid_t pid, int64_t due) {
  ++stat_events;
  ++win_events;
  if (npending == MAX_PENDING) {
    overflowed = 1; /* storm mode takes over */
    return;
  }
  pending[npending].pid = pid;
  pending[npending].tries = 0;
  pending[npending].due = due;
  ++npending;
}

/* Read every queued event, up to EV_BATCH datagrams per syscall (netlink
 * delivers one datagram per exec, so plain recv() costs a syscall each). */
#define EV_BATCH 64
#define EV_SIZE 256 /* one proc-connector datagram is ~80 bytes */

static int drain_events(void) {
  static char bufs[EV_BATCH][EV_SIZE] __attribute__((aligned(8)));
  static struct iovec iov[EV_BATCH];
  static struct mmsghdr msgs[EV_BATCH];
  int64_t due = now_ms() + FIRST_CHECK_MS;
  unsigned long before = stat_events;

  for (;;) {
    for (int i = 0; i < EV_BATCH; ++i) {
      iov[i].iov_base = bufs[i];
      iov[i].iov_len = EV_SIZE;
      msgs[i].msg_hdr = (struct msghdr){.msg_iov = &iov[i], .msg_iovlen = 1};
    }

    int got = recvmmsg(sock, msgs, EV_BATCH, MSG_DONTWAIT, NULL);
    if (got < 0) {
      if (errno == EINTR)
        continue;
      if (errno == ENOBUFS) { /* events lost: storm mode takes over */
        overflowed = 1;
        need_scan = 1;
        continue;
      }
      return (int)(stat_events - before); /* EAGAIN: drained */
    }

    if (!game_mode) /* else: stale events queued before IGNORE */
      for (int m = 0; m < got; ++m) {
        size_t n = msgs[m].msg_len;
        for (struct nlmsghdr *nl = (void *)bufs[m]; NLMSG_OK(nl, n);
             nl = NLMSG_NEXT(nl, n)) {
          struct cn_msg *cn = NLMSG_DATA(nl);
          struct proc_event *ev = (void *)cn->data;
          if (ev->what == PROC_EVENT_EXEC)
            add_pending(ev->event_data.exec.process_tgid, due);
        }
      }

    if (got < EV_BATCH) /* queue empty: skip the final EAGAIN round trip */
      return (int)(stat_events - before);
  }
}

/* Check processes whose first/next check is due. Returns 1 if a game was
 * found (a full scan then collects all game PIDs for start.sh). */
static int check_pending(void) {
  static char buf[CMD_MAX];
  int64_t now = now_ms();
  int hit = 0;

  for (int i = 0; i < npending;) {
    if (pending[i].due > now) {
      ++i;
      continue;
    }
    ++stat_checks;
    char *cmd;
    /* kill(pid, 0) is far cheaper than a failed /proc path lookup, and most
     * programs started at high rates (compilers, scripts) are gone by now. */
    ssize_t n = kill(pending[i].pid, 0) && errno == ESRCH
                    ? -1
                    : read_cmdline(pending[i].pid, buf, &cmd);
    int keep = 0;
    if (n > 0 && is_game(cmd, (size_t)n)) {
      hit = 1;
    } else if (n > 0 && pending[i].tries < 2 && memmem(cmd, (size_t)n, "wine", 4)) {
      pending[i].due = now + wine_retry_ms[pending[i].tries++];
      keep = 1;
    }
    if (keep)
      ++i;
    else
      pending[i] = pending[--npending];
  }
  return hit;
}

static int64_t next_due(void) {
  int64_t d = INT64_MAX;
  for (int i = 0; i < npending; ++i)
    if (pending[i].due < d)
      d = pending[i].due;
  return d;
}

static void scan_and_maybe_enter(void) {
  static struct found f;
  need_scan = 0;
  full_scan(&f, 0);
  if (f.n)
    enter_game_mode(&f);
}

/* The tracked game exited (or vanished): follow another game or stop. */
static void on_game_exit(void) {
  static struct found f;

  logmsg("Game process ended: PID=%d", (int)current);
  if (pidfd >= 0)
    close(pidfd), pidfd = -1;

  /* Listen before scanning so nothing exec'd in between is missed. */
  if (sock >= 0) {
    cn_control(sock, PROC_CN_MCAST_LISTEN);
    game_mode = 0; /* drain_events keeps events from here on */
    (void)drain_events();
    game_mode = 1;
  }

  need_scan = 0;
  full_scan(&f, 0);
  if (f.n) {
    logmsg("Switched tracking to another game: PID=%d, CMD='%s'",
           (int)f.pid[0], f.first_cmd);
    write_flag(f.pid[0], f.first_cmd);
    if (sock >= 0)
      cn_control(sock, PROC_CN_MCAST_IGNORE);
    npending = 0;
    track(f.pid[0]);
  } else {
    leave_game_mode();
  }
}

/* The kernel counts proc-connector listeners per LISTEN/IGNORE message and
 * does not decrement the count when a listening socket is closed, so exiting
 * while subscribed would leave every later fork/exec/exit (system-wide, until
 * reboot) building an event for nobody. Idempotent: IGNORE is only counted
 * if this socket is currently listening. */
static void unsubscribe(void) {
  if (sock >= 0)
    cn_control(sock, PROC_CN_MCAST_IGNORE);
}

/* ------------------------------------------------------------------------- */

static int usage(void) {
  fprintf(stderr, "usage: gameboostd -m GAME_ERE [-x EXCL_ERE] "
                  "(-d SCRIPT_DIR [-f FLAG] | -1 | -n)\n");
  return 2;
}

int main(int argc, char **argv) {
  const char *game_pat = NULL, *excl_pat = NULL;
  int check_only = 0, once = 0;

  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "-n"))
      check_only = 1;
    else if (!strcmp(argv[i], "-1"))
      once = 1;
    else if (i + 1 < argc && !strcmp(argv[i], "-m"))
      game_pat = argv[++i];
    else if (i + 1 < argc && !strcmp(argv[i], "-x"))
      excl_pat = argv[++i];
    else if (i + 1 < argc && !strcmp(argv[i], "-d"))
      script_dir = argv[++i];
    else if (i + 1 < argc && !strcmp(argv[i], "-f"))
      flag_file = argv[++i];
    else
      return usage();
  }
  if (!game_pat || (!check_only && !once && !script_dir))
    return usage();

  split_alts(game_pat, &games);
  if (excl_pat)
    split_alts(excl_pat, &excls);

  if (check_only) { /* compile everything once to validate */
    regex_t r;
    if (regcomp(&r, game_pat, REG_EXTENDED | REG_NOSUB) ||
        (excl_pat && regcomp(&r, excl_pat, REG_EXTENDED | REG_NOSUB)))
      return 2;
    for (int i = 0; i < games.n; ++i)
      if (compile_alt(&games.v[i]))
        return 2;
    for (int i = 0; i < excls.n; ++i)
      if (compile_alt(&excls.v[i]))
        return 2;
    return 0;
  }

  self = getpid();
  procfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (procfd < 0)
    return 1;

  if (once) {
    static struct found f;
    full_scan(&f, 1);
    return 0;
  }

  setvbuf(stdout, NULL, _IONBF, 0);
  unlink(flag_file);

  sigset_t ss;
  sigemptyset(&ss);
  sigaddset(&ss, SIGTERM);
  sigaddset(&ss, SIGINT);
  sigprocmask(SIG_BLOCK, &ss, NULL);
  sigfd = signalfd(-1, &ss, SFD_CLOEXEC);

  sock = cn_open();
  if (sock >= 0)
    logmsg("Watching exec events");
  else
    logmsg("Exec events unavailable: polling every %d s", FALLBACK_MS / 1000);

  scan_and_maybe_enter();

  for (;;) {
    struct pollfd p[2] = {{sigfd, POLLIN, 0}, {-1, POLLIN, 0}};
    int timeout = -1;

    if (game_mode) {
      p[1].fd = pidfd;
      if (pidfd < 0)
        timeout = FALLBACK_MS;
    } else if (sock < 0) {
      timeout = FALLBACK_MS;
    } else if (storm_until) {
      int64_t d = storm_until - now_ms();
      timeout = d < 0 ? 0 : (int)d;
    } else if (npending) {
      /* Let events queue in the socket until the next check is due:
       * one wakeup per batch instead of one per exec. */
      int64_t d = next_due() - now_ms();
      timeout = d < 0 ? 0 : (int)d;
    } else {
      p[1].fd = sock;
    }

    if (need_scan)
      timeout = 0;

    int r = poll(p, 2, timeout);
    if (r < 0 && errno != EINTR) {
      unsubscribe();
      return 1;
    }

    if (p[0].revents & POLLIN) {
      logmsg("Stopping: %lu exec events, %lu checks, %lu full scans, "
             "%lu storm periods",
             stat_events, stat_checks, stat_scans, stat_storms);
      if (game_mode) { /* restore power settings on shutdown */
        leave_game_mode();
        while (wait(NULL) > 0 || errno == EINTR)
          ;
      }
      unsubscribe();
      return 0;
    }

    reap();

    if (game_mode) {
      if ((p[1].revents & POLLIN) || need_scan ||
          (pidfd < 0 && kill(current, 0) && errno == ESRCH))
        on_game_exit();
      continue;
    }

    if (sock < 0) {
      scan_and_maybe_enter();
      continue;
    }

    int64_t now = now_ms();

    if (storm_until) {
      if (now < storm_until)
        continue;
      /* Storm period over: watch events again, and scan once for anything
       * started while we weren't listening. */
      storm_until = 0;
      win_start = now;
      win_events = 0;
      cn_control(sock, PROC_CN_MCAST_LISTEN);
      scan_and_maybe_enter();
      continue;
    }

    int batch = drain_events();

    if (now - win_start >= STORM_WINDOW_MS) {
      if (stormy && win_events <= STORM_EVENTS) {
        logmsg("Program start rate back to normal: watching exec events");
        stormy = 0;
      }
      win_start = now;
      win_events = (unsigned)batch;
    }

    if (overflowed || batch > STORM_BATCH || win_events > STORM_EVENTS) {
      if (!stormy)
        logmsg("Many programs starting: scanning every %d s until it calms "
               "down", FALLBACK_MS / 1000);
      stormy = 1;
      ++stat_storms;
      overflowed = 0;
      need_scan = 0;
      npending = 0; /* the scan at the end of the storm period covers them */
      cn_control(sock, PROC_CN_MCAST_IGNORE);
      storm_until = now + FALLBACK_MS;
      continue;
    }

    if (check_pending() || need_scan)
      scan_and_maybe_enter();
  }
}
