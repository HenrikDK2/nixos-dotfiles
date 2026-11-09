# Plant deliberate bugs into a source and check equiv.js reports each one.
# usage: python3 mutants.py BENCH_DIR SRC OUTDIR
import sys, subprocess, os
bench, src, out = sys.argv[1:4]
base = open(src).read()
M = [
 ("tolerance", "const GEOM_TOLERANCE_PX = 16;", "const GEOM_TOLERANCE_PX = 15;"),
 ("score", "secondary * 1.5", "secondary * 1.4"),
 ("stack-tie", "cfg.stackExtra && count < fewest", "cfg.stackExtra && count <= fewest"),
 ("frame-guard-resize", "window.move || window.resize ||\n            window.tile", "window.move ||\n            window.tile"),
 ("restore-guard-move", "window.move || window.resize || window.tile) {\n        return;", "window.resize || window.tile) {\n        return;"),
 ("shares-allDesktops", "if (context.onAllDesktops || other.onAllDesktops) return true;", "if (context.onAllDesktops) return true;"),
 ("loop1-minimized", "if (window !== selfWindow && !window.minimized &&", "if (window !== selfWindow &&"),
 ("loop2-transient", "window.dialog || window.transient || !sharesContext", "window.dialog || !sharesContext"),
 ("center-left", "return distance || (rightFirst ? b - a : a - b);", "return distance || (rightFirst ? a - b : a - b);"),
 ("fullscreen-reserve", "(fullScreen && reserved) ||", ""),
 ("key-rounding", "${Math.round(g.x)},${Math.round(g.y)}", "${Math.round(g.y)},${Math.round(g.x)}"),
 ("untile-on-move", "state.userUntiled = true;", "state.userUntiled = false;"),
 ("focus-gap", "if (found) window = found;\n            return found !== null;", "if (found) window = found;\n            return true;"),
 ("desktop-keep", "if (desktopChanged && window.tile && snapshot.byTile.has(window.tile)) {", "if (desktopChanged && window.tile) {"),
]
caught = 0; tried = 0
for name, a, b in M:
    if base.count(a) != 1:
        print(f"SKIP {name}: pattern not found once"); continue
    p = os.path.join(out, name + ".js")
    open(p, "w").write(base.replace(a, b))
    r = subprocess.run(["node", os.path.join(bench, "equiv.js"), src, p, "3000"], capture_output=True, text=True)
    tried += 1
    ok = r.returncode != 0
    caught += ok
    print(("CAUGHT " if ok else "MISSED ") + name + ("  " + r.stdout.splitlines()[0] if ok else ""))
print(f"{caught}/{tried} mutants caught")
