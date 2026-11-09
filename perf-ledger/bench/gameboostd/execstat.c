/* Listen to the real proc connector for SECONDS and report how often an exec
 * event repeats a recent PID (exec chains): adjacent, within the last 4
 * events, and within the same 1 s window (what gameboostd batches).
 * Needs root. Usage: execstat SECONDS */
#define _GNU_SOURCE
#include <linux/cn_proc.h>
#include <linux/connector.h>
#include <linux/netlink.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static int64_t now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
  int secs = argc > 1 ? atoi(argv[1]) : 60;
  int s = socket(AF_NETLINK, SOCK_DGRAM, NETLINK_CONNECTOR);
  struct sockaddr_nl a = {.nl_family = AF_NETLINK, .nl_groups = CN_IDX_PROC};
  int rcv = 4 << 20;
  setsockopt(s, SOL_SOCKET, SO_RCVBUFFORCE, &rcv, sizeof rcv);
  if (bind(s, (void *)&a, sizeof a)) { perror("bind"); return 1; }
  struct __attribute__((packed)) { struct nlmsghdr nl; struct cn_msg cn; struct proc_input in; } m;
  memset(&m, 0, sizeof m);
  m.nl.nlmsg_len = sizeof m; m.nl.nlmsg_type = NLMSG_DONE;
  m.cn.id.idx = CN_IDX_PROC; m.cn.id.val = CN_VAL_PROC; m.cn.len = sizeof m.in;
  m.in.mcast_op = PROC_CN_MCAST_LISTEN; m.in.event_type = PROC_EVENT_EXEC;
  send(s, &m, sizeof m, 0);
  int64_t end = now_ms() + secs * 1000, win = now_ms();
  unsigned long ev = 0, adj = 0, last4 = 0, inwin = 0;
  pid_t hist[4] = {0}; int h = 0;
  static pid_t w[65536]; int nw = 0;
  char buf[4096];
  while (now_ms() < end) {
    struct pollfd p = {s, POLLIN, 0};
    if (poll(&p, 1, 200) <= 0) continue;
    ssize_t n = recv(s, buf, sizeof buf, 0);
    if (n <= 0) continue;
    for (struct nlmsghdr *nl = (void *)buf; NLMSG_OK(nl, (size_t)n); nl = NLMSG_NEXT(nl, n)) {
      struct proc_event *e = (void *)((struct cn_msg *)NLMSG_DATA(nl))->data;
      if (e->what != PROC_EVENT_EXEC) continue;
      pid_t t = e->event_data.exec.process_tgid;
      ++ev;
      if (t == hist[(h + 3) & 3]) ++adj;
      for (int i = 0; i < 4; ++i) if (hist[i] == t) { ++last4; break; }
      hist[h] = t; h = (h + 1) & 3;
      if (now_ms() - win >= 1000) { win = now_ms(); nw = 0; }
      int dup = 0;
      for (int i = 0; i < nw; ++i) if (w[i] == t) { dup = 1; break; }
      if (dup) ++inwin; else if (nw < 65536) w[nw++] = t;
    }
  }
  m.in.mcast_op = PROC_CN_MCAST_IGNORE; m.in.event_type = 0;
  send(s, &m, sizeof m, 0);
  printf("exec events %lu  adjacent repeat %lu (%.1f%%)  within last 4 %lu (%.1f%%)  within 1 s window %lu (%.1f%%)\n",
         ev, adj, ev ? 100.0 * adj / ev : 0, last4, ev ? 100.0 * last4 / ev : 0, inwin, ev ? 100.0 * inwin / ev : 0);
  return 0;
}
