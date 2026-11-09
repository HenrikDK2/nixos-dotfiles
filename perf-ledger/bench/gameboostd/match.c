/* User-space matching harness for gameboostd.c.
 *
 * Build:  cc -O2 -DGBD_SRC='"/path/to/gameboostd.c"' match.c -o match
 * Usage:  match GAME_RE_FILE EXCL_RE_FILE CORPUS.argv MODE [REPS]
 *   MODE classify  print one char per corpus line: G game, W wine-watch,
 *                  - neither (exactly the decision check_pending makes),
 *                  plus 'g' column for full_scan's is_game.
 *   MODE check     run the check_pending cmdline path (read_cmdline with a
 *                  faked openat/read/close + is_game + wine/exclude test)
 *                  over the corpus REPS times inside bench_check()
 *   MODE scan      same with full_scan's per-process test (is_game only)
 *   MODE cold      one bench_check() pass with nothing compiled yet
 * Corpus lines are argv joined by \x1f; they are turned into the raw
 * NUL-separated /proc/PID/cmdline bytes that the faked read() returns, so
 * the cmdline cleanup in read_cmdline_fd is measured too.
 * Count instructions with
 *   valgrind --tool=callgrind --toggle-collect=bench_check ./match ... check 5
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

static const char *fake_data;
static size_t fake_len;

static int fake_openat(int d, const char *p, int f) {
  (void)d, (void)p, (void)f;
  return 1000;
}
static ssize_t fake_read(int fd, void *b, size_t n) {
  (void)fd;
  size_t k = fake_len < n ? fake_len : n;
  memcpy(b, fake_data, k);
  return (ssize_t)k;
}
static int fake_close(int fd) {
  (void)fd;
  return 0;
}

#define openat(d, p, f) fake_openat(d, p, f)
#define read(fd, b, n) fake_read(fd, b, n)
#define close(fd) fake_close(fd)
#define main gbd_main
#include GBD_SRC
#undef main
#undef openat
#undef read
#undef close

struct line {
  char *raw;
  size_t len;
};
static struct line *L;
static size_t nl;

static void load(const char *path) {
  FILE *f = fopen(path, "r");
  if (!f) {
    perror(path);
    exit(1);
  }
  char *s = NULL;
  size_t cap = 0, ncap = 0;
  ssize_t k;
  while ((k = getline(&s, &cap, f)) > 0) {
    if (s[k - 1] == '\n')
      s[--k] = 0;
    if (nl == ncap)
      L = realloc(L, (ncap = ncap ? ncap * 2 : 1024) * sizeof *L);
    char *r = malloc((size_t)k + 1);
    for (ssize_t i = 0; i < k; ++i)
      r[i] = s[i] == '\x1f' ? '\0' : s[i];
    r[k] = 0; /* cmdline ends with a NUL */
    L[nl].raw = r;
    L[nl].len = (size_t)k + 1;
    ++nl;
  }
  fclose(f);
}

static char *slurp(const char *path) {
  FILE *f = fopen(path, "r");
  if (!f) {
    perror(path);
    exit(1);
  }
  static char b[1 << 16];
  size_t n = fread(b, 1, sizeof b - 1, f);
  b[n] = 0;
  fclose(f);
  return strdup(b);
}

static volatile unsigned long sink;
static char gbuf[CMD_MAX];

/* 2 = game, 1 = wine watch, 0 = neither: the check_pending decision. */
static int decide(size_t i, int *scan) {
  char *cmd;
  fake_data = L[i].raw;
  fake_len = L[i].len;
  ssize_t n = read_cmdline(1234 + (pid_t)i, gbuf, &cmd);
  if (scan)
    *scan = n > 0 && is_game(cmd, (size_t)n);
  if (n > 0 && is_game(cmd, (size_t)n))
    return 2;
  if (n > 0 && has_lit(cmd, (size_t)n, &wine_lit) &&
      !set_matches(&excls, cmd, (size_t)n))
    return 1;
  return 0;
}

__attribute__((noinline)) void bench_check(int reps) {
  unsigned long acc = 0;
  for (int r = 0; r < reps; ++r)
    for (size_t i = 0; i < nl; ++i)
      acc += (unsigned long)decide(i, NULL);
  sink = acc;
}

__attribute__((noinline)) void bench_scan(int reps) {
  unsigned long acc = 0;
  for (int r = 0; r < reps; ++r)
    for (size_t i = 0; i < nl; ++i) {
      char *cmd;
      fake_data = L[i].raw;
      fake_len = L[i].len;
      ssize_t n = read_cmdline(1234 + (pid_t)i, gbuf, &cmd);
      acc += n > 0 && is_game(cmd, (size_t)n);
    }
  sink = acc;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: match GAME_RE EXCL_RE CORPUS MODE [REPS]\n");
    return 2;
  }
  split_alts(slurp(argv[1]), &games);
  split_alts(slurp(argv[2]), &excls);
  load(argv[3]);
  const char *mode = argv[4];
  int reps = argc > 5 ? atoi(argv[5]) : 1;

  if (!strcmp(mode, "classify")) {
    for (size_t i = 0; i < nl; ++i) {
      int g, d = decide(i, &g);
      printf("%c%c\n", "-WG"[d], g ? 'g' : '-');
    }
    return 0;
  }
  if (!strcmp(mode, "cold")) {
    bench_check(1);
    return 0;
  }
  bench_check(1); /* warm: compile what this corpus needs */
  if (!strcmp(mode, "check"))
    bench_check(reps);
  else if (!strcmp(mode, "scan"))
    bench_scan(reps);
  else if (!strcmp(mode, "time")) { /* wall ns per line, many reps */
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    bench_check(reps);
    clock_gettime(CLOCK_MONOTONIC, &b);
    printf("%.1f\n", ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) /
                         ((double)reps * nl));
  }
  return 0;
}
