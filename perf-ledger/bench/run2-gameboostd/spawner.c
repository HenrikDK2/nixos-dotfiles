/* spawner TREE CMD ARGS...: for every TREE/<pid>/cmdline start a `hold`
 * process whose argv is that cmdline (empty cmdline -> empty argv, like a
 * kernel thread), wait until all have exec'd, run CMD, then kill them.
 * Meant to run as PID 1 of a fresh PID namespace with its own /proc
 * (unshare --pid --fork --mount-proc), so /proc holds exactly these. */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t kids[8192];
static int nk;

int main(int argc, char **argv) {
  if (argc < 3)
    return 2;
  const char *hold = getenv("HOLD") ? getenv("HOLD") : "/dev/shm/gbd_hold";
  DIR *d = opendir(argv[1]);
  struct dirent *e;
  static char buf[65536];
  /* sorted by pid so the spawn order (and pids) are stable */
  long pids[8192];
  int np = 0;
  while ((e = readdir(d)))
    if (e->d_name[0] >= '1' && e->d_name[0] <= '9' && strspn(e->d_name, "0123456789") == strlen(e->d_name))
      pids[np++] = atol(e->d_name);
  closedir(d);
  for (int i = 1; i < np; ++i)
    for (int j = i; j > 0 && pids[j - 1] > pids[j]; --j) {
      long t = pids[j]; pids[j] = pids[j - 1]; pids[j - 1] = t;
    }
  for (int i = 0; i < np; ++i) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%ld/cmdline", argv[1], pids[i]);
    int fd = open(path, O_RDONLY);
    if (fd < 0)
      continue;
    ssize_t n = read(fd, buf, sizeof buf - 1);
    close(fd);
    if (n < 0)
      n = 0;
    buf[n] = 0;
    char *av[1024];
    int ac = 0;
    for (char *p = buf; p < buf + n && ac < 1023; p += strlen(p) + 1)
      av[ac++] = p;
    av[ac] = NULL;
    int pp[2];
    if (pipe2(pp, O_CLOEXEC))
      return 1;
    pid_t c = fork();
    if (c == 0) {
      close(pp[0]);
      execve(hold, av, (char *[]){NULL});
      _exit(127);
    }
    close(pp[1]);
    char x;
    (void)!read(pp[0], &x, 1); /* EOF once the exec happened */
    close(pp[0]);
    kids[nk++] = c;
  }
  fprintf(stderr, "spawner: %d processes\n", nk);
  pid_t c = fork();
  if (c == 0) {
    execvp(argv[2], argv + 2);
    _exit(127);
  }
  int st = 0;
  while (waitpid(c, &st, 0) < 0)
    ;
  for (int i = 0; i < nk; ++i)
    kill(kids[i], SIGKILL);
  while (wait(NULL) > 0)
    ;
  return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}
