/* One copy of gameboostd.c behind a small API, compiled once per variant
 * (-DSUF=A / -DSUF=B -DGBD_SRC='"…/gameboostd.c"') so that pair.c can run A
 * and B alternately in the same process, round by round, on the same
 * processes and events. Everything in gameboostd.c is static, so the two
 * copies do not clash; only these wrappers (suffixed) are exported. */
#define _GNU_SOURCE
#define CAT2(a, b) a##b
#define CAT(a, b) CAT2(a, b)
#define FN(x) CAT(x, SUF)
#define main FN(gbd_main_)
#include GBD_SRC
#undef main

void FN(core_init_)(int s, const char *game, const char *excl) {
  self = getpid();
  procfd = open("/proc", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  split_alts(game, &games);
  if (excl)
    split_alts(excl, &excls);
  sock = s;
  cur_mask = PROC_EVENT_EXEC;
}

/* Exec-event path: read every queued event, then run every check now. */
__attribute__((noinline)) int FN(ev_round_)(void) {
  int n = drain_events();
  for (int i = 0; i < npending; ++i)
    pending[i].due = 0;
  (void)check_pending();
  return n;
}

int FN(ev_left_)(void) { return npending; }
unsigned long FN(ev_checks_)(void) { return stat_checks; }

/* One full /proc scan; returns the number of game processes found. */
__attribute__((noinline)) int FN(scan_)(void) {
  static struct found f;
  full_scan(&f, 0);
  return f.n;
}
