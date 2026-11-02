#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <linux/types.h>
#include <pthread.h>
#include <regex.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#ifndef SYS_close_range
#define SYS_close_range 436 /* Linux 5.9+ */
#endif

#define MAX_WORKERS 8
#define MIN_PER_WORKER 64 /* don't spawn a thread for < this many PIDs */
#define GETDENTS_BUF_SIZE (64 * 1024)
#define CMD_BUF_SIZE 4096
#define OUT_BUF_SIZE (64 * 1024)
#define MAX_PIDS 131072
#define WORKER_STACK (64 * 1024)
#define CLOSE_BATCH 128 /* fds held open before one close_range() */

_Static_assert(OUT_BUF_SIZE >= 15 + 1 + CMD_BUF_SIZE + 1,
               "output buffer must fit one worst-case entry");

struct linux_dirent64 {
  uint64_t ino;
  int64_t off;
  unsigned short reclen;
  unsigned char type;
  char name[];
};

struct process {
  char pid[16];
  uint8_t len;
};

struct worker {
  int procfd;
  const struct process *items;
  size_t count;
  _Atomic size_t *next;
  size_t chunk;
  char *out;
  size_t outpos;
  /* Batched-close state (single-threaded mode only; see main). */
  int batch;
  int lo;
  int pending;
};

static struct process items[MAX_PIDS];
static char dirbuf[GETDENTS_BUF_SIZE] __attribute__((aligned(16)));
static char outbufs[MAX_WORKERS][OUT_BUF_SIZE];
static char stacks[MAX_WORKERS][WORKER_STACK] __attribute__((aligned(4096)));
static pthread_mutex_t out_lock = PTHREAD_MUTEX_INITIALIZER;
static int no_close_range; /* only touched in single-threaded mode */

/* Optional in-process filter:  optimized_ps -m GAME_ERE [-x EXCLUDE_ERE]
 * Prints "pid<TAB>cmdline" for processes matching GAME_ERE and not EXCLUDE_ERE,
 * replacing a `| grep -E | while read ... [[ =~ ]]` pipeline in the caller.
 *
 * glibc's regexec is slow (~30us/line), so every top-level alternative of
 * GAME_ERE is reduced to one literal that any match must contain, and lines
 * lacking all of them are rejected with memmem(). If the pattern uses anything
 * the extractor is unsure about it gives up and every line gets the regex. */
#define MAX_LITS 16
#define MIN_LIT 3

static regex_t re_game, re_excl;
static int have_filter, have_excl;
static const char *game_pat, *excl_pat;
static pthread_once_t once_game = PTHREAD_ONCE_INIT, once_excl = PTHREAD_ONCE_INIT;
static char self_pid[16]; /* never report ourselves: our argv holds the patterns */
static size_t self_len;
static struct {
  const char *s;
  size_t n;
} lits[MAX_LITS];
static int nlits;
static char pool[2048];
static size_t poolpos;

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

/* Returns 1 and fills lits[] on success, 0 to disable the prefilter. */
static int extract_literals(const char *re) {
  size_t run = poolpos, runn = 0, best = 0, bestn = 0;
  int depth = 0;

#define END_RUN()                                                              \
  do {                                                                         \
    if (runn > bestn) {                                                        \
      best = run;                                                              \
      bestn = runn;                                                            \
    }                                                                          \
    run += runn;                                                               \
    runn = 0;                                                                  \
  } while (0)
#define ADD_LIT(ch)                                                            \
  do {                                                                         \
    if (run + runn >= sizeof(pool))                                            \
      return 0;                                                                \
    pool[run + runn++] = (ch);                                                 \
  } while (0)

  for (const char *p = re;; ++p) {
    char c = *p;

    if (c == '\0' || (c == '|' && depth == 0)) {
      END_RUN();

      if (depth || bestn < MIN_LIT || nlits == MAX_LITS)
        return 0;

      lits[nlits].s = pool + best;
      lits[nlits].n = bestn;
      ++nlits;
      bestn = 0;

      if (!c)
        break;

      continue;
    }

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
      if (!p[1])
        return 0;

      ++p;

      /* Only escaped punctuation is a plain literal: \w \b \< \> \' ... are
       * special in GNU regex. */
      if (*p && strchr(".\\/-+*?[](){}|^$ :_,=@#%&!~\";", *p))
        ADD_LIT(*p);
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

      if (c == '{') { /* only a plain interval {m,n} is understood */
        for (++p; *p && *p != '}'; ++p)
          if ((*p < '0' || *p > '9') && *p != ',')
            return 0;

        if (!*p)
          return 0;
      }

      break;
    default:
      ADD_LIT(c);
    }
  }

  poolpos = run;
  return 1;
#undef END_RUN
#undef ADD_LIT
}

