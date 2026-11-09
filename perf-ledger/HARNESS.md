# Benchmark harness

Sandbox: generic Linux container (not NixOS), 4 vCPU, no GPU/KWin/games, no `perf`
(no HW counters). Tools: gcc/clang, valgrind (callgrind/massif), strace, hyperfine,
shellcheck, node 22, nix-instantiate.

Benchmarks are saved under `perf-ledger/bench/<target>/` with a README each.

## Harnesses (added run 1, 2026-11-08)

Each dir has a README.md with exact commands. Copy the dir to a scratch location before use.

- `bench/gameboostd/`: unpack the corpora first with `tar -xJf data.tar.xz`. The harness
  `#include`s gameboostd.c with main renamed.
  - `match_ab.sh A B N`: callgrind Ir per checked cmdline.
  - `mem_e2e.sh A B N`: whole-daemon PSS after Steam/Wine-heavy checks, in a pid namespace with sleepers.
  - `pair_ab.sh A B ev N "live:dup ..."`: paired CPU ns per exec event.
  - `ev_ab.sh`: strace syscalls per event.
  - `e2e_ab.sh`: whole main loop with a fake connector.
  - `equiv.sh` / `one_eq.sh` / `seqtest.c`: equivalence checks.
  - `flags.sh`: build-flag variants. `gen_corpus.py N SEED mix|desktop`: deterministic synthetic corpora.
- `bench/gameboost-scripts/`: a fake sysfs/proc/run tree in a mount namespace (`ns.sh`), with
  stub commands that log their argv (`stub.c`).
  - `ab.py`: whole-tree CPU via rusage, interleaved.
  - `run.sh` / `timing.sh`: callgrind bash Ir.
  - `compare.sh`: equivalence of stdout, stderr, rc, the stub log and the final tree.
  - `patequiv.sh` / `parsefuzz.py` / `realkill.py` / `realtree.py`: targeted equivalence.
  - The paths assume the old flat layout: the scripts now live in `system/services/gameboost/scripts/`.
- `bench/mastertile/`: a node mock of the KWin 6 API (`kwin-mock.js`, `scenarios.js`).
  - `counts.js`: deterministic bridge crossings per event (`--detail` for a per-property breakdown).
  - `equiv.js`: trace equivalence. `timing.js`: node / --jitless timing. `mutants.py`: harness sensitivity.
  - `qjsengine/`: a Qt6 QJSEngine C++ host (needs `apt-get install qt6-declarative-dev`, cmake).
    Use it for callgrind Ir in the engine KWin actually uses.
- Method used in run 1: an analysis agent per target, then an independent re-bench, then 3 skeptics
  (correctness / measurement with a different method / relevance). After that the composed patch
  is verified again by 2 skeptics. Prefer deterministic metrics (callgrind, strace, bridge counts):
  the 4 shared vCPUs make wall-clock noisy.

## Harnesses (added run 2, 2026-11-09): `bench/run2-<target>/`
Alternative, independent harnesses for the same three targets (each with README.md and patches/):
- `run2-gameboostd/`: driver.c + fake /proc trees (gen_tree.sh); `ir.sh` = callgrind Ir per
  steady-state scan/event; `realproc.sh`, `daemon_rss.sh`; `equiv.c` regex-split fuzzer.
- `run2-gameboost-scripts/`: fake root bind-mounted on /srv (unshare -m, needs root);
  `setup.sh base=<checkout> new=<checkout>`, `snap.sh`, `correctness.sh new` (42 cases),
  `metrics.sh base new` (Ir+spawns), `wall.sh` (abrun ABAB, GB_CPU).
- `run2-mastertile/`: `mock.js`/`scenario.js`; `summary.js base new` (API accesses per phase),
  `check.js old new --seeds 3000 --steps 200`.
Install hyperfine/shellcheck with apt-get at the start of a run if missing.
