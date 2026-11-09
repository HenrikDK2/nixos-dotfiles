# gameboostd benchmark harness

> Stored compressed on the ledger branch: run `tar -xJf data.tar.xz` here first (creates data/). Build outputs go to out/ (`mkdir -p out`).


Reusable A/B harness for `system/services/gameboost/gameboostd.c`. Every
script takes the two source files under test (`SRC_A` = baseline, `SRC_B` =
candidate); patterns come from the `main.sh` next to `SRC_A` (override with
`MAIN_SH=...`). Build/output files go to `OUT` (default `./out`; use a
separate `OUT=` per concurrent run). Needs: gcc, python3, valgrind
(callgrind), strace, root (netlink sockets, proc connector for `execstat`).

No script needs the real proc connector except `execstat`: the exec-event
path is fed through a `NETLINK_USERSOCK` socket so that other jobs on the
machine cannot add events.

## Files

| file | what |
|---|---|
| `patterns.sh MAIN_SH OUTDIR` | evaluates main.sh up to `EXCLUDED_PATTERN`, writes `game.re` / `excl.re` (exactly what is passed to `-m` / `-x`) |
| `gen_corpus.py N SEED [mix\|desktop]` | deterministic synthetic NixOS/KDE/Steam/Proton cmdline corpus (argv joined by `\x1f`). `data/corpus.argv` = 2000 mixed (seed 1), `data/desktop.argv` = 2000 without Steam/Wine/games (seed 2). The mix is a guess, not a measurement. |
| `mklines.py` | corpus -> cleaned cmdline per line (as `read_cmdline_fd` makes it) |
| `gen_fuzz.py N SEED` | adversarial lines built from pattern fragments, `/`, `\`, separators |
| `match.c` | includes the source with `openat/read/close` faked: `read_cmdline` + `is_game` + Wine/exclude test per corpus line. Modes `classify`, `check`, `scan`, `cold`, `time` |
| `core.c` + `pair.c` | two copies of the source (A, B) in one process, run round by round on the same live processes / events; CPU time per round (`CLOCK_THREAD_CPUTIME_ID`, includes kernel time) and the paired per-round difference |
| `evbench.c` | single-variant event path (drain_events + check_pending) for strace counts / callgrind |
| `e2e.c` + `e2e_drive.c` | the real daemon main loop with the connector replaced by a USERSOCK socket; the driver queues exec-event bursts (SIGSTOP/SIGCONT around bursts with K>1), reads on-CPU ns (`/proc/PID/schedstat`), wakeups (voluntary context switches), optional `strace -c` and `smaps_rollup` |
| `sleeper.c` | stand-in process (pause()), exec'd with corpus argv so /proc/PID/cmdline is the corpus line |
| `sysbench.c` | CPU cost of the individual syscalls of a check (kill live/dead, failed openat, openat+read+close, batched close_range, waitpid ECHILD) |
| `altstats.c` | per alternative: literal, anchor byte, prefilter passes, regexec hits/time |
| `heap.c` | heap held by compiled alternatives and grown by regexec's lazy DFA along the daemon's matching path (`heap GAME EXCL daemon FILE.lines...`) |
| `seqtest.c` | for candidates with a regex-free matcher (`a->seq`): has_seq() vs regexec() on 200k generated strings per alternative |
| `execstat.c` | listens to the real proc connector and reports how often an exec repeats a recent PID |

## Scripts (A/B)

```sh
cd bench
A=../a/system/services/gameboost/gameboostd.c
B=../cands/combined/system/services/gameboost/gameboostd.c

./equiv.sh     $A $B [N=200000] [SEED=7]   # classification identical on fuzz + corpora (exit 1 if not)
./match_ab.sh  $A $B [RUNS=15]             # Ir/line (callgrind, deterministic) + native ns/line
./pair_ab.sh   $A $B ev   [REPS=5] ["50:0 50:30 100:0 10:0"]   # paired CPU ns/event, live%:dup%
./pair_ab.sh   $A $B scan [REPS=5] [NPROCS=800]                # paired CPU ns per full_scan
./ev_ab.sh     $A $B [RUNS=11] ["50:0 50:30"]  # syscalls/event (strace, ROUNDS vs 2*ROUNDS) + Ir/event
./e2e_ab.sh    $A $B [RUNS=10] [BURSTS=10] [K=1] [LIVE=50] [DUP=0] [GAP_MS=1100]  # whole loop: cpu, wakeups, syscalls per burst
./mem_e2e.sh   $A $B [RUNS=6]              # whole daemon Rss/Pss/Private_Dirty after Steam/Wine-heavy non-game checks
./flags.sh     $A [RUNS=10]                # build-flag matrix on top of emulated nixpkgs hardening
./one_eq.sh    BIN_A BIN_B [N=400]         # `-1` scan output identical with corpus processes (incl. games) running
```

Single-source tools:

```sh
gcc -O2 sysbench.c -o out/sysbench && out/sysbench out/sleeper data/desktop.argv 20000
gcc -O2 -Wno-unused-function -DGBD_SRC="\"$A\"" heap.c -o out/heap && out/heap data/game.re data/excl.re daemon data/desktop.lines data/corpus.lines
gcc -O2 -Wno-unused-function -DGBD_SRC="\"$A\"" altstats.c -o out/altstats && out/altstats data/game.re data/excl.re data/corpus.lines
gcc -O2 -Wno-unused-function -DGBD_SRC="\"$B\"" seqtest.c -o out/seqtest && out/seqtest data/game.re data/excl.re
gcc -O2 execstat.c -o out/execstat && out/execstat 600     # root; real connector
```

## Notes on noise and validity

* The machine is shared: wall/CPU time of identical binaries differs by up
  to ~7% between separate runs (`ev_ab.sh` A vs A). Use `pair_ab.sh` (A and B
  in the same process, alternating rounds): A vs A medians agree within ~1%.
* Instruction counts (callgrind) are deterministic for the match harness;
  `-1` scan counts vary with what is running.
* In this VM a daemon wakeup costs ~100-250 us of on-CPU time (schedstat),
  far more than the work done, so `e2e_ab.sh` CPU numbers cannot resolve
  sub-microsecond savings; use its syscall and wakeup counts.
* `e2e_drive` sends SIGTERM GAP_MS after the last burst; on a loaded machine
  the last burst's checks can be cut off (fewer "checks" in the stats line).
* The flag emulation (`flags.sh`) approximates nixpkgs' cc-wrapper hardening;
  glibc here is Ubuntu 2.39, not nixpkgs'.
