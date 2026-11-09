"use strict";
// Correctness: run old and new main.js over the same event sequences and
// require identical traces: every script write (Window.tile=, frameGeometry=,
// workspace.activeWindow=), every print(), every exception, and the full
// window/tile/remembered-state dump after every step.
// usage: node check.js <old main.js> <new main.js> [--seeds 600] [--steps 120]
const { loadScript, LAYOUTS, rect } = require("./mock");
const { makeEnv, phases, CLASSES } = require("./scenario");

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const oldScript = loadScript(args[0]);
const newScript = loadScript(args[1]);
const seeds = Number(opt("--seeds", "600"));
const steps = Number(opt("--steps", "120"));

function mulberry32(a) {
    return function () {
        a |= 0; a = a + 0x6D2B79F5 | 0;
        let t = Math.imul(a ^ a >>> 15, 1 | a);
        t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
        return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
}

const CONFIGS = [
    {},
    { FillOrder: 0 }, { FillOrder: 1 }, { FillOrder: 3 },
    { FillOrder: 4, CustomOrder: "3, 1;2 9 2" },
    { StackExtra: true }, { StackExtra: true, FillOrder: 1 },
    { Debug: true }, { Debug: true, StackExtra: true },
    { IgnoredClasses: "Steam, discord" },
];

function trace(env, label, fn) {
    const before = env.writeLog.length;
    let err = "";
    try { fn(); } catch (e) { err = " E:" + e.message; }
    return label + err + " | " + env.writeLog.slice(before).join("; ") + " | " + env.dumpState();
}

function fixedTrace(script, N, layout, config) {
    const env = makeEnv(script, { layout, config, detailed: false });
    const ctx = {};
    return phases(N).map(p => trace(env, p.name, () => p.run(env, ctx)));
}

function randomTrace(script, seed) {
    const rnd = mulberry32(seed);
    const pick = xs => xs[Math.floor(rnd() * xs.length)];
    const layoutNames = Object.keys(LAYOUTS);
    const env = makeEnv(script, {
        layout: pick(layoutNames), config: pick(CONFIGS), detailed: false,
        tilingApi: seed % 5 === 3 ? "output" : seed % 5 === 4 ? "name" : "rootTile",
    });
    const out = [];
    const normals = () => env.windows.filter(w => w._normal);
    const anyLeaf = w => {
        const root = env.roots.get(w._output._id + ":" + (w._desktops[0] || env.desktops[0])._id);
        const leaves = env.leavesOf(root);
        return pick(leaves);
    };
    for (let s = 0; s < steps; s++) {
        const r = rnd();
        const ws = normals();
        const w = ws.length ? pick(ws) : null;
        let label, fn;
        if (r < 0.16 || !w) {
            const kind = rnd();
            const output = rnd() < 0.8 ? env.outputs[0] : env.outputs[1];
            const dk = rnd();
            const desktops = dk < 0.7 ? [env.desktops[0]] : dk < 0.85 ? [env.desktops[1]] : dk < 0.93 ? [] : [env.desktops[0], env.desktops[1]];
            const props = {
                output, desktops,
                normalWindow: kind > 0.04,
                dialog: kind > 0.04 && kind < 0.08,
                transient: kind > 0.08 && kind < 0.11,
                moveable: rnd() > 0.04, resizeable: rnd() > 0.04,
                minimized: rnd() < 0.03,
                resourceClass: pick(CLASSES.concat(["Steam", "kate"])),
                geometry: rect(Math.floor(rnd() * 1800), Math.floor(rnd() * 900), 400 + Math.floor(rnd() * 900), 300 + Math.floor(rnd() * 600)),
            };
            label = "add";
            fn = () => {
                if (rnd() < 0.2) {
                    const root = env.roots.get(output._id + ":" + (desktops[0] || env.desktops[0])._id);
                    props.geometry = env.tileGeomForWindow(pick(env.leavesOf(root)));
                }
                env.addWindow(props);
            };
        } else if (r < 0.22) {
            label = "close"; fn = () => env.closeWindow(w);
        } else if (r < 0.30) {
            label = "tileResize"; fn = () => {
                const root = env.rootFor(rnd() < 0.85 ? 0 : 1, rnd() < 0.8 ? 0 : 1);
                if (!root._weights) return;
                if (rnd() < 0.1) {
                    // Layout edited in the tile editor: new tile objects.
                    const spec = LAYOUTS[pick(layoutNames)];
                    for (const leaf of env.leavesOf(root)) for (const x of leaf._windows.slice()) x.kwinSetTile(null);
                    root._children = [];
                    rebuild(env, root, spec);
                } else {
                    root._weights[0] = Math.max(0.3, root._weights[0] + (rnd() - 0.5) * 0.3);
                    env.relayout(root);
                }
            };
        } else if (r < 0.40) {
            label = "appGeometry"; fn = () => {
                if (rnd() < 0.3) env.moveTo(w, env.tileGeomForWindow(anyLeaf(w)));
                else {
                    const g = w._geom;
                    env.moveTo(w, rect(g.x + Math.floor(rnd() * 21) - 10, g.y + Math.floor(rnd() * 21) - 10, g.width + Math.floor(rnd() * 41) - 20, g.height));
                }
            };
        } else if (r < 0.50) {
            label = "drag"; fn = () => {
                env.startMove(w, rnd() < 0.8);
                const k = 1 + Math.floor(rnd() * 6);
                for (let i = 0; i < k; i++) env.moveTo(w, rect(Math.floor(rnd() * 2000), Math.floor(rnd() * 1000), w._geom.width, w._geom.height));
                const f = rnd();
                if (f < 0.3) env.finishMove(w, anyLeaf(w));
                else if (f < 0.6) { env.moveTo(w, env.tileGeomForWindow(anyLeaf(w))); env.finishMove(w); }
                else env.finishMove(w);
            };
        } else if (r < 0.57) {
            label = "fullscreen"; fn = () => env.setFullScreen(w, !w._fullScreen, rnd() < 0.5);
        } else if (r < 0.62) {
            label = "minimize"; fn = () => env.setMinimized(w, !w._minimized);
        } else if (r < 0.68) {
            label = "desktops"; fn = () => {
                const dk = rnd();
                env.setDesktops(w, dk < 0.4 ? [env.desktops[0]] : dk < 0.8 ? [env.desktops[1]] : dk < 0.9 ? [] : [env.desktops[1], env.desktops[2]]);
            };
        } else if (r < 0.70) {
            label = "currentDesktop"; fn = () => env.setCurrentDesktop(Math.floor(rnd() * 2));
        } else if (r < 0.80) {
            const dir = pick(["left", "right", "up", "down"]);
            label = "focus-" + dir; fn = () => { if (rnd() < 0.5) env.setActive(pick(env.windows)); env.shortcut("mastertile-focus-" + dir); };
        } else if (r < 0.88) {
            const dir = pick(["left", "right", "up", "down"]);
            label = "swap-" + dir; fn = () => { if (rnd() < 0.5) env.setActive(pick(env.windows)); env.shortcut("mastertile-swap-" + dir); };
        } else if (r < 0.92) {
            label = "config"; fn = () => {
                for (const k of Object.keys(env.config)) delete env.config[k];
                Object.assign(env.config, pick(CONFIGS));
            };
        } else {
            label = "kwinTile"; fn = () => w.kwinSetTile(rnd() < 0.7 ? anyLeaf(w) : null);
        }
        out.push(trace(env, label, fn));
    }
    return out;
}

// Rebuild a root's children from a spec (KWin tile editor change).
function rebuild(env, root, spec) {
    const Tile = env.Tile;
    const build = (tile, s) => {
        tile._dir = s.dir;
        tile._weights = s.parts.map(p => (typeof p === "number" ? p : p.weight || 1));
        tile._children = s.parts.map(p => {
            const child = new Tile(tile);
            if (typeof p !== "number" && p.parts) build(child, p);
            return child;
        });
    };
    build(root, spec);
    env.relayout(root);
}

function compare(a, b, what) {
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
        if (a[i] !== b[i]) {
            console.log(`MISMATCH ${what} step ${i}\n  old: ${a[i]}\n  new: ${b[i]}`);
            return false;
        }
    }
    return true;
}

