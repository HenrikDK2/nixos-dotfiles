/* Per-alternative stats: literal, anchor, how many corpus lines pass the
 * literal prefilter, how many regexec calls / matches, and regexec ns.
 * cc -O2 -DGBD_SRC='"…/gameboostd.c"' altstats.c -o altstats
 * altstats GAME_RE EXCL_RE CORPUS.lines */
#define main gbd_main
#include GBD_SRC
#undef main
static void stats(struct altset *set, const char *name, char **ln, size_t *lens, size_t n) {
  for (int i = 0; i < set->n; ++i) {
    struct alt *a = &set->v[i];
    size_t pass = 0, hit = 0;
    compile_alt(a);
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (size_t j = 0; j < n; ++j) {
      if (a->lit && !has_lit(ln[j], lens[j], a)) continue;
      ++pass;
      if (!regexec(&a->re, ln[j], 0, NULL, 0)) ++hit;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("%s[%2d] lit=%-28.*s anc=%c pass=%5zu hit=%5zu  %8.0f us  %s\n", name, i,
           a->lit ? (int)a->litn : 4, a->lit ? a->lit : "NONE", a->lit ? a->lit[a->anc] : ' ',
           pass, hit, ((t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec)) / 1e3, a->pat);
  }
}
int main(int argc, char **argv) {
  static char b1[1 << 16], b2[1 << 16];
  FILE *f = fopen(argv[1], "r"); b1[fread(b1, 1, sizeof b1 - 1, f)] = 0; fclose(f);
  f = fopen(argv[2], "r"); b2[fread(b2, 1, sizeof b2 - 1, f)] = 0; fclose(f);
  split_alts(b1, &games); split_alts(b2, &excls);
  char **ln = NULL; size_t *lens = NULL, n = 0, cap = 0; char *s = NULL; size_t sc = 0; ssize_t k;
  f = fopen(argv[3], "r");
  while ((k = getline(&s, &sc, f)) > 0) {
    if (n == cap) { cap = cap ? 2 * cap : 1024; ln = realloc(ln, cap * sizeof *ln); lens = realloc(lens, cap * sizeof *lens); }
    s[--k] = 0; ln[n] = strdup(s); lens[n++] = (size_t)k;
  }
  stats(&games, "game", ln, lens, n);
  stats(&excls, "excl", ln, lens, n);
  return 0;
}
