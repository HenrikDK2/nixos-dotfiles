/* Drive an e2e_daemon (gameboostd with a fake connector, see e2e.c) through
 * its real main loop and measure it from outside.
 *
 * Usage: e2e_drive DAEMON SLEEPER CORPUS.argv BURSTS K LIVE_PCT DUP_PCT GAP_MS
 *   Each burst: SIGSTOP the daemon (only if K > 1), queue K exec events (LIVE_PCT % for
 *   running sleepers with corpus cmdlines, else reaped PIDs; DUP_PCT %
 *   repeat the previous PID), SIGCONT, wait GAP_MS (> FIRST_CHECK_MS, so
 *   each burst is checked before the next one).
 * Prints (for the measured part only, after the daemon's startup scan):
 *   cpu_ns   on-CPU time from /proc/PID/schedstat (user + kernel)
 *   wakeups  voluntary context switches (/proc/PID/status)
 *   and the daemon's own "Stopping: ..." statistics line.
 * Env: GAME_RE, EXCL_RE (patterns); E2E_MEM=1 prints the daemon's Rss/Pss/
 * Private_Dirty/Anonymous (kB, smaps_rollup) at the end; E2E_STRACE=FILE attaches
 * `strace -c -o FILE -p PID` for the measured part.
 */
#define _GNU_SOURCE
#include <linux/cn_proc.h>
#include <linux/connector.h>
#include <linux/netlink.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static unsigned long long rng = 88172645463325252ULL;
static unsigned rnd(void) {
  rng ^= rng << 13, rng ^= rng >> 7, rng ^= rng << 17;
  return (unsigned)(rng >> 11);
}

static pid_t live[512], dead[4096];
static int nlive, ndead;

static void spawn_live(const char *sleeper, const char *corpus, int want) {
  FILE *f = fopen(corpus, "r");
  char *s = NULL;
  size_t cap = 0;
  ssize_t k;
  while (nlive < want && (k = getline(&s, &cap, f)) > 0) {
    if (s[k - 1] == '\n')
      s[--k] = 0;
    char *argv[512];
    int n = 0;
    for (char *p = s, *q; n < 511; p = q + 1) {
      argv[n++] = p;
      if (!(q = strchr(p, '\x1f')))
        break;
      *q = 0;
    }
    argv[n] = NULL;
    pid_t pid = fork();
    if (pid == 0) {
      int null = open("/dev/null", O_RDWR);
      dup2(null, 1);
      dup2(null, 2);
      execv(sleeper, argv);
      _exit(127);
    }
    live[nlive++] = pid;
  }
  fclose(f);
}

static void kill_live(void) {
  for (int i = 0; i < nlive; ++i)
    kill(live[i], SIGKILL);
}

static unsigned long long sched_ns(pid_t p) {
  char path[64];
  unsigned long long ns = 0;
  snprintf(path, sizeof path, "/proc/%d/schedstat", (int)p);
  FILE *f = fopen(path, "r");
  if (f) {
    if (fscanf(f, "%llu", &ns) != 1)
      ns = 0;
    fclose(f);
  }
  return ns;
}

static long vol_cs(pid_t p) {
  char path[64], line[256];
  long v = -1;
  snprintf(path, sizeof path, "/proc/%d/status", (int)p);
  FILE *f = fopen(path, "r");
  while (f && fgets(line, sizeof line, f))
    if (!strncmp(line, "voluntary_ctxt_switches:", 24))
      v = atol(line + 24);
  if (f)
    fclose(f);
  return v;
}

struct ev {
  struct nlmsghdr nl;
  struct cn_msg cn;
  struct proc_event pe;
} __attribute__((packed));

