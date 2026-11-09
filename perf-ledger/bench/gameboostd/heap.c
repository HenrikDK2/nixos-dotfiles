/* Heap held by the compiled pattern alternatives (mallinfo2 in-use bytes):
 * after split_alts, after compiling each alternative, and after matching the
 * corpus (regexec grows the lazy DFA). Also prints the heap's top (sbrk)
 * growth, which is what becomes resident.
 * cc -O2 -DGBD_SRC='"…"' heap.c -o heap; heap GAME_RE EXCL_RE CORPUS.lines */
#include <malloc.h>
#define main gbd_main
#include GBD_SRC
#undef main
static size_t used(void) { return mallinfo2().uordblks; }
/* check_pending's decision on each line of each file (no compile first):
 * the daemon's real heap growth. */
static int daemon_path(char **files, int nf) {
  char *brk0 = sbrk(0);
  size_t u0 = used();
  for (int j = 0; j < nf; ++j) {
    FILE *f = fopen(files[j], "r");
    char *s = NULL; size_t cap = 0; ssize_t k; unsigned long n = 0;
    while ((k = getline(&s, &cap, f)) > 0) {
      s[--k] = 0;
      if (!is_game(s, (size_t)k) && has_lit(s, (size_t)k, &wine_lit))
        set_matches(&excls, s, (size_t)k);
      ++n;
    }
    fclose(f);
    printf("after %-60s (%lu lines): heap in use +%zu bytes, heap top +%td bytes\n", files[j] + (strlen(files[j]) > 60 ? strlen(files[j]) - 60 : 0), n, used() - u0, (char *)sbrk(0) - brk0);
  }
  return 0;
}

int main(int argc, char **argv) {
  if (argc > 4 && !strcmp(argv[3], "daemon")) {
    static char g[1 << 16], x[1 << 16];
    FILE *f = fopen(argv[1], "r"); g[fread(g, 1, sizeof g - 1, f)] = 0; fclose(f);
    f = fopen(argv[2], "r"); x[fread(x, 1, sizeof x - 1, f)] = 0; fclose(f);
    split_alts(g, &games); split_alts(x, &excls);
    return daemon_path(argv + 4, argc - 4);
  }
  static char b1[1 << 16], b2[1 << 16];
  FILE *f = fopen(argv[1], "r"); b1[fread(b1, 1, sizeof b1 - 1, f)] = 0; fclose(f);
  f = fopen(argv[2], "r"); b2[fread(b2, 1, sizeof b2 - 1, f)] = 0; fclose(f);
  char *brk0 = sbrk(0);
  size_t u0 = used();
  split_alts(b1, &games); split_alts(b2, &excls);
  printf("split_alts: %zu bytes\n", used() - u0);
  size_t tot = 0;
  for (int s = 0; s < 2; ++s) {
    struct altset *set = s ? &excls : &games;
    for (int i = 0; i < set->n; ++i) {
      size_t u = used();
      compile_alt(&set->v[i]);
      size_t d = used() - u;
      tot += d;
      printf("%s[%2d] regcomp %6zu bytes  %s\n", s ? "excl" : "game", i, d, set->v[i].pat);
    }
  }
  printf("all regcomp: %zu bytes; in use %zu; heap top grew %td bytes\n", tot, used() - u0, (char *)sbrk(0) - brk0);
  /* match the corpus: lazy DFA growth */
  char *s = NULL; size_t cap = 0; ssize_t k; size_t u = used();
  f = fopen(argv[3], "r");
  while ((k = getline(&s, &cap, f)) > 0) {
    s[--k] = 0;
    for (int t = 0; t < 2; ++t) {
      struct altset *set = t ? &excls : &games;
      for (int i = 0; i < set->n; ++i) regexec(&set->v[i].re, s, 0, NULL, 0);
    }
  }
  printf("after regexec of every alternative on the corpus: +%zu bytes in use; heap top grew %td bytes total\n", used() - u, (char *)sbrk(0) - brk0);
  return 0;
}
