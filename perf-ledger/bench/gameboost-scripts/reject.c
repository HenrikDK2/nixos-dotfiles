/* LD_PRELOAD shim for correctness scenarios: makes writes to the files listed
 * in $GB_REJECT ('|'-separated absolute paths; sysfs PCI paths contain ':') fail the way sysfs rejects a
 * value: open succeeds, write fails (the path is opened as /dev/full).
 * Reads are unaffected. Only for bash (the scripts' own redirections). */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <string.h>
#include <stdlib.h>

static int rejected(const char *path, int flags) {
  if ((flags & O_ACCMODE) == O_RDONLY)
    return 0;
  const char *list = getenv("GB_REJECT");
  if (!list || !*list)
    return 0;
  size_t pl = strlen(path);
  for (const char *p = list; *p;) {
    const char *e = strchr(p, '|');
    size_t l = e ? (size_t)(e - p) : strlen(p);
    if (l == pl && !strncmp(p, path, l))
      return 1;
    if (!e)
      break;
    p = e + 1;
  }
  return 0;
}

#define WRAP(fn, ...)                                                          \
  int fn(const char *path, int flags, ...) {                                   \
    static int (*real)(const char *, int, ...);                                \
    if (!real)                                                                 \
      real = (int (*)(const char *, int, ...))dlsym(RTLD_NEXT, #fn);           \
    mode_t mode = 0;                                                           \
    if (flags & (O_CREAT | O_TMPFILE)) {                                       \
      va_list ap;                                                              \
      va_start(ap, flags);                                                     \
      mode = va_arg(ap, mode_t);                                               \
      va_end(ap);                                                              \
    }                                                                          \
    if (rejected(path, flags))                                                 \
      return real("/dev/full", O_WRONLY | (flags & O_CLOEXEC), 0);             \
    return real(path, flags, mode);                                            \
  }

WRAP(open)
WRAP(open64)