int main(int argc, char **argv) {
  if (argc < 9) {
    fprintf(stderr, "usage: e2e_drive DAEMON SLEEPER CORPUS BURSTS K LIVE_PCT "
                    "DUP_PCT GAP_MS\n");
    return 2;
  }
  int bursts = atoi(argv[4]), K = atoi(argv[5]), live_pct = atoi(argv[6]);
  int dup_pct = atoi(argv[7]), gap = atoi(argv[8]);
  if (K > 1024)
    K = 1024;

  spawn_live(argv[2], argv[3], 256);
  atexit(kill_live);
  while (ndead < 4096) {
    pid_t p = fork();
    if (!p)
      _exit(0);
    waitpid(p, NULL, 0);
    dead[ndead++] = p;
  }

  char stub[] = "/tmp/e2e_stubXXXXXX";
  if (!mkdtemp(stub))
    return 1;
  char flag[128];
  snprintf(flag, sizeof flag, "%s/running.flag", stub);

  unsigned nlpid = 0x6d000000u | (unsigned)getpid();
  char nls[32];
  snprintf(nls, sizeof nls, "%u", nlpid);
  setenv("E2E_NLPID", nls, 1);

  int out[2];
  if (pipe(out))
    return 1;
  pid_t d = fork();
  if (d == 0) {
    dup2(out[1], 1);
    close(out[0]);
    close(out[1]);
    execl(argv[1], argv[1], "-m", getenv("GAME_RE"), "-x", getenv("EXCL_RE"),
          "-d", stub, "-f", flag, (char *)NULL);
    _exit(127);
  }
  close(out[1]);
  FILE *dout = fdopen(out[0], "r");
  char line[8192];
  if (!fgets(line, sizeof line, dout) || !strstr(line, "Watching exec")) {
    fprintf(stderr, "daemon did not start: %s", line);
    kill(d, SIGKILL);
    return 1;
  }
  usleep(500000); /* startup full scan done; daemon idle in poll() */
  if (access(flag, F_OK) == 0) {
    fprintf(stderr, "daemon entered game mode at startup; aborting\n");
    kill(d, SIGTERM);
    return 1;
  }

  pid_t st = 0;
  const char *sf = getenv("E2E_STRACE");
  if (sf) {
    char ps[16];
    snprintf(ps, sizeof ps, "%d", (int)d);
    st = fork();
    if (st == 0) {
      execlp("strace", "strace", "-c", "-o", sf, "-p", ps, (char *)NULL);
      _exit(127);
    }
    usleep(500000);
  }

  int tx = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_USERSOCK);
  struct sockaddr_nl ta = {.nl_family = AF_NETLINK, .nl_pid = nlpid + 1};
  struct sockaddr_nl ra = {.nl_family = AF_NETLINK, .nl_pid = nlpid};
  if (bind(tx, (void *)&ta, sizeof ta) || connect(tx, (void *)&ra, sizeof ra)) {
    perror("netlink");
    return 1;
  }

  unsigned long long ns0 = sched_ns(d);
  long cs0 = vol_cs(d);
  static struct ev evs[1024];
  pid_t prev = 0;
  for (int b = 0; b < bursts; ++b) {
    int stop = K > 1; /* a single event cannot be split: no stop needed */
    if (stop) {
      kill(d, SIGSTOP);
      int stt;
      if (!st)
        waitpid(d, &stt, WUNTRACED);
      else
        usleep(20000); /* traced: strace owns the stop notification */
    }
    for (int i = 0; i < K; ++i) {
      pid_t pid;
      if (prev && (int)(rnd() % 100) < dup_pct)
        pid = prev;
      else if ((int)(rnd() % 100) < live_pct)
        pid = live[rnd() % (unsigned)nlive];
      else
        pid = dead[rnd() % (unsigned)ndead];
      prev = pid;
      memset(&evs[i], 0, sizeof evs[i]);
      evs[i].nl.nlmsg_len = sizeof evs[i];
      evs[i].nl.nlmsg_type = NLMSG_DONE;
      evs[i].cn.id.idx = CN_IDX_PROC;
      evs[i].cn.id.val = CN_VAL_PROC;
      evs[i].cn.len = sizeof evs[i].pe;
      evs[i].pe.what = PROC_EVENT_EXEC;
      evs[i].pe.event_data.exec.process_pid = pid;
      evs[i].pe.event_data.exec.process_tgid = pid;
      if (send(tx, &evs[i], sizeof evs[i], 0) != sizeof evs[i]) {
        perror("send");
        return 1;
      }
    }
    if (stop)
      kill(d, SIGCONT);
    usleep((useconds_t)gap * 1000);
  }
  unsigned long long ns1 = sched_ns(d);
  long cs1 = vol_cs(d);
  if (st) {
    kill(st, SIGINT);
    waitpid(st, NULL, 0);
  }
  if (getenv("E2E_MEM")) { /* the daemon's memory now, from smaps_rollup */
    char path[64], l[256];
    snprintf(path, sizeof path, "/proc/%d/smaps_rollup", (int)d);
    FILE *m = fopen(path, "r");
    while (m && fgets(l, sizeof l, m)) {
      char k[64];
      long v;
      if (sscanf(l, "%63s %ld", k, &v) == 2 &&
          (!strcmp(k, "Rss:") || !strcmp(k, "Pss:") ||
           !strcmp(k, "Private_Dirty:") || !strcmp(k, "Anonymous:")))
        printf("%s %ld ", k, v);
    }
    if (m)
      fclose(m);
  }
  kill(d, SIGTERM);
  printf("cpu_ns %llu wakeups %ld ", ns1 - ns0, cs1 - cs0);
  while (fgets(line, sizeof line, dout))
    if (strstr(line, "Stopping"))
      printf("%s", line);
  waitpid(d, NULL, 0);
  for (int i = 0; i < nlive; ++i)
    kill(live[i], SIGKILL);
  while (wait(NULL) > 0)
    ;
  unlink(flag);
  rmdir(stub);
  return 0;
}
