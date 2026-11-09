# GameBoost start.sh / exit.sh bench harness

Runs `system/services/gameboost/start.sh` and `exit.sh` (any version: a
directory holding both files) against a generated fake system, with stub
commands on PATH, and either compares two versions for identical behaviour or
measures them. Needs root (mount namespaces), bash, python3, gcc, strace,
valgrind. No systemd, D-Bus, GPU or real sysfs needed.

## How it works

- `gen.py ROOT SCENARIO [--cpus N --procs N --game-threads N --pci N]`
  writes a deterministic fake `ROOT/sys`, `ROOT/run`, `ROOT/proc` (≈`--procs`
  processes: kernel threads, services, a Plasma session and a Steam/Proton
  game tree with a 120-thread game, wine services, wineserver, odd comm
  names in `odd-procs`; `task/TID/{stat,comm,schedstat,children}`), the stub
  responses `ROOT/resp/NAME`, the start.sh arguments `ROOT/args` and extra
  env `ROOT/env`.
  Scenarios: `desktop-sysfs` (no PPD, amd-pstate per-CPU boost, global boost,
  X3D, swsmu GPU + a 0x0380 device), `desktop-ppd` (PPD drives amd-pstate,
  hold OK), `laptop-battery`, `laptop-ac` (intel_pstate, PPD, deferred
  upgrade but gameboost inactive), `reentry` (existing state and cups files,
  deferred upgrade), `odd-procs` (comm with `) `, newlines, globs; vanished
  PIDs; a cgroup without cpu.weight; ionice failing -> per-thread retry),
  `powerplay-ppd-refused` (PPD present, hold refused -> sysfs; profile write
  rejected -> "manual" fallback), `render-busy` / `render-busy-nopref`
  (with the sleep hook every game thread gets a different run time during
  the render sample and the busiest "Job" thread is SCHED_FIFO; -nopref has
  no RenderThread name, so the policy check decides the pick).
  The canned `pgrep -lx` answer is derived from the fake /proc (what the real
  pgrep would print), so a /proc-scanning exit.sh sees the same processes.
- `ns.sh ROOT CMD...` runs CMD in a private mount namespace with `ROOT/sys`
  on `/sys`, `ROOT/run` on `/run`, `ROOT/proc` on `/home`.
- `prep.sh SRC OUTDIR` copies start.sh/exit.sh with `/proc/` rewritten to
  `/home/` (same length, so string operations cost the same as on a real
  system). Nothing else in the scripts changes.
- `stub.c` (built by `setup.sh` into `build/bin/{systemctl,busctl,
  systemd-ac-power,renice,ionice,pgrep,killall,chrt,sleep}`) logs argv to
  `$GB_LOG` and answers from `$GB_RESP/NAME` (`fnmatch-pattern<TAB>rc<TAB>
  stdout`). `sleep` returns at once; with `GB_SLEEP_STOP` it removes the
  running flag (= game ended, start.sh's follow-up loop stops); with
  `GB_SLEEP_HOOK` it runs a hook (bumps the render thread's schedstat).
- `reject.c` -> `build/reject.so`: LD_PRELOAD shim that makes writes to the
  paths in `$GB_REJECT` (`|`-separated) fail like a rejecting sysfs file.

## Commands

```sh
B=/path/to/bench            # this directory
REPO_A=/path/to/pristine    # tree with system/services/gameboost
REPO_B=/path/to/candidate
G=system/services/gameboost

bash $B/setup.sh                                    # once: build stubs + shim

# Behaviour: every scenario x {startexit, entry, exit}; diffs stdout, stderr
# (line numbers normalised), exit codes, the stub call log and the final
# contents of every fake sysfs/run file (state file included).
bash $B/compare.sh $REPO_A/$G $REPO_B/$G /tmp/cmpdir
#   IGNORE_CALLS='^systemctl is-active --quiet power-profiles-daemon|^busctl '  (call a candidate drops)
#   SORT_CALLS=1        (argv compared as sorted lists, for PID-order-only changes)
#   SCENARIOS="desktop-sysfs reentry" MODES="startexit"   (subset)

# Single run, outputs in OUT (calls.log, *.tree, *.stdout/stderr/rc)
bash $B/run.sh $REPO_A/$G desktop-sysfs startexit /tmp/root /tmp/out

# Measurements: interleaved, rotating order, warm-up 3
python3 $B/ab.py --mode entry --count -n 30 A=$REPO_A/$G B=$REPO_B/$G
#   --mode entry         start.sh until its first sleep (game-mode entry)
#   --mode start         whole start.sh incl. the +10/+30/+60 s follow-ups
#   --mode exit          exit.sh with the state a full start.sh left
#   --mode exit-nostate  exit.sh fallback paths
#   --scenario NAME, --gen '--cpus 16 --procs 1000 --game-threads 300'
#   --count: execs/forks (strace -f), syscalls of the main bash (strace -c),
#            instructions in bash processes (callgrind, deterministic)
#   --no-time: counts only
#   --hook: start mode, run the scenario's sleep hook (use with render-busy)
#   --real-procs N: exit modes only; new PID namespace with N sleepers,
#            exit.sh on the real /proc with the REAL pgrep (other commands
#            stubbed); orphans are reaped so their CPU is counted. Needed to
#            compare anything that replaces pgrep.

# The full measurement set of the 2026-11-08 run (both scripts):
N=30 bash $B/timing.sh /tmp/res $REPO_A/$G name1=$REPO_B/$G ...

# Correctness helpers
bash $B/patequiv.sh STATEFILE...   # old exit.sh regexes vs glob patterns
python3 $B/parsefuzz.py            # old vs IFS=')' stat parser, 3000 fuzzed comms
python3 $B/realtree.py SRC_A SRC_B # tree_pids on the REAL /proc (odd comms,
                                   # thread-forked children, zombies)
python3 $B/realkill.py SRC_A SRC_B # kill_lingering_processes on the real /proc
                                   # with real pgrep, 72 process mixes, + CPU
```

## Metrics and caveats

- `bash_Ir` (callgrind instructions of bash and its forked subshells, not of
  exec'd programs) is deterministic: the primary metric for script CPU work.
  Absolute values are for Ubuntu's bash 5.2.21; NixOS's bash differs.
- `execs`/`forks` count every process start incl. stubs; on the real system
  each is a real systemctl/busctl/renice/... (several ms for systemctl).
- `WALL`/`CPU` include stub processes (tiny C programs), so they understate
  the cost of real external commands; the sandbox is shared, so use many
  runs and the medians.
- Fake sysfs files are plain files: anything the kernel does on a write
  (e.g. amd-pstate refusing EPP under "performance") is not modelled except
  `GB_REJECT`.