let ok = 0, bad = 0, writes = 0, prints = 0, errors = 0;
for (const layout of Object.keys(LAYOUTS)) {
    for (const N of [1, 2, 3, 4, 5, 6, 8, 12, 16]) {
        for (const config of CONFIGS) {
            const a = fixedTrace(oldScript, N, layout, config);
            const b = fixedTrace(newScript, N, layout, config);
            if (compare(a, b, `fixed N=${N} ${layout} ${JSON.stringify(config)}`)) ok++; else bad++;
            for (const line of a) { writes += (line.match(/[TAG] w?\S+/g) || []).length; }
        }
    }
}
for (let seed = 1; seed <= seeds; seed++) {
    const a = randomTrace(oldScript, seed);
    const b = randomTrace(newScript, seed);
    if (compare(a, b, `random seed=${seed}`)) ok++; else bad++;
    for (const line of a) {
        const mid = line.split(" | ")[1] || "";
        for (const e of mid.split("; ")) { if (/^[TAG] /.test(e)) writes++; if (/^P /.test(e)) prints++; }
        if (line.includes(" E:")) errors++;
    }
}
console.log(`traces identical: ${ok}, mismatched: ${bad} (old: ~${writes} writes, ${prints} prints, ${errors} exception steps)`);
process.exit(bad ? 1 : 0);
