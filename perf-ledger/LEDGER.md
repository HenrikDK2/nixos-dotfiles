# Performance ledger

Memory for the daily perf-optimization routine. One row per tested hypothesis.
Rejected ideas stay rejected unless the target code changed materially since
(check `git log` on the file after the row's date) — say so in the new row.

Verdicts: ACCEPTED (>=5%, verified, but not shipped alone), REJECTED (<5% or
regression or refuted), INCONCLUSIVE (noise > effect), UNMEASURABLE (cannot be
measured in the cloud sandbox), PR-OPENED.

| date | target | hypothesis | method | baseline | result | delta % | verdict | PR link |
|------|--------|------------|--------|----------|--------|---------|---------|---------|

## Run plans

### 2026-11-08 (run 1, ledger created)
Targets (none covered before; picked the three hottest code paths):
1. `system/services/gameboost/gameboostd.c` — per-exec-event cost (drain/check/match),
   full_scan cost (fallback/storm mode), startup (pattern split/compile), build flags
   vs binary size/RSS.
2. `system/services/gameboost/start.sh` + `exit.sh` — game-mode entry/exit latency:
   forks/execs/subshells and wall time against stubbed sysfs + commands.
3. `home/programs/desktop/plasma/files/kwin/mastertile/contents/code/main.js` — per-event
   handler cost (windowAdded/placeWindow, frameGeometryChanged, computeOccupancies,
   snapshot building) with a mocked KWin API, by window count.
Method: Workflow fan-out (analysis+baseline+candidates per target) → independent
re-benchmark → 3 skeptical verifiers per surviving candidate. Sandbox: 4 vCPU, no perf
counters (no `perf`), so instruction counts come from valgrind/callgrind.

### 2026-11-08 run 1 outcome
Interrupted: no hypothesis rows and no RUNS.md row were written. Nothing from run 1 counts
as tested; run 2 re-plans the same targets from scratch (paths moved in a6dcc5d to
`system/services/gameboost/src/` and `scripts/`).

### 2026-11-09 (run 2)
Targets (all still uncovered):
1. `system/services/gameboost/src/gameboostd.c` — per-exec-event cost (proc reads,
   pattern match), full_scan cost, startup, build flags vs size/RSS (callgrind Ir).
2. `system/services/gameboost/scripts/start.sh` + `exit.sh` — entry/exit forks/execs and
   wall time vs stubbed sysfs/commands (strace -f -c, hyperfine).
3. `home/programs/desktop/plasma/files/kwin/mastertile/contents/code/main.js` — per-event
   handler cost with mocked KWin API by window count (node microbench).
Method: Workflow — per target: analysis+harness+baseline+candidates agent, then an
independent re-benchmark agent and 3 skeptical verifiers per candidate claiming >=5%.
