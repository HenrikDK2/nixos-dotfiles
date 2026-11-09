# mastertile bench harness

Mock-KWin harness for `home/programs/desktop/plasma/files/kwin/mastertile/contents/code/main.js`
(KWin JS script). The script under test is a parameter. Nothing here touches the repo.

Requires node >= 18. `qjs` (QuickJS, `apt-get install quickjs`) is optional and gives
timings from a bytecode interpreter with no JIT.

## Files

| file | purpose |
|------|---------|
| `kwin-mock.js` | Mock of the KWin 6 API the script uses: `workspace` (`windowList()`, `windowAdded`, `activeWindow`, `currentDesktop`, `rootTile(output, desktop)` for 6.4+, or `tilingForScreen(output / name)` for 6.0–6.3), windows (`frameGeometry`, `tile` r/w, `output`, `desktops`, flags, 7 signals), tiles (`tiles`, `windows`, `absoluteGeometry`), `readConfig`, `print`, `registerShortcut`. Counts every bridge crossing (see below) and records a trace of every side effect. Setting `window.tile` behaves like `Window::setTile` (leaves old tile, joins new, moves the window to the tile minus padding, emits `frameGeometryChanged` then `tileChanged`). |
| `scenarios.js` | 136 fixed scenarios + a seeded random generator. Engine-agnostic (node and qjs). |
| `equiv.js` | Behaviour check: old vs new on every fixed scenario plus N random seeds. Compares the full trace: each `window.tile` write (window, tile), `workspace.activeWindow` write, `print` line, plus final per-window tile, `mt` state (tile/key/userUntiled) and geometry. Exit 1 on the first difference. |
| `mutants.py` | Plants 14 known bugs in a source and checks `equiv.js` catches each (sanity check of the harness). |
| `counts.js` | Deterministic bridge-crossing counts per event for each scenario and source. |
| `timing.js` | node ns/event of the measured part only, interleaved A/B(/C), rotated order per batch, warm-up, median + min-max + median of per-batch paired ratios. Run with `node --jitless` too. |
| `qjs-timing.js` | Same idea under QuickJS (ms clock, so batches are large). |

### Counted categories (per event)

* `read` – Q_PROPERTY read on a KWin QObject (window/tile/workspace/output/tile manager). Arrays (`tiles`, `windows`, `desktops`) are fresh copies on every read like QList conversions.
* `write` – Q_PROPERTY write (`window.tile = …`, `workspace.activeWindow = …`).
* `call` – invokable/global call: `windowList`, `rootTile`, `tilingForScreen`, `readConfig`, `print`, `connect`, `registerShortcut`.
* `dyn` – read/write of the script's own expando `window.mt` (in QV4 this misses the QObject property cache first).
* `value` – member read on a returned QRectF (`geometry.x` …). Whether this is a C++ crossing depends on the Qt version's value-type wrappers, so it is reported separately.

`bridge` = read + write + call + dyn; `+value` = bridge + value.

### Scenarios

* `place/<layout>[/stack]/N<n>` – the n-th `windowAdded` into a layout already holding n-1 placed windows (layouts: cols3, grid2x2, grid3x2, master3 = master + 3-row stack, cols6; `/stack` = StackExtra on). Includes the handlers run by the resulting tile write.
* `storm/move` – interactive move of a tiled window: started, untiled, 300 geometry updates, finished.
* `storm/tiled` – 3 tiled windows each get 100 geometry changes (tile resize).
* `storm/float` – 300 geometry changes of a floating overflow window (StackExtra off, 7 windows in 6 tiles): the full handler path.
* `storm/float-reserved` – same for a window that remembers a tile.
* `desktop/<api>[/perdesk]` – two tiled windows moved to another desktop (6.4+ per-desktop layouts, or one shared layout).
* `focus|swap/<layout>` – every live window × 4 directions, with one empty tile.
* `fullscreen` – enter + exit fullscreen of a tiled window.
* `startup/N4|N12` – script load with existing windows (half tiled, some at tile geometry).
* `random/<seed>` (equiv only) – 1–2 outputs, random layouts (children sometimes listed out of geometric order, overlapping leaves, empty roots), all three root-tile APIs, per-desktop layouts on/off, random config (all 5 fill orders, custom orders, ignored classes, StackExtra, Debug), 20–80 random ops: add (dialog/transient/minimized/fullscreen/all-desktops/ignored/unmoveable variants), close, fullscreen toggle, minimize, interactive move + drop near/at/away from tiles, programmatic geometry (incl. ±20px of a tile), desktop moves, external tile assignment, move/resize flags held while other windows are placed, focus/swap shortcuts, desktop switch, config changes.

## Commands

Paths below are relative to this directory; any `label=path/to/main.js` works.

```sh
SRC_OLD=../variants/base/main.js          # e.g. pristine copy of the script
SRC_NEW=../variants/combo-all/main.js     # candidate

# 1. syntax
node --check "$SRC_NEW"

# 2. harness sanity: all 14 planted bugs must be caught
python3 mutants.py . "$SRC_OLD" /tmp/mt-mutants     # (dir must exist)

# 3. behaviour equivalence (136 fixed + 5000 random scenarios)
node equiv.js "$SRC_OLD" "$SRC_NEW" 5000

# 4. deterministic bridge counts per event (last two columns: % fewer, old vs new)
node counts.js old="$SRC_OLD" new="$SRC_NEW"
node counts.js --filter '^storm' --detail old="$SRC_OLD"     # per-property breakdown

# 5. timing (noisy on a shared box; prefer jitless / qjs, many batches)
node --jitless timing.js --batches 21 old="$SRC_OLD" new="$SRC_NEW"
node timing.js --batches 21 --scen '^storm/' old="$SRC_OLD" new="$SRC_NEW"
qjs --std qjs-timing.js "$PWD" 11 '^(storm/move|storm/tiled|storm/float)$' 3000 old="$SRC_OLD" new="$SRC_NEW"
```

`timing.js` options: `--batches N` (default 15), `--scen REGEX`, `--events N` (target measured
events per variant per batch, default 3000), `--reps R` (override), `--json FILE`.

## Caveats

* Real KWin runs QJSEngine (QV4: interpreter + baseline JIT), not V8. Treat node JIT
  timings as noise-prone hints; bridge counts are the primary, engine-independent metric.
* The mock emits `frameGeometryChanged`/`tileChanged` synchronously on `window.tile` writes
  and untiles a window when it goes fullscreen; real KWin (Wayland) may apply geometry later.
  Both sides of an A/B see the same mock, so the comparison stays fair.

## Candidate workflow used on 2026-11-08 (files one level up)

* `../variants/base/main.js` – pristine copy; `../mkvariant.py NAME` or
  `../mkvariant.py combo=a+b+c` applies the exact-string edits in `EDITS` to base and writes
  `../variants/<name>/main.js`.
* `../mkpatches.sh` – regenerates `../patches/<name>.diff` (paths `a/home/...`, `b/home/...`,
  apply from repo root with `patch -p1`) and checks each applies to the pristine tree.
* `../run-timing.sh`, `../run-timing2.sh` – the timing runs whose output is in `../results/`;
  `../results/counts-all.json` / `counts-summary.txt` hold the deterministic counts.
