/* CPU cost of the syscalls in a gameboostd per-process check, measured with
 * CLOCK_THREAD_CPUTIME_ID over many iterations (interleaved, repeated).
 * Usage: sysbench SLEEPER CORPUS.argv ITERS
 * Ops (each over ITERS distinct-ish pids, cycling through the sets):
 *   kill_live   kill(pid, 0) on a running process
 *   kill_dead   kill(pid, 0) on a reaped pid           (ESRCH)
 *   open_dead   openat(/proc, "PID/cmdline") on a reaped pid (ENOENT)
 *   open_close  openat + close on a running process
 *   orc         openat + read(4095) + close            (pristine check)
 *   or_batch    openat + read, closes batched with close_range per 64
 *   waitpid     waitpid(-1, WNOHANG) with no children  (ECHILD)
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define NL 400
static pid_t live[NL], dead[NL];
static int procfd;
static char buf[4096];

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t);
  return t.tv_sec * 1e9 + t.tv_nsec;
}

static void path(char *p, pid_t pid) { sprintf(p, "%d/cmdline", (int)pid); }

int main(int argc, char **argv) {
  int iters = atoi(argv[3]);
  FILE *f = fopen(argv[2], "r");
  char *s = NULL;
  size_t cap = 0;
  ssize_t k;
  int n = 0;
  while (n < NL && (k = getline(&s, &cap, f)) > 0) {
    s[--k] = 0;
    char *av[512];
    int c = 0;
    for (char *p = s, *q; c < 511; p = q + 1) {
      av[c++] = p;
      if (!(q = strchr(p, '\x1f')))
        break;
      *q = 0;
    }
    av[c] = NULL;
    pid_t pid = fork();
    if (!pid) {
      execv(argv[1], av);
      _exit(127);
    }
    live[n++] = pid;
  }
  for (int i = 0; i < NL; ++i) {
    pid_t p = fork();
    if (!p)
      _exit(0);
    waitpid(p, NULL, 0);
    dead[i] = p;
  }
  usleep(300000);
  procfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  /* children are reaped/never waited: the live ones are children, so for the
   * waitpid op use a grandchild-free helper: fork a process that measures it */
  static char lp[NL][24], dp[NL][24];
  for (int i = 0; i < NL; ++i)
    path(lp[i], live[i]), path(dp[i], dead[i]);

  const char *names[] = {"kill_live", "kill_dead", "open_dead", "open_close",
                         "orc", "or_batch"};
  enum { NOPS = 6 };
  double best[NOPS][32];
  int rep = 0;
  for (rep = 0; rep < 15; ++rep)
    for (int op = 0; op < NOPS; ++op) {
      double t0 = now();
      int fds = 0, lo = -1;
      for (int i = 0; i < iters; ++i) {
        int j = i % NL;
        switch (op) {
        case 0:
          kill(live[j], 0);
          break;
        case 1:
          kill(dead[j], 0);
          break;
        case 2: {
          int fd = openat(procfd, dp[j], O_RDONLY | O_CLOEXEC);
          if (fd >= 0)
            close(fd);
          break;
        }
        case 3: {
          int fd = openat(procfd, lp[j], O_RDONLY | O_CLOEXEC);
          close(fd);
          break;
        }
        case 4: {
          int fd = openat(procfd, lp[j], O_RDONLY | O_CLOEXEC);
          (void)!read(fd, buf, 4095);
          close(fd);
          break;
        }
        case 5: {
          int fd = openat(procfd, lp[j], O_RDONLY | O_CLOEXEC);
          (void)!read(fd, buf, 4095);
          if (!fds)
            lo = fd;
          if (++fds == 64) {
            syscall(SYS_close_range, lo, lo + fds - 1, 0);
            fds = 0;
          }
          break;
        }
        }
      }
      if (fds)
        syscall(SYS_close_range, lo, lo + fds - 1, 0);
      best[op][rep] = (now() - t0) / iters;
    }
  /* waitpid with no children, in a child process that has none */
  pid_t c = fork();
  if (!c) {
    double w[15];
    for (int r = 0; r < 15; ++r) {
      double t0 = now();
      for (int i = 0; i < iters; ++i)
        waitpid(-1, NULL, WNOHANG);
      w[r] = (now() - t0) / iters;
    }
    for (int i = 0; i < 15; ++i)
      for (int j = i + 1; j < 15; ++j)
        if (w[j] < w[i]) {
          double t = w[i];
          w[i] = w[j], w[j] = t;
        }
    printf("%-10s median %7.1f ns  min %7.1f  max %7.1f  (15 reps x %d)\n",
           "waitpid", w[7], w[0], w[14], iters);
    fflush(stdout);
    _exit(0);
  }
  waitpid(c, NULL, 0);
  for (int op = 0; op < NOPS; ++op) {
    double *v = best[op];
    for (int i = 0; i < rep; ++i)
      for (int j = i + 1; j < rep; ++j)
        if (v[j] < v[i]) {
          double t = v[i];
          v[i] = v[j], v[j] = t;
        }
    printf("%-10s median %7.1f ns  min %7.1f  max %7.1f  (%d reps x %d)\n",
           names[op], v[rep / 2], v[0], v[rep - 1], rep, iters);
  }
  for (int i = 0; i < NL; ++i)
    kill(live[i], SIGKILL);
  while (wait(NULL) > 0)
    ;
  return 0;
}