/* Most scans find no candidate, so the regexes are compiled on first use. */
static void compile_game(void) {
  if (regcomp(&re_game, game_pat, REG_EXTENDED | REG_NOSUB))
    _exit(2);
}

static void compile_excl(void) {
  if (regcomp(&re_excl, excl_pat, REG_EXTENDED | REG_NOSUB))
    _exit(2);
}

/* Decide whether the record "pid cmdline" at w->out[start..outpos) is wanted.
 * On success it is rewritten in place as "pid<TAB>cmdline" (blanks around the
 * cmdline trimmed, as `read -r pid cmdline` does). */
static int accept_record(struct worker *w, size_t start, size_t pidlen) {
  char *line = w->out + start;

  if (nlits) {
    size_t len = w->outpos - start;
    int hit = 0;

    for (int i = 0; i < nlits && !hit; ++i)
      hit = memmem(line, len, lits[i].s, lits[i].n) != NULL;

    if (!hit)
      return 0;
  }

  w->out[w->outpos] = '\0'; /* room reserved by process_one's `need` */

  pthread_once(&once_game, compile_game);

  if (regexec(&re_game, line, 0, NULL, 0))
    return 0;

  char *cmd = line + pidlen + 1, *end = w->out + w->outpos;

  while (cmd < end && (*cmd == ' ' || *cmd == '\t'))
    ++cmd;

  while (end > cmd && (end[-1] == ' ' || end[-1] == '\t'))
    --end;

  *end = '\0';

  if (have_excl) {
    pthread_once(&once_excl, compile_excl);

    if (!regexec(&re_excl, cmd, 0, NULL, 0))
      return 0;
  }

  size_t clen = (size_t)(end - cmd);

  line[pidlen] = '\t';
  memmove(line + pidlen + 1, cmd, clen);
  w->outpos = start + pidlen + 1 + clen;
  return 1;
}

static void flush(struct worker *w) {
  size_t n = 0;

  pthread_mutex_lock(&out_lock);

  while (n < w->outpos) {
    ssize_t r = write(1, w->out + n, w->outpos - n);

    if (r > 0)
      n += (size_t)r;
    else if (r < 0 && errno == EINTR)
      continue;
    else
      break;
  }

  pthread_mutex_unlock(&out_lock);
  w->outpos = 0;
}

/* Close every fd we've been holding with one syscall. The fds are contiguous
 * because we never close individually in batch mode and nothing else opens
 * files while we run, so openat() hands out lo, lo+1, ... in order. */
static void close_pending(struct worker *w) {
  if (!w->pending)
    return;

  int lo = w->lo, hi = w->lo + w->pending - 1;

  w->pending = 0;

  if (!no_close_range && syscall(SYS_close_range, lo, hi, 0) == 0)
    return;

  /* ENOSYS (old kernel) or EPERM (seccomp): fall back for good. */
  no_close_range = 1;

  for (int fd = lo; fd <= hi; ++fd)
    close(fd);
}

static inline void process_one(struct worker *w, const struct process *p) {
  char path[24];

  if (have_filter && p->len == self_len && !memcmp(p->pid, self_pid, self_len))
    return;

  memcpy(path, p->pid, p->len);
  memcpy(path + p->len, "/cmdline", 9);

  int fd = openat(w->procfd, path, O_RDONLY);

  if (fd < 0 && errno == EMFILE && w->pending) {
    /* Low RLIMIT_NOFILE: release the batch and retry rather than drop PIDs. */
    close_pending(w);
    fd = openat(w->procfd, path, O_RDONLY);
  }

  if (fd < 0)
    return;

  int batched = w->batch && (w->pending == 0 || fd == w->lo + w->pending);

  if (batched) {
    if (!w->pending)
      w->lo = fd;
    ++w->pending;
  }

  size_t need = (size_t)p->len + 1 + CMD_BUF_SIZE + 1;

  if (need > OUT_BUF_SIZE - w->outpos)
    flush(w);

  size_t start = w->outpos;

  memcpy(w->out + w->outpos, p->pid, p->len);
  w->outpos += p->len;
  w->out[w->outpos++] = ' ';

  char *dst = w->out + w->outpos;
  ssize_t n;

  do {
    n = read(fd, dst, CMD_BUF_SIZE);
  } while (n < 0 && errno == EINTR);

  if (batched) {
    if (w->pending >= CLOSE_BATCH)
      close_pending(w);
  } else {
    close(fd);
  }

  if (n < 0) {
    w->outpos = start;
    return;
  }

  if (n > 0) {
    /* One record per line: a '\n' inside an argument must not be able to
     * forge a second "pid cmdline" record for the root-run caller. */
    for (ssize_t i = 0; i < n; ++i)
      if (dst[i] == '\0' || dst[i] == '\n')
        dst[i] = ' ';

    w->outpos += (size_t)n;

    if (w->out[w->outpos - 1] == ' ')
      w->outpos--;
  }

  if (have_filter && !accept_record(w, start, p->len)) {
    w->outpos = start;
    return;
  }

  w->out[w->outpos++] = '\n';
}

