/* Alternating A/B/... wall-time runner.
 * usage: abrun ROUNDS WARMUP PREP_CMD 'cmdA args' 'cmdB args' ...
 * Each round runs PREP_CMD (via /bin/sh -c, untimed) before every variant,
 * then the variant (argv split on spaces, execv'd directly, stdout/stderr to
 * /dev/null), timed with CLOCK_MONOTONIC. Variant order alternates per round
 * (ABAB.. for round 0, BABA.. reversed on odd rounds).
 * $ABRUN_CPU: pin only the timed child to that CPU (prep runs unpinned).
 * Prints per variant: median, min, max, q1, q3 in microseconds, and writes raw
 * samples to $ABRUN_RAW (if set). */
#define _GNU_SOURCE
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now_us(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e6 + t.tv_nsec / 1e3;
}

static int run_sh(const char *cmd) {
  pid_t p = fork();
  if (!p) { execl("/bin/sh", "sh", "-c", cmd, (char *)NULL); _exit(127); }
  int st; waitpid(p, &st, 0); return st;
}

static double run_timed(char **argv) {
  double t0 = now_us();
  pid_t p = fork();
  if (!p) {
    const char *cpu = getenv("ABRUN_CPU");
    if (cpu) {
      cpu_set_t set;
      CPU_ZERO(&set);
      CPU_SET(atoi(cpu), &set);
      sched_setaffinity(0, sizeof set, &set);
    }
    int fd = open("/dev/null", O_WRONLY);
    dup2(fd, 1); dup2(fd, 2);
    execv(argv[0], argv); _exit(127);
  }
  int st; waitpid(p, &st, 0);
  return now_us() - t0;
}

static int cmp(const void *a, const void *b) {
  double x = *(const double *)a, y = *(const double *)b;
  return x < y ? -1 : x > y;
}

int main(int argc, char **argv) {
  if (argc < 5) { fprintf(stderr, "usage\n"); return 2; }
  int rounds = atoi(argv[1]), warm = atoi(argv[2]);
  const char *prep = argv[3];
  int nv = argc - 4;
  char **av[16];
  for (int v = 0; v < nv; v++) {
    char *s = strdup(argv[4 + v]);
    av[v] = calloc(64, sizeof(char *));
    int k = 0;
    for (char *t = strtok(s, " "); t && k < 63; t = strtok(NULL, " ")) av[v][k++] = t;
  }
  double *res[16];
  for (int v = 0; v < nv; v++) res[v] = calloc(rounds, sizeof(double));
  for (int r = -warm; r < rounds; r++) {
    for (int j = 0; j < nv; j++) {
      int v = ((r & 1) ? nv - 1 - j : j);
      run_sh(prep);
      double t = run_timed(av[v]);
      if (r >= 0) res[v][r] = t;
    }
  }
  const char *raw = getenv("ABRUN_RAW");
  FILE *rf = raw ? fopen(raw, "w") : NULL;
  for (int v = 0; v < nv; v++) {
    if (rf) {
      fprintf(rf, "%s", argv[4 + v]);
      for (int r = 0; r < rounds; r++) fprintf(rf, " %.1f", res[v][r]);
      fprintf(rf, "\n");
    }
    qsort(res[v], rounds, sizeof(double), cmp);
    double med = rounds % 2 ? res[v][rounds / 2] : (res[v][rounds / 2 - 1] + res[v][rounds / 2]) / 2;
    printf("%-60s median %9.1f us  min %9.1f  max %9.1f  q1 %9.1f  q3 %9.1f  n=%d\n",
           argv[4 + v], med, res[v][0], res[v][rounds - 1], res[v][rounds / 4],
           res[v][(3 * rounds) / 4], rounds);
  }
  if (rf) fclose(rf);
  return 0;
}
