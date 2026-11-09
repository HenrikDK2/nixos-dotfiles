/* Paired A/B CPU-time benchmark: two copies of gameboostd.c (core.c built
 * with SUF=A and SUF=B) run alternately in one process, round by round, on
 * the same processes and the same events, so load from other processes on
 * this shared machine hits both alike. Reports per-round CPU time
 * (CLOCK_THREAD_CPUTIME_ID, includes kernel time of the syscalls).
 *
 *   pair ev   SLEEPER CORPUS.argv ROUNDS K LIVE_PCT DUP_PCT [SEED]
 *   pair scan SLEEPER CORPUS.argv ROUNDS NPROCS
 *
 * ev:   each round sends K exec events over a NETLINK_USERSOCK socket, then
 *       runs ev_round (drain_events + every check due). Events are for
 *       running processes (LIVE_PCT %, started as execv(SLEEPER, corpus
 *       argv)) or reaped PIDs; DUP_PCT % repeat the previous PID.
 * scan: NPROCS extra sleepers with corpus cmdlines, then full_scan() per
 *       round.
 * Output: median ns (per event / per scan) for A and B, and the median and
 * IQR of the per-round paired difference (B-A)/A in %.
 * GAME_RE / EXCL_RE come from the environment.
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
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

void core_init_A(int, const char *, const char *);
void core_init_B(int, const char *, const char *);
int ev_round_A(void), ev_round_B(void);
int ev_left_A(void), ev_left_B(void);
int scan_A(void), scan_B(void);

#define NLIVE_MAX 2048

static unsigned long long rng = 88172645463325252ULL;
static unsigned rnd(void) {
  rng ^= rng << 13, rng ^= rng >> 7, rng ^= rng << 17;
  return (unsigned)(rng >> 11);
}

static pid_t live[NLIVE_MAX];
static int nlive;

static void spawn_live(const char *sleeper, const char *corpus, int want) {
  FILE *f = fopen(corpus, "r");
  if (!f) {
    perror(corpus);
    exit(1);
  }
  char *s = NULL;
  size_t cap = 0;
  ssize_t k;
  while (nlive < want) {
    if ((k = getline(&s, &cap, f)) <= 0) { /* wrap around the corpus */
      rewind(f);
      continue;
    }
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
      execv(sleeper, argv);
      _exit(127);
    }
    live[nlive++] = pid;
  }
  fclose(f);
}

static pid_t dead[4096];
static int ndead;

static void make_dead(int want) {
  while (ndead < want) {
    pid_t p = fork();
    if (p == 0)
      _exit(0);
    waitpid(p, NULL, 0);
    dead[ndead++] = p;
  }
}

struct ev {
  struct nlmsghdr nl;
  struct cn_msg cn;
  struct proc_event pe;
} __attribute__((packed));

static double cpu_ns(void) {
  struct timespec t;
  clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t);
  return t.tv_sec * 1e9 + t.tv_nsec;
}

static int cmpd(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return x < y ? -1 : x > y;
}

static void report(const char *unit, double *a, double *b, int n) {
  static double d[100000];
  for (int i = 0; i < n; ++i)
    d[i] = (b[i] - a[i]) / a[i] * 100;
  qsort(a, n, sizeof *a, cmpd);
  qsort(b, n, sizeof *b, cmpd);
  qsort(d, n, sizeof *d, cmpd);
  printf("A %s median %.1f (IQR %.1f-%.1f)  B median %.1f (IQR %.1f-%.1f)  "
         "paired (B-A)/A median %+.2f%% (IQR %+.2f..%+.2f%%)  rounds %d\n",
         unit, a[n / 2], a[n / 4], a[3 * n / 4], b[n / 2], b[n / 4],
         b[3 * n / 4], d[n / 2], d[n / 4], d[3 * n / 4], n);
}

static void cleanup(void) {
  for (int i = 0; i < nlive; ++i)
    kill(live[i], SIGKILL);
  while (wait(NULL) > 0)
    ;
}