static void *worker_main(void *arg) {
  struct worker *w = arg;

  for (;;) {
    size_t base =
        atomic_fetch_add_explicit(w->next, w->chunk, memory_order_relaxed);

    if (base >= w->count)
      break;

    size_t end = base + w->chunk;

    if (end > w->count)
      end = w->count;

    for (size_t i = base; i < end; ++i)
      process_one(w, &w->items[i]);
  }

  close_pending(w);
  flush(w);
  return NULL;
}

int main(int argc, char **argv) {
  int check_only = 0;

  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "-n")) /* validate the patterns and exit */
      check_only = 1;
    else if (i + 1 < argc && !strcmp(argv[i], "-m"))
      game_pat = argv[++i], have_filter = 1;
    else if (i + 1 < argc && !strcmp(argv[i], "-x"))
      excl_pat = argv[++i], have_excl = 1;
    else
      return 2;
  }

  if (have_excl && !have_filter)
    return 2;

  if (check_only)
    return (!have_filter ||
            (!regcomp(&re_game, game_pat, REG_EXTENDED | REG_NOSUB) &&
             (!have_excl ||
              !regcomp(&re_excl, excl_pat, REG_EXTENDED | REG_NOSUB))))
               ? 0
               : 2;

  if (have_filter) {
    if (!extract_literals(game_pat))
      nlits = 0, poolpos = 0;

    self_len = (size_t)snprintf(self_pid, sizeof(self_pid), "%d", (int)getpid());
  }

  int procfd = open("/proc", O_RDONLY | O_DIRECTORY);

  if (procfd < 0)
    return 1;

  size_t count = 0;

  for (;;) {
    long n = syscall(SYS_getdents64, procfd, dirbuf, GETDENTS_BUF_SIZE);

    if (n == 0)
      break;

    if (n < 0) {
      if (errno == EINTR)
        continue;
      return 1;
    }

    for (size_t pos = 0; pos < (size_t)n;) {
      struct linux_dirent64 *e = (void *)(dirbuf + pos);

      if (!e->reclen)
        break;

      const char *s = e->name;
      size_t len = 0;

      while (s[len] >= '0' && s[len] <= '9')
        ++len;

      if (len && len < 16 && s[len] == '\0' && count < MAX_PIDS) {
        memcpy(items[count].pid, s, len + 1);
        items[count].len = (uint8_t)len;
        ++count;
      }

      pos += e->reclen;
    }

    if (count == MAX_PIDS)
      break;
  }

  if (!count)
    return 0;

  size_t nworkers = 1;

  if (count >= 2 * MIN_PER_WORKER) {
    cpu_set_t set;
    size_t cpus = 1;

    if (sched_getaffinity(0, sizeof(set), &set) == 0)
      cpus = (size_t)CPU_COUNT(&set);

    nworkers = cpus;

    if (nworkers > MAX_WORKERS)
      nworkers = MAX_WORKERS;

    if (nworkers > count / MIN_PER_WORKER)
      nworkers = count / MIN_PER_WORKER;

    if (nworkers < 1)
      nworkers = 1;
  }

  _Atomic size_t next = 0;
  size_t chunk = count / (nworkers * 8);

  if (chunk < 1)
    chunk = 1;

  struct worker workers[MAX_WORKERS];
  pthread_t threads[MAX_WORKERS];

  for (size_t i = 0; i < nworkers; ++i) {
    workers[i].procfd = procfd;
    workers[i].items = items;
    workers[i].count = count;
    workers[i].next = &next;
    workers[i].chunk = chunk;
    workers[i].out = outbufs[i];
    workers[i].outpos = 0;
    workers[i].batch = (nworkers == 1); /* fd numbers race across threads */
    workers[i].lo = 0;
    workers[i].pending = 0;
  }

  size_t created = 0;

  for (size_t i = 1; i < nworkers; ++i) {
    pthread_attr_t attr;

    pthread_attr_init(&attr);
    /* Caller-supplied stack: no mmap, no guard-page mprotect, no munmap. */
    pthread_attr_setstack(&attr, stacks[i], WORKER_STACK);

    int rc = pthread_create(&threads[created], &attr, worker_main, &workers[i]);

    pthread_attr_destroy(&attr);

    if (rc)
      break;

    ++created;
  }

  worker_main(&workers[0]);

  for (size_t i = 0; i < created; ++i)
    pthread_join(threads[i], NULL);

  _exit(0);
}
