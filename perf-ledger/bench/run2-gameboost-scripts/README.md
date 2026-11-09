# GameBoost start.sh / exit.sh harness

Runs `system/services/gameboost/scripts/start.sh` and `exit.sh` from any
checkout against a deterministic fake root, with every external command
stubbed, and compares/measures variants.

## Pieces

- `genroot.py` - fake `proc/` (about 500 processes: kernel threads, odd comm
  names with `) `, newline, glob chars and spaces, a Steam/Proton game tree
  with about 250 threads, Wine processes with RLIMIT_NICE 31,
  `task/*/children` files unless `--no-children`), `sys/` (32 CPUs amd-pstate,
  40 PCI devices with one AMD GPU, SATA/NVMe, pcie_aspm, cgroups), `run/`.
- `stub.c` - one binary symlinked as systemctl, busctl, renice, ionice, chrt,
  systemd-ac-power, pgrep, killall, notify-send, loginctl, setpriv. It
  appends its argv to `$GB_LOG` and answers from `build/tmpl/SCEN/resp/NAME`
  (tab-separated `ARGS EXIT OUTPUT`). coreutils (sleep, rm, mkdir) stay real.
- `lib.sh` - scenarios (`ALL_SCENS`), path rewrite (`/proc/ /sys/ /run/` ->
  `/srv/...`), modes: `start` (FOLLOW_UP=(): only the game-start path),
  `full` (FOLLOW_UP=(0 boost 0 render 0 boost), RENDER_SAMPLE_S=0),
  `render` (FOLLOW_UP=(0 render), 1 s sample). The fake root lives in
  `../root*` and is bind-mounted on `/srv` inside a private mount namespace
  (`unshare -m`), so paths are as short as the real ones. Nothing outside the
  namespace is touched.
- `setup.sh NAME=CHECKOUT ...` - build stubs, `abrun`, templates, variants.
- `snap.sh SCEN...` - post-start snapshots (base start.sh) used as exit.sh input.
- `run1.sh VARIANT MODE start.sh|exit.sh|chain SCEN [snap|snapflag]` - one run
  plus a dump (all fake sys/run files, written proc files, command log, rc,
  stdout, stderr normalised for path and line numbers).
- `correctness.sh VARIANT` - 42 cases byte-compared against `base`.
- `ir.sh` - callgrind instruction count of the main bash process.
- `spawns.sh` - strace -f: execve, clone, total syscalls, programs run.
- `metrics.sh VARIANT...` - Ir and spawn counts for the standard cases.
- `wall.sh ROUNDS SCRIPT MODE SCEN snap|- VARIANT...` - `abrun`: alternating
  order (A B / B A per round), untimed reset before every run, only the timed
  child pinned (`GB_CPU`, default 2), prints median/min/max/q1/q3 in us.
- `profile_fn.sh VARIANT SCEN 'code'` - Ir of one start.sh function.
- `hf.sh SCRIPT MODE SCEN snap|- VARIANT...` - hyperfine (-w 3 -r 20, --prepare reset), not interleaved.
- `realtree.sh WORKDIR` - real-kernel check: base vs c3 `tree_pids` on a live
  process tree it starts itself (identical TREE expected).

Patches (relative to repo root, `git apply` on 9008034) are in `../patches/`.

## Typical session

    W=..   # this dir's parent
    ./setup.sh base=$W/base c1=$W/c1
    ./snap.sh desk-sysfs desk-ppd lap-bat big exit-reaper exit-wine2 \
        exit-deferred exit-deferred-off exit-noflag
    ./correctness.sh c1          # cases=42 diffs=0 expected
    ./metrics.sh base c1
    ./wall.sh 20 start.sh start desk-sysfs - base c1
    ./wall.sh 20 exit.sh start desk-sysfs snap base c1

Several `correctness.sh` runs can go in parallel (each uses `../root-VARIANT`);
other scripts take `GB_ROOT_DIR` to choose their root dir.

Needs root (for unshare/mount), python3, gcc, valgrind, strace, bash.
