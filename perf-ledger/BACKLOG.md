# Backlog (prioritized)

Covered in run 1 (2026-11-08): gameboostd.c, gameboost start.sh/exit.sh, mastertile main.js
(PRs #3/#4/#5). After they merge, re-baseline those targets before testing follow-ups.
Rejected in run 1 (do not retry unless the code changes): tree_pids via task/*/children
(race), IFS=')' stat split (UTF-8 mis-parse), busctl --auto-start=no (ignored by
get-property), single rm in exit.sh (CUPS race), occupancy-visible-memo, float-prune.

## Not yet covered (highest priority for the next runs)
1. mastertile-effect/contents/code/main.js: per-frame/per-event cost (reuse bench/mastertile
   mock + qjsengine host).
2. gameboost notify.sh / status.sh, src/gameboost-hold.c.
3. system/services/auto-update/main.sh.
4. system/services/system-tuning/script.sh, home/services/auto-connect-ethernet/script.sh,
   home/programs/gaming/ffxi_backup/script.sh, micro-run main.lua, qBittorrent nova3 engines.
5. kwin.nix / config.nix KWin settings (mostly UNMEASURABLE here: no compositor).

## Follow-up ideas from run 1 (untested)
- [gameboostd] Measure the real exec-chain rate on the NixOS desktop with bench/execstat.c (it needs root and the real proc connector), to size dedup's benefit. This sandbox gave 0.4% adjacent repeats over 600 s (dominated by benchmark processes) and 24.7% / 36.5% (adjacent / within last 4) in a quiet 60 s window. A look-back of 4 entries may catch about 1.5x more repeats.
- [gameboostd] The remaining regexec DFA heap (about 650-800 kB after Steam/Wine use) comes from alternatives with '.', '.+' or groups. Options: regfree + lazy recompile when leaving game mode (plus malloc_trim) to drop the DFA built during a game launch, or extend the regex-free matcher to '.' (one unescaped dot in e.g. xalia[/\]xalia.exe or [/\]7z.exe). Check with heap.c and mem_e2e.sh.
- [gameboostd] The no-literal exclude alternatives ((^//)(yay/.../cat)[[:space:]], the sudo/timeout one, the link2ea/EA Desktop group) run regexec for every exclude evaluation and cost 0.35-2.4 us per line (altstats). A literal-set prefilter (any-of over a required group's branches) could skip most of them.
- [gameboostd] Wakeup reduction with SO_TIMESTAMP or arrival-time-aware batching: check whether netlink recvmsg returns per-datagram timestamps, then drain only on the timer while keeping the exec -> first check >= 1 s rule.
- [gameboostd] has_lit cost is now mostly memchr call overhead per anchor occurrence (anchors appear 4-8 times per Nix-heavy line). A single pass over the cmdline testing all game-set anchors via a 256-entry byte table might win for long lines; measure with match_ab.sh.
- [gameboostd] Re-run flags.sh in a real nixpkgs build (actual cc-wrapper hardening flags, nixpkgs glibc) to settle -Os / -z noseparate-code; PSS here is bimodal with about 100 kB run-to-run spread.
- [gameboost-scripts] exit.sh restore_saved still walks the whole state five times. The arithmetic for loop costs about 16K instructions per iteration in bash, so exit with state is 54.6M instructions against 13M without state. A single newest-first pass that dispatches each entry to its group would cut most of that, but it changes the write order between groups (SATA/NVMe/PCIe/CPU/GPU). Someone needs to decide whethe…
- [gameboost-scripts] wine_sets_nice reads /proc/PID/limits line by line (17 reads plus a regex per Wine process per boost, about 0.5M instructions each). The 'Max nice priority' row could be found with one read -d '' and substring arithmetic.
- [gameboost-scripts] set_process_priority and tree-children both glob /proc/PID/task/* for every tree process. tree_pids could return the thread lists to set_process_priority and skip the second readdir.
- [gameboost-scripts] The per-CPU sysfs loop (32 CPUs x 3 files) costs about 300K bash instructions per set_saved: function calls, is_saved, three redirections. Inlining set_saved's checks into the loop, or a per-file fast path, could halve the 47M instructions the sysfs phase still costs after set-saved-once.
- [gameboost-scripts] Measure on real NixOS hardware: real systemctl/busctl exec latency, and the gameboost-hold start (Type=notify) wait at entry. Could set_gpu_performance run before the blocking hold start without changing state-file semantics?
- [gameboost-scripts] Re-check the candidates under nixpkgs' bash 5.3 (patequiv.sh, parsefuzz.py, realtree.py, compare.sh all take the bash from PATH).
- [gameboost-scripts] notify.sh runs twice per game, at the same moment as start.sh. Its fork count (setpriv/busctl/notify-send/loginctl/id) was optimized in a previous run, but its CPU was not profiled with this harness.
- [mastertile] Cache the per-root leaf list and geometries, invalidated by KWin tile signals (layoutModified / childTilesChanged / absoluteGeometryChanged). This would remove the remaining tiles and absoluteGeometry reads per storm/float event and per placement, but needs real KWin signal semantics to verify.
- [mastertile] Before any PR of float-prune, verify on real KWin 6.8 that child tiles always lie inside their parent's absoluteGeometry, including minimum-size clamping in nested custom layouts. Alternatively, ship it with a containment check that falls back to the full walk.
- [mastertile] Replace the window.mt expando plus the trackedWindows Set with a Map<window,state>. This avoids the QV4 property-cache miss on every mt access, but changes behaviour when a wrapper is garbage-collected and recreated, so the semantics need deciding.
- [mastertile] Measure on device whether QRectF member reads are C++ crossings in Qt 6.8 QJSEngine (value-type references re-reading the property). That decides whether snapshot-key-from-entry and the +value metric matter. A QV4_PROFILE / QML profiler run of KWin with the script enabled would settle it.
- [mastertile] Extend the harness to the sibling mastertile-effect/contents/code/main.js (per-frame/per-event cost); it is not covered yet.
- [mastertile] Model Wayland's asynchronous geometry ack in kwin-mock (frameGeometryChanged after tileChanged, deferred) and re-run equiv for robustness.
- [mastertile] computeOccupancies converts entry.tile.windows for every leaf, even though windowList() already gives each window's tile via window.tile. Explore deriving explicit occupants from windowList alone; this needs a proof that tile.windows always equals {w : w.tile === tile} in KWin.
