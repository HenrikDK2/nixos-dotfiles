/* Generic command stub: appends "name arg1 arg2 ..." to $GB_LOG, then looks up
 * a canned response in $GB_RESP/<name>: lines "ARGS\tEXIT\tOUTPUT" where ARGS
 * is the space-joined argument list (or "*" for any), OUTPUT uses \n escapes.
 * First matching line wins; no match -> exit 0, no output. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  const char *name = strrchr(argv[0], '/');
  name = name ? name + 1 : argv[0];
  char args[8192] = "";
  size_t n = 0;
  for (int i = 1; i < argc; i++) {
    size_t l = strlen(argv[i]);
    if (n + l + 2 >= sizeof args) break;
    if (i > 1) args[n++] = ' ';
    memcpy(args + n, argv[i], l);
    n += l;
    args[n] = 0;
  }
  const char *log = getenv("GB_LOG");
  if (log) {
    FILE *f = fopen(log, "a");
    if (f) { fprintf(f, "%s%s%s\n", name, argc > 1 ? " " : "", args); fclose(f); }
  }
  const char *resp = getenv("GB_RESP");
  if (!resp) return 0;
  char path[4096];
  snprintf(path, sizeof path, "%s/%s", resp, name);
  FILE *r = fopen(path, "r");
  if (!r) return 0;
  char line[16384];
  while (fgets(line, sizeof line, r)) {
    line[strcspn(line, "\n")] = 0;
    char *t1 = strchr(line, '\t');
    if (!t1) continue;
    *t1 = 0;
    char *t2 = strchr(t1 + 1, '\t');
    if (t2) *t2 = 0;
    if (strcmp(line, "*") && strcmp(line, args)) continue;
    int code = atoi(t1 + 1);
    if (t2) {
      for (char *p = t2 + 1; *p; p++) {
        if (p[0] == '\\' && p[1] == 'n') { putchar('\n'); p++; }
        else putchar(*p);
      }
    }
    fclose(r);
    return code;
  }
  fclose(r);
  return 0;
}
