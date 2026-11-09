/* Equivalence checks for a gameboostd.c variant (GBD_SRC):
 *
 *   equiv GAME_ERE EXCL_ERE CORPUS NRANDOM_PATTERNS
 *
 * 1. For every corpus line (and mutations of it): set_matches() of the split,
 *    lazily compiled alternatives == regexec() of the whole ERE compiled the
 *    plain way; is_game() == whole(game) && !whole(excl); and for each
 *    alternative, has_lit() == (memmem() != NULL) and
 *    regexec(compile_alt) == regexec(plain regcomp of the alternative).
 * 2. NRANDOM_PATTERNS random EREs (literals, [/\], ., .*, .+, ^, $, groups
 *    with |, ?, *, +, {m,n}, brackets): the same checks on random strings.
 * Prints counts; exits 1 on the first mismatch (with details), except
 * split-vs-whole differences on random patterns, which are only counted.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define main gbd_main
#include GBD_SRC
#undef main

static unsigned long long rs = 88172645463325252ULL;
static unsigned rnd(unsigned n) {
  rs ^= rs << 13;
  rs ^= rs >> 7;
  rs ^= rs << 17;
  return (unsigned)(rs % n);
}

static unsigned long nlines, nalt, nlit, nsplit_diff;
static int fatal_split = 1;
static unsigned long nvalid_cmp;

static int plain(const char *re, regex_t *r) {
  return regcomp(r, re, REG_EXTENDED | REG_NOSUB);
}

static void check_set(struct altset *set, regex_t *whole, const char *s,
                      const char *what) {
  size_t n = strlen(s);
  int a = set_matches(set, s, n), b = !regexec(whole, s, 0, NULL, 0);
  if (a != b) {
    /* For random patterns this is a property of the unchanged literal
     * extraction (e.g. "e+*"): counted, and must be the same for base. */
    ++nsplit_diff;
    if (fatal_split) {
      printf("MISMATCH set %s: split=%d whole=%d line=[%s]\n", what, a, b, s);
      exit(1);
    }
  }
  for (int i = 0; i < set->n; ++i) {
    struct alt *al = &set->v[i];
    if (al->lit) {
      int x = has_lit(s, n, al), y = memmem(s, n, al->lit, al->litn) != NULL;
      ++nlit;
      if (x != y) {
        printf("MISMATCH has_lit lit=[%.*s] line=[%s] %d %d\n", (int)al->litn,
               al->lit, s, x, y);
        exit(1);
      }
    }
    static regex_t pr[256];
    static const struct alt *pa[256];
    if (i < 256 && pa[i] != al) {
      if (pa[i])
        regfree(&pr[i]);
      if (plain(al->pat, &pr[i])) {
        pa[i] = NULL;
        continue;
      }
      pa[i] = al;
    }
    if (compile_alt(al))
      continue;
    int c = !regexec(&al->re, s, 0, NULL, 0), d = !regexec(&pr[i], s, 0, NULL, 0);
    ++nalt;
    if (c != d) {
      printf("MISMATCH alt [%s] line=[%s] new=%d plain=%d\n", al->pat, s, c, d);
      exit(1);
    }
  }
  ++nlines;
}

static const char *alpha = "/\\:. -_aAbcCeEhinsSwxz09()[]*+?|^$";

static void mutate(char *dst, const char *src, size_t max) {
  size_t n = strlen(src);
  if (n >= max - 8)
    n = max - 8;
  memcpy(dst, src, n);
  dst[n] = 0;
  int k = 1 + rnd(4);
  for (int j = 0; j < k; ++j) {
    n = strlen(dst);
    unsigned pos = n ? rnd((unsigned)n + 1) : 0, op = rnd(3);
    char c = alpha[rnd((unsigned)strlen(alpha))];
    if (op == 0 && n + 1 < max) { /* insert */
      memmove(dst + pos + 1, dst + pos, n - pos + 1);
      dst[pos] = c;
    } else if (op == 1 && n) { /* delete */
      if (pos == n)
        --pos;
      memmove(dst + pos, dst + pos + 1, n - pos);
    } else if (n) {
      dst[pos == n ? pos - 1 : pos] = c;
    }
  }
}

static const char *frag[] = {"ab",  "exe", "[/\\]", ".",    ".*",   ".+",  "^",
                             "$",   "(a|b)", "?",   "*",    "+",    "{1,3}", "[A-Z]",
                             "[^ ]", "\\.", ":",    "wine", " ",    "(x|yz|)", "c",
                             "S",   "[[:space:]]", "(^|/)", "( |$)", "|", "[ab]*"};

