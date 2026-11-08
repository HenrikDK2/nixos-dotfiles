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