int main(int argc, char **argv) {
  if (argc < 6) {
    fprintf(stderr, "usage: pair ev SLEEPER CORPUS ROUNDS K LIVE DUP [SEED]\n"
                    "       pair scan SLEEPER CORPUS ROUNDS NPROCS\n");
    return 2;
  }
  const char *mode = argv[1];
  int rounds = atoi(argv[4]);
  if (rounds > 100000)
    rounds = 100000;
  static double ta[100000], tb[100000];

  if (!strcmp(mode, "scan")) {
    spawn_live(argv[2], argv[3], atoi(argv[5]));
    usleep(500000);
    core_init_A(-1, getenv("GAME_RE"), getenv("EXCL_RE"));
    core_init_B(-1, getenv("GAME_RE"), getenv("EXCL_RE"));
    int fa = scan_A(), fb = scan_B(); /* warm: lazy regex compiles */
    if (fa != fb) {
      fprintf(stderr, "scan results differ: A %d B %d\n", fa, fb);
      return 1;
    }
    for (int r = 0; r < rounds; ++r) {
      for (int k = 0; k < 2; ++k) {
        int b = (r + k) % 2;
        double t0 = cpu_ns();
        int found = b ? scan_B() : scan_A();
        double t = cpu_ns() - t0;
        if (found != fa) {
          fprintf(stderr, "found %d, expected %d\n", found, fa);
        }
        (b ? tb : ta)[r] = t;
      }
    }
    report("ns/scan", ta, tb, rounds);
    cleanup();
    return 0;
  }

  int K = atoi(argv[5]), live_pct = atoi(argv[6]), dup_pct = atoi(argv[7]);
  if (argc > 8)
    rng += (unsigned long long)atoll(argv[8]) * 0x9E3779B97F4A7C15ULL;
  if (K > 1024)
    K = 1024;
  spawn_live(argv[2], argv[3], 512);
  make_dead(4096);
  usleep(300000);

  int rx = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK,
                  NETLINK_USERSOCK);
  int tx = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_USERSOCK);
  struct sockaddr_nl ra = {.nl_family = AF_NETLINK,
                           .nl_pid = 0x6b000000u | (unsigned)getpid()};
  struct sockaddr_nl xa = {.nl_family = AF_NETLINK,
                           .nl_pid = 0x6c000000u | (unsigned)getpid()};
  int rcv = 1 << 20;
  setsockopt(rx, SOL_SOCKET, SO_RCVBUFFORCE, &rcv, sizeof rcv);
  if (bind(rx, (void *)&ra, sizeof ra) || bind(tx, (void *)&xa, sizeof xa) ||
      connect(tx, (void *)&ra, sizeof ra)) {
    perror("netlink");
    return 1;
  }
  core_init_A(rx, getenv("GAME_RE"), getenv("EXCL_RE"));
  core_init_B(rx, getenv("GAME_RE"), getenv("EXCL_RE"));

  static struct ev evs[1024];
  static struct mmsghdr mm[1024];
  static struct iovec io[1024];
  pid_t prev = 0;
  for (int r = -2; r < rounds; ++r) { /* two warm-up rounds */
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
      io[i] = (struct iovec){&evs[i], sizeof evs[i]};
      mm[i].msg_hdr = (struct msghdr){.msg_iov = &io[i], .msg_iovlen = 1};
    }
    for (int k = 0; k < 2; ++k) {
      int b = ((r & 1) + k) % 2; /* alternate which variant goes first */
      for (int sent = 0; sent < K;) {
        int s = sendmmsg(tx, mm + sent, (unsigned)(K - sent), 0);
        if (s <= 0) {
          perror("sendmmsg");
          return 1;
        }
        sent += s;
      }
      double t0 = cpu_ns();
      int got = b ? ev_round_B() : ev_round_A();
      double t = cpu_ns() - t0;
      if (got != K || (b ? ev_left_B() : ev_left_A())) {
        fprintf(stderr, "round %d: got %d of %d events, %d left\n", r, got, K,
                b ? ev_left_B() : ev_left_A());
        return 1;
      }
      if (r >= 0)
        (b ? tb : ta)[r] = t / K;
    }
  }
  report("ns/event", ta, tb, rounds);
  cleanup();
  return 0;
}
