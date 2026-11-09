/* Multi-call stub for the external commands start.sh / exit.sh run.
 * Installed as hard links/symlinks named systemctl, busctl, renice, ...
 *
 * - Appends "NAME ARG..." (one line) to $GB_LOG.
 * - Response: first line of $GB_RESP/NAME whose first TAB field (an fnmatch
 *   pattern) matches the space-joined args; second field = exit code, third
 *   (optional) = stdout, with "\n" escapes. No match: exit 0, no output.
 * - sleep: if $GB_SLEEP_STOP is set, unlinks $GB_FLAG (ends start.sh's
 *   follow-up loop like gameboostd's "game exited" would). If
 *   $GB_SLEEP_HOOK is set, execs it with the sleep argument (correctness
 *   runs only: it can bump schedstat counters of fake threads).
 */
#include <fcntl.h>
#include <fnmatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
  const char *name = strrchr(argv[0], '/');
  name = name ? name + 1 : argv[0];
  char args[65536];
  size_t n = 0;
  args[0] = 0;
  for (int i = 1; i < argc && n < sizeof args - 2; ++i) {
    int w = snprintf(args + n, sizeof args - n, "%s%s", i > 1 ? " " : "", argv[i]);
    if (w < 0)
      break;
    n += (size_t)w;
    if (n >= sizeof args)
      n = sizeof args - 1;
  }
  const char *log = getenv("GB_LOG");
  if (log) {
    char line[65536 + 256];
    int l = snprintf(line, sizeof line, "%s%s%s\n", name, argc > 1 ? " " : "", args);
    if (l > (int)sizeof line - 1)
      l = sizeof line - 1;
    int fd = open(log, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0644);
    if (fd >= 0) {
      (void)!write(fd, line, (size_t)l);
      close(fd);
    }
  }
  if (!strcmp(name, "sleep")) {
    const char *flag = getenv("GB_FLAG");
    if (getenv("GB_SLEEP_STOP") && flag)
      unlink(flag);
    const char *hook = getenv("GB_SLEEP_HOOK");
    if (hook && *hook) {
      execl(hook, hook, argc > 1 ? argv[1] : "", (char *)NULL);
      return 127;
    }
    return 0;
  }
  const char *dir = getenv("GB_RESP");
  if (!dir)
    return 0;
  char path[4096];
  snprintf(path, sizeof path, "%s/%s", dir, name);
  FILE *f = fopen(path, "r");
  if (!f)
    return 0;
  char buf[65536];
  while (fgets(buf, sizeof buf, f)) {
    buf[strcspn(buf, "\n")] = 0;
    char *pat = buf, *rc = strchr(buf, '\t');
    if (!rc)
      continue;
    *rc++ = 0;
    char *out = strchr(rc, '\t');
    if (out)
      *out++ = 0;
    if (fnmatch(pat, args, 0))
      continue;
    if (out && *out) {
      char last = 0;
      for (char *p = out; *p; ++p) {
        if (p[0] == '\\' && p[1] == 'n') {
          putchar(last = '\n');
          ++p;
        } else {
          putchar(last = *p);
        }
      }
      if (last != '\n') /* real tools end their output with a newline */
        putchar('\n');
    }
    fflush(stdout);
    fclose(f);
    return atoi(rc);
  }
  fclose(f);
  return 0;
}
