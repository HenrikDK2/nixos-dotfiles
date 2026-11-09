/* gameboostd itself (unchanged main loop) with the proc connector replaced by
 * a NETLINK_USERSOCK socket bound to $E2E_NLPID, so that e2e_drive can feed
 * it exec events for its own processes only (the real connector would also
 * deliver every exec of the other jobs on this machine). LISTEN/IGNORE
 * messages are swallowed (reported as sent) and counted in $E2E_CTL if set.
 * Build: cc -O2 -DGBD_SRC='"…/gameboostd.c"' e2e.c -o e2e_daemon */
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

static int fake_socket(int dom, int type, int proto) {
  (void)dom, (void)proto;
  int s = socket(AF_NETLINK, type, NETLINK_USERSOCK);
  const char *e = getenv("E2E_NLPID");
  struct sockaddr_nl a = {.nl_family = AF_NETLINK,
                          .nl_pid = e ? (unsigned)strtoul(e, NULL, 0) : 0};
  if (s >= 0 && bind(s, (void *)&a, sizeof a)) {
    close(s);
    return -1;
  }
  return s;
}
static int fake_bind(int s, const void *a, socklen_t n) {
  (void)s, (void)a, (void)n;
  return 0;
}
static ssize_t fake_send(int s, const void *b, size_t n, int f) {
  (void)s, (void)b, (void)f;
  return (ssize_t)n;
}

#define socket(d, t, p) fake_socket(d, t, p)
#define bind(s, a, n) fake_bind(s, a, n)
#define send(s, b, n, f) fake_send(s, b, n, f)
#include GBD_SRC