int main(int argc, char **argv) {
  if (argc < 5)
    return 2;
  regex_t wg, wx;
  if (plain(argv[1], &wg) || plain(argv[2], &wx))
    return 2;
  split_alts(argv[1], &games);
  split_alts(argv[2], &excls);

  FILE *f = fopen(argv[3], "r");
  static char line[CMD_MAX], mut[CMD_MAX];
  unsigned long ngame = 0;
  while (fgets(line, sizeof line, f)) {
    line[strcspn(line, "\n")] = 0;
    for (int m = 0; m < 150; ++m) {
      const char *s = line;
      if (m) {
        mutate(mut, line, sizeof mut);
        s = mut;
      }
      check_set(&games, &wg, s, "game");
      check_set(&excls, &wx, s, "excl");
      size_t n = strlen(s);
      int a = is_game(s, n),
          b = !regexec(&wg, s, 0, NULL, 0) && regexec(&wx, s, 0, NULL, 0);
      if (a != b) {
        printf("MISMATCH is_game line=[%s]\n", s);
        return 1;
      }
      ngame += a;
    }
  }
  printf("corpus: %lu set checks, %lu alt regexec pairs, %lu has_lit pairs, "
         "%lu game lines\n", nlines, nalt, nlit, ngame);

  fatal_split = 0;
  int npat = atoi(argv[4]), valid = 0;
  unsigned long l0 = nlines;
  for (int t = 0; t < npat; ++t) {
    char re[256] = "";
    int k = 1 + rnd(7);
    for (int j = 0; j < k; ++j)
      strcat(re, frag[rnd(sizeof frag / sizeof *frag)]);
    /* compile_alt() must accept exactly the alternatives regcomp() accepts */
    {
      struct altset vs;
      split_alts(re, &vs);
      for (int i = 0; i < vs.n; ++i) {
        regex_t t;
        int pv = !plain(vs.v[i].pat, &t), cv = !compile_alt(&vs.v[i]);
        if (pv)
          regfree(&t);
        ++nvalid_cmp;
        if (pv != cv) {
          printf("MISMATCH validity alt [%s]: plain=%d compile_alt=%d\n",
                 vs.v[i].pat, pv, cv);
          return 1;
        }
      }
    }
    regex_t w;
    if (plain(re, &w))
      continue;
    struct altset set;
    split_alts(re, &set);
    int ok = 1;
    for (int i = 0; i < set.n; ++i) /* invalid alone: skipped by the daemon too */
      if (compile_alt(&set.v[i]))
        ok = 0;
    if (!ok) {
      regfree(&w);
      continue;
    }
    ++valid;
    for (int s = 0; s < 300; ++s) {
      char str[64];
      int len = rnd(40);
      for (int i = 0; i < len; ++i)
        str[i] = "abexwinS:./\\ ()cyz|"[rnd(19)];
      str[len] = 0;
      check_set(&set, &w, str, re);
    }
    regfree(&w);
  }
  printf("random: %d valid patterns, %lu strings, %lu split-vs-whole "
         "differences; totals: %lu alt regexec pairs, %lu has_lit pairs\n",
         valid, nlines - l0, nsplit_diff, nalt, nlit);

  /* 3. has_lit() == memmem() on random literals/strings over tiny alphabets
   * (anchors at every offset, matches at both ends, partial overlaps). */
  unsigned long nh = 0, nhit = 0;
  for (int t = 0; t < 3000000; ++t) {
    const char *ab = t & 1 ? "abc" : "aZ.";
    char lit[16], str[48];
    int ln = 3 + rnd(6), sn = rnd(40);
    for (int i = 0; i < ln; ++i)
      lit[i] = ab[rnd(3)];
    lit[ln] = 0;
    for (int i = 0; i < sn; ++i)
      str[i] = ab[rnd(3)];
    str[sn] = 0;
    struct alt al = {.lit = lit, .litn = (size_t)ln};
    char pool[32];
    const char *l2;
    size_t n2;
    if (extract_literal(lit, pool, &l2, &n2) && n2 == (size_t)ln) {
      struct alt *a = &al; /* anchors chosen the way split_alts() does */
      struct altset one;
      split_alts(lit, &one);
      a = &one.v[0];
      int x = has_lit(str, (size_t)sn, a),
          y = memmem(str, (size_t)sn, lit, (size_t)ln) != NULL;
      if (x != y) {
        printf("MISMATCH has_lit random lit=[%s] str=[%s] %d %d\n", lit, str, x, y);
        return 1;
      }
      ++nh;
      nhit += x;
      free(one.v[0].pat);
      free((void *)one.v[0].lit);
      free(one.v);
    }
  }
  printf("has_lit random: %lu cases, %lu hits; validity compared for %lu "
         "alternatives\n", nh, nhit, nvalid_cmp);
  return 0;
}
