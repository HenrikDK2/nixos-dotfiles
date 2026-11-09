# mastertile benchmark harness

The harness loads `home/programs/desktop/plasma/files/kwin/mastertile/contents/code/main.js`
against a mocked KWin scripting API and drives it with event sequences.

- `mock.js`: the mock KWin API. `workspace` provides windowList(), activeWindow,
  currentDesktop, rootTile() (Plasma 6.4+), or tilingForScreen(output|name) for
  older versions, plus a windowAdded signal. Window and Tile objects expose their
  properties as getters that count every access. Window.tile= and
  frameGeometry= setters, and workspace.activeWindow=, count the write, log it
  and simulate KWin. A tile assignment moves the window to the tile's geometry
  minus 4 px of padding, which emits frameGeometryChanged and then tileChanged
  synchronously, as KWin does. Counters:
  - reads: QObject property reads
  - writes: QObject property writes
  - calls: method calls (windowList, rootTile, tilingForScreen, readConfig)
  - expando: the script's `window.mt` JS-side property, reported but kept out
    of the API total
  - emits: signal emissions that had a handler

  On the real system each read, write or call crosses from QJSEngine into C++,
  and list properties (desktops, tiles, windows) allocate a fresh JS array.
- `scenario.js`: the fixed, realistic scenario for N windows on layout L5
  (3 columns, outer ones split: 5 leaves) or L8 (4x2). It has 3 non-normal
  windows (desktop, panel, notification). Phases:
  - open: N windowAdded placements
  - tileResize: 10 splitter drags; KWin re-applies tile geometry to every tiled window
  - appGeometry: 5 app-driven geometry changes per window
  - drag: two interactive moves, 30 frames each, then a re-tile
  - fullscreen: enter and exit with the tile kept, and with the tile dropped
  - focus: 8 directional focus shortcuts
  - swap: 4 swap shortcuts
  - desktop: desktopsChanged away and back
  - minimizeOpen: a placement while one window is minimized
  - close: every window closes
- `counts.js <main.js> [--n 1,4,8,16] [--layout L5] [--keys]`: deterministic API
  traffic per phase, with a per-property breakdown under `--keys`.
- `summary.js <base.js> <cand.js>...`: base vs candidate API totals and the
  per-event changes.
- `time.js <main.js> [--iters 2000]`: one timing process. It loads the script
  once per N, warms up, then times K repetitions of the scenario with
  process.hrtime.bigint and prints ns/event per phase and ns per full scenario.
  The time includes the mock's own cost (window construction, layout maths), so
  it is a diluted, secondary metric.
- `ab.js <A.js> <B.js> --runs 12 --iters 2000 --cpu 3`: alternates A and B
  processes (ABAB...) pinned with taskset and reports median [min..max] per
  phase. `run_ab_all.sh <base.js> <outdir> <cand.js>...` runs it for several
  candidates.
- `micro.js <main.js> [--iters 400000]`: handler microbenchmarks after opening
  8 windows on L5. It times frameGeometryChanged on a tiled window, during a
  drag and on an untiled overflow window, plus one placement and close. Use it
  through ab.js with `--tool micro.js`.
- `check.js <old.js> <new.js> [--seeds 3000 --steps 200]`: correctness check.
  It covers the fixed scenarios (N in 1..16, five layouts, ten configs: every
  FillOrder, StackExtra, Debug, IgnoredClasses) and seeded random sequences:
  - windows added with mixed types, outputs, desktops and geometries
  - close, tile resize and tile-layout rebuilds
  - app geometry changes, drags with and without a tile snap
  - fullscreen with and without untile, minimize
  - desktop and current-desktop changes
  - focus and swap shortcuts, config changes, KWin-side tile changes
  - all three root-tile APIs

  The old and new traces must match exactly, after every step. A trace holds
  every script write, every print() (Debug logs), every exception, and the
  full window, tile and remembered-state dump. Planted bugs were caught: a
  dropped guard, a wrong remembered entry, a skipped sort, a wrong visibility
  memo and a wrong name strategy. One near-equivalent mutation was not caught:
  passing the traversal-order snapshot to the occupancy pass, which differs
  only when two tiles both match a window within 16 px.

Example:

    M=base/home/programs/desktop/plasma/files/kwin/mastertile/contents/code/main.js
    node bench/counts.js $M --n 8 --keys
    node bench/summary.js $M cands/*/main.js --layout L5
    node bench/check.js $M cands/E/main.js --seeds 3000 --steps 200
    node bench/ab.js $M cands/E/main.js --runs 12 --iters 2000 --cpu 3
    node bench/ab.js $M cands/E/main.js --tool micro.js --runs 12 --iters 400000 --cpu 3

An A/A run (base against a copy of base, 12 alternating runs) showed scenario
TOTAL median differences of -2.6% to +4.7%, and micro-case differences of
-3.8% to +8.4%. Wall-time deltas below about 5% are noise here. The API counts
are exact and deterministic.
