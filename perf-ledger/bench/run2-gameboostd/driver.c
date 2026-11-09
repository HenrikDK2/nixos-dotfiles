/* Test driver for gameboostd.c: runs its hot paths without root or netlink.
 *
 * Built as: cc FLAGS -DGBD_SRC='"path/to/gameboostd.c"' driver.c -o drv
 * gameboostd's main() is renamed (gbd_main) and its kill() is redirected to
 * an oracle that says which fake pids are alive (and still makes one real
 * kill() syscall, so syscall counts stay the same as in the daemon).
 *
 *   drv scan   GAME_ERE EXCL_ERE PROCDIR REPS
 *       full_scan() REPS times over a fake /proc tree; prints the result.
 *   drv events GAME_ERE EXCL_ERE PROCDIR EVFILE ROUNDS [CHUNK]
 *       Per round: send every event of EVFILE as a proc-connector datagram
 *       (exec, plus a rename for Wine pids) through a socketpair in chunks of
 *       CHUNK (default 50), drain_events() after each chunk, then make all checks due and run
 *       check_pending() (twice: renames queue a second check). Prints a
 *       transcript of what was checked/watched/hit.
 *   drv start  GAME_ERE EXCL_ERE REPS
 *       split_alts() of both patterns (startup), REPS times.
 *
 * Measured functions are wrapped in noinline bench_* functions, for
 * callgrind --toggle-collect=bench_*.
 */
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <dirent.h>

static unsigned char alive_map[1 << 18];
static int fake_kill(pid_t pid, int sig) {
  int alive = pid > 0 && pid < (1 << 18) && alive_map[pid];
  /* one real syscall, like the daemon: self is alive, -1 pid fails */
  return (int)syscall(SYS_kill, alive ? getpid() : 0x3ffffff0, sig);
}
#define kill fake_kill
#define main gbd_main
#include GBD_SRC
#undef main
#undef kill

__attribute__((noinline)) static void bench_scan(struct found *f) {
  full_scan(f, 0);
}
__attribute__((noinline)) static void bench_drain(void) { (void)drain_events(); }
__attribute__((noinline)) static int bench_check(void) { return check_pending(); }
__attribute__((noinline)) static void bench_start(const char *g, const char *x) {
  split_alts(g, &games);
  split_alts(x, &excls);
}

static void mark_alive(const char *dir) {
  DIR *d = opendir(dir);
  struct dirent *e;
  while ((e = readdir(d))) {
    long p = atol(e->d_name);
    if (p > 0 && p < (1 << 18))
      alive_map[p] = 1;
  }
  closedir(d);
}

