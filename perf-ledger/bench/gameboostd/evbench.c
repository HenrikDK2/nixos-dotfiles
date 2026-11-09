/* Per-exec-event pipeline harness for gameboostd.c: drain_events() +
 * check_pending() on real processes, fed through a real netlink socket
 * (NETLINK_USERSOCK unicast instead of the proc connector, which would also
 * deliver every other exec on this shared machine).
 *
 * Build:  cc -O2 -DGBD_SRC='"/path/to/gameboostd.c"' evbench.c -o evbench
 * Usage:  evbench SLEEPER CORPUS.argv ROUNDS K LIVE_PCT DUP_PCT [SEED]
 *   SLEEPER   a program that just pause()s; LIVE processes are started as
 *             execv(SLEEPER, corpus argv) so /proc/PID/cmdline is the
 *             corpus line
 *   ROUNDS    measured rounds; each round sends K exec events, then runs
 *             drain_events() and check_pending() with every check due
 *   LIVE_PCT  % of events whose process is still running at check time
 *             (the rest are reaped PIDs: short-lived programs)
 *   DUP_PCT   % of events that repeat the previous event's PID right away
 *             (one process exec'ing twice: Nix wrapper -> wrapped binary,
 *             env -> interpreter, systemd-executor -> service binary)
 * Prints: events, checks (stat_checks), CPU ns per event of the measured part
 * (CLOCK_THREAD_CPUTIME_ID around drain+check only), and the event stream
 * is deterministic for a given SEED. Count syscalls of the measured part with
 * strace by differencing two ROUNDS values (see README.md).
 */
#define _GNU_SOURCE
#define main gbd_main
#include GBD_SRC
#undef main

#define NLIVE_MAX 512

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

int main(int argc, char **argv) {
  if (argc < 7) {
    fprintf(stderr,
            "usage: evbench SLEEPER CORPUS ROUNDS K LIVE_PCT DUP_PCT [SEED]\n");
    return 2;
  }
  int rounds = atoi(argv[3]), K = atoi(argv[4]);
  int live_pct = atoi(argv[5]), dup_pct = atoi(argv[6]);
  if (argc > 7)
    rng += (unsigned long long)atoll(argv[7]) * 0x9E3779B97F4A7C15ULL;

  spawn_live(argv[1], argv[2], NLIVE_MAX);
  make_dead(4096);
  usleep(300000); /* let every sleeper finish its execv */

  self = getpid();
  procfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);

  /* Patterns: GAME/EXCL from the environment (as main.sh builds them). */
  split_alts(getenv("GAME_RE"), &games);
  split_alts(getenv("EXCL_RE"), &excls);

  int rx = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK,
                  NETLINK_USERSOCK);
  int tx = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_USERSOCK);
  struct sockaddr_nl ra = {.nl_family = AF_NETLINK, .nl_pid = 0x6b000000u | (unsigned)getpid()};
  struct sockaddr_nl ta = {.nl_family = AF_NETLINK, .nl_pid = 0x6c000000u | (unsigned)getpid()};
  int rcv = 1 << 20;
  setsockopt(rx, SOL_SOCKET, SO_RCVBUFFORCE, &rcv, sizeof rcv);
  if (bind(rx, (void *)&ra, sizeof ra) || bind(tx, (void *)&ta, sizeof ta) ||
      connect(tx, (void *)&ra, sizeof ra)) {
    perror("netlink");
    return 1;
  }
  sock = rx;
  cur_mask = PROC_EVENT_EXEC;

  static struct ev evs[4096];
  static struct mmsghdr mm[4096];
  static struct iovec io[4096];
  if (K > 4096)
    K = 4096;

  long long ns = 0;
  static double per[100000];
  unsigned long evtotal = 0;
  pid_t prev = 0;
  for (int r = 0; r < rounds; ++r) {
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
    for (int sent = 0; sent < K;) {
      int s = sendmmsg(tx, mm + sent, (unsigned)(K - sent), 0);
      if (s <= 0) {
        perror("sendmmsg");
        return 1;
      }
      sent += s;
    }

    struct timespec a, b;
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &a);
    evtotal += (unsigned long)drain_events();
    for (int i = 0; i < npending; ++i)
      pending[i].due = 0;
    (void)check_pending();
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &b);
    long long d = (b.tv_sec - a.tv_sec) * 1000000000LL + (b.tv_nsec - a.tv_nsec);
    ns += d;
    if (r < 100000)
      per[r] = (double)d / K;
    if (npending) {
      fprintf(stderr, "pending left: %d\n", npending);
      return 1;
    }
  }
  int nr = rounds < 100000 ? rounds : 100000;
  for (int i = 1; i < nr; ++i) /* insertion sort: median of rounds */
    for (int j = i; j > 0 && per[j] < per[j - 1]; --j) {
      double t = per[j];
      per[j] = per[j - 1], per[j - 1] = t;
    }
  /* field 6: mean ns/event; field 8: median over rounds of ns per sent event
   * (robust against bursts of load from other processes) */
  printf("events %lu checks %lu ns/event %.1f median_round %.1f\n", evtotal,
         stat_checks, (double)ns / (double)evtotal, per[nr / 2]);

  for (int i = 0; i < nlive; ++i)
    kill(live[i], SIGKILL);
  while (wait(NULL) > 0)
    ;
  return 0;
}
