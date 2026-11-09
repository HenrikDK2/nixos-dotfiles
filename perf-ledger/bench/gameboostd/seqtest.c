/* For every alternative that a candidate matches without a regex (a->seq),
 * compare has_seq() with regexec() of the alternative on generated strings:
 * the sequence with class positions as '/', '\\' or another byte, single-byte
 * mutations, random prefixes/suffixes. cc -DGBD_SRC=... seqtest.c */
#define main gbd_main
#include GBD_SRC
#undef main
static unsigned long long r = 0x1234567ULL;
static unsigned rnd(void) { r ^= r << 13; r ^= r >> 7; r ^= r << 17; return (unsigned)(r >> 11); }
static const char noise[] = "/\\ abcxyzAZ09-._:wine.exe";
int main(int argc, char **argv) {
  static char g[65536], x[65536];
  FILE *f = fopen(argv[1], "r"); g[fread(g, 1, 65535, f)] = 0; fclose(f);
  f = fopen(argv[2], "r"); x[fread(x, 1, 65535, f)] = 0; fclose(f);
  split_alts(g, &games); split_alts(x, &excls);
  unsigned long tests = 0, bad = 0, pos = 0;
  for (int t = 0; t < 2; ++t) {
    struct altset *set = t ? &excls : &games;
    for (int i = 0; i < set->n; ++i) {
      struct alt *a = &set->v[i];
      if (!a->seq) continue;
      compile_alt(a);
      for (int k = 0; k < 200000; ++k) {
        char s[512]; size_t n = 0;
        for (int j = rnd() % 6; j > 0; --j) s[n++] = noise[rnd() % (sizeof noise - 1)];
        int copies = 1 + (rnd() % 4 == 0);
        for (int c = 0; c < copies; ++c) {
          for (size_t j = 0; j < a->seqn; ++j) {
            char ch = a->seq[j] ? a->seq[j] : (rnd() % 2 ? '/' : '\\');
            if (!a->seq[j] && rnd() % 10 == 0) ch = noise[rnd() % (sizeof noise - 1)];
            if (rnd() % 40 == 0) ch = noise[rnd() % (sizeof noise - 1)];
            if (rnd() % 60 == 0) continue; /* drop */
            s[n++] = ch;
          }
          for (int j = rnd() % 4; j > 0; --j) s[n++] = noise[rnd() % (sizeof noise - 1)];
        }
        s[n] = 0;
        int want = !regexec(&a->re, s, 0, NULL, 0);
        int got = has_seq(s, n, a);
        ++tests; pos += want;
        if (want != got && bad++ < 10) printf("MISMATCH %s: '%s' regexec %d has_seq %d\n", a->pat, s, want, got);
      }
    }
  }
  printf("seqtest: %lu strings, %lu regex matches, %lu mismatches\n", tests, pos, bad);
  return bad != 0;
}