/* CPU (user+sys) and wall clock, in ns, for the timing line on stderr. */
#include <sys/resource.h>
#include <malloc.h>
static long long cpu_ns(void) {
  struct rusage u;
  getrusage(RUSAGE_SELF, &u);
  return (u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1000000000LL +
         (u.ru_utime.tv_usec + u.ru_stime.tv_usec) * 1000LL;
}
static long long user_ns(void) {
  struct rusage u;
  getrusage(RUSAGE_SELF, &u);
  return u.ru_utime.tv_sec * 1000000000LL + u.ru_utime.tv_usec * 1000LL;
}
static long long wall_ns(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000000000LL + t.tv_nsec;
}
static long long t_wall, t_cpu, t_user;
static void tstart(void) { t_wall = wall_ns(), t_cpu = cpu_ns(), t_user = user_ns(); }
static void tstop(const char *what, long ops) {
  fprintf(stderr, "TIME %s wall_ns_per_op %.1f cpu_ns_per_op %.1f user_ns_per_op %.1f\n",
          what, (double)(wall_ns() - t_wall) / ops, (double)(cpu_ns() - t_cpu) / ops,
          (double)(user_ns() - t_user) / ops);
}

struct ev {
  pid_t pid;
  int alive;
  char comm[16];
};

static int send_ev(int fd, pid_t pid, const char *comm) {
  struct __attribute__((packed)) {
    struct nlmsghdr nl;
    struct cn_msg cn;
    struct proc_event ev;
  } m;
  memset(&m, 0, sizeof m);
  m.nl.nlmsg_len = sizeof m;
  m.nl.nlmsg_type = NLMSG_DONE;
  m.cn.id.idx = CN_IDX_PROC;
  m.cn.id.val = CN_VAL_PROC;
  m.cn.len = sizeof m.ev;
  if (comm) {
    m.ev.what = PROC_EVENT_COMM;
    m.ev.event_data.comm.process_pid = pid;
    m.ev.event_data.comm.process_tgid = pid;
    strncpy(m.ev.event_data.comm.comm, comm, 15);
  } else {
    m.ev.what = PROC_EVENT_EXEC;
    m.ev.event_data.exec.process_pid = pid;
    m.ev.event_data.exec.process_tgid = pid;
  }
  return send(fd, &m, sizeof m, 0) == sizeof m ? 0 : -1;
}

int main(int argc, char **argv) {
  if (argc < 4)
    return 2;
  const char *gp = argv[2], *xp = argv[3];

  if (!strcmp(argv[1], "start")) {
    int reps = atoi(argv[4]);
    for (int r = 0; r < reps; ++r)
      bench_start(gp, xp);
    printf("games=%d excls=%d\n", games.n, excls.n);
    for (int i = 0; i < games.n; ++i)
      printf("g %d lit=%.*s anc=%zu\n", i, (int)games.v[i].litn,
             games.v[i].lit ? games.v[i].lit : "", games.v[i].anc);
    for (int i = 0; i < excls.n; ++i)
      printf("x %d lit=%.*s anc=%zu\n", i, (int)excls.v[i].litn,
             excls.v[i].lit ? excls.v[i].lit : "", excls.v[i].anc);
    return 0;
  }

  split_alts(gp, &games);
  split_alts(xp, &excls);
  self = getpid();
  procfd = open(argv[4], O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (procfd < 0)
    return 1;
  mark_alive(argv[4]);

  if (!strcmp(argv[1], "scan")) {
    static struct found f;
    int reps = atoi(argv[5]);
    full_scan(&f, 0); /* warm-up (lazy regcomp, DFA states): not measured */
    tstart();
    for (int r = 0; r < reps; ++r)
      bench_scan(&f);
    tstop("scan", reps);
    fprintf(stderr, "HEAP in_use_bytes %zu\n", mallinfo2().uordblks);
    printf("found %d first_cmd=%s\n", f.n, f.n ? f.first_cmd : "");
    for (int i = 0; i < f.n; ++i)
      printf("pid %d\n", (int)f.pid[i]);
    return 0;
  }

  if (!strcmp(argv[1], "events")) {
    static struct ev evs[4096];
    int nev = 0;
    FILE *fp = fopen(argv[5], "r");
    char comm[64];
    while (nev < 4096 &&
           fscanf(fp, "%d %d %63s", &evs[nev].pid, &evs[nev].alive, comm) == 3) {
      comm[15] = 0;
      strcpy(evs[nev].comm, strcmp(comm, "-") ? comm : "");
      ++nev;
    }
    fclose(fp);
    int rounds = atoi(argv[6]);
    int chunk = argc > 7 ? atoi(argv[7]) : 50; /* events per drain_events() */
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0, sv))
      return 1;
    int big = 4 << 20;
    setsockopt(sv[0], SOL_SOCKET, SO_RCVBUFFORCE, &big, sizeof big);
    setsockopt(sv[1], SOL_SOCKET, SO_SNDBUFFORCE, &big, sizeof big);
    setsockopt(sv[0], SOL_SOCKET, SO_SNDBUFFORCE, &big, sizeof big);
    sock = sv[0];
    unsigned long hits = 0, maxwatch = 0;
    char junk[256];
    /* round -1: warm-up (lazy regcomp, DFA states), not measured */
    for (int r = -1; r < rounds; ++r) {
      int warm = r < 0;
      if (r == 0)
        tstart(); /* includes the driver's own sends: see README */
      npending = 0;
      nwatch = 0;
      cur_mask = PROC_EVENT_EXEC;
      game_mode = 0;
      int sent = 0;
      for (int i = 0; i < nev; ++i) {
        send_ev(sv[1], evs[i].pid, NULL);
        ++sent;
        if (sent % chunk == 0)
          warm ? (void)drain_events() : bench_drain();
      }
      warm ? (void)drain_events() : bench_drain();
      for (int i = 0; i < npending; ++i)
        pending[i].due = 0;
      hits += warm ? check_pending() : bench_check();
      if ((unsigned long)nwatch > maxwatch)
        maxwatch = nwatch;
      if (r == 0) {
        printf("after check1: npending=%d nwatch=%d mask=%u\n", npending, nwatch,
               cur_mask);
        for (int i = 0; i < nwatch; ++i)
          printf("watch %d dl=%d\n", (int)watch[i].tgid, watch[i].deadline > 0);
      }
      /* renames for watched Wine pids */
      for (int i = 0; i < nev; ++i)
        if (evs[i].comm[0])
          send_ev(sv[1], evs[i].pid, evs[i].comm);
      warm ? (void)drain_events() : bench_drain();
      for (int i = 0; i < npending; ++i)
        pending[i].due = 0;
      hits += warm ? check_pending() : bench_check();
      if (r == 0)
        printf("after check2: npending=%d nwatch=%d\n", npending, nwatch);
      while (recv(sv[1], junk, sizeof junk, MSG_DONTWAIT) > 0)
        ; /* cn_control() sends from listen_for() */
    }
    tstop("event", (long)rounds * nev);
    fprintf(stderr, "HEAP in_use_bytes %zu\n", mallinfo2().uordblks);
    printf("events=%lu renames=%lu checks=%lu hits=%lu maxwatch=%lu\n",
           stat_events, stat_renames, stat_checks, hits, maxwatch);
    return 0;
  }
  return 2;
}
