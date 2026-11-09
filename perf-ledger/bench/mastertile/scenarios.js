// Deterministic scenarios + a seeded random scenario generator for mastertile.
// Each scenario: run(src, measure) -> { trace: [...], marks: { name: {events, stats} } }
// `measure(name, events, fn)` brackets the measured part; outside it nothing is
// counted into marks (setup), but the full trace is always kept for equivalence.
(function (root) {
"use strict";
const M = (typeof require === "function") ? require("./kwin-mock.js").KWinMock : globalThis.KWinMock;
const { World, layouts } = M;

const STAT_KEYS = ["read", "write", "call", "value", "dyn"];

function snap(S) { const o = {}; for (const k of STAT_KEYS) o[k] = S[k]; return o; }
function diff(a, b) { const o = {}; for (const k of STAT_KEYS) o[k] = b[k] - a[k]; return o; }

function finalState(world) {
    const out = [];
    for (const w of world.windows) {
        const mt = w._mt;
        out.push("final " + w.id + " tile=" + (w._tile ? w._tile.id : "-") +
            " mt=" + (mt ? (mt.tile ? mt.tile.id : "-") + "/" + mt.key + "/" + mt.userUntiled : "none") +
            " geom=" + w._geom.join(","));
    }
    out.push("active " + (world._active ? world._active.id : "-"));
    return out;
}

function makeWorld(opts) {
    return new World(Object.assign({
        api: "rootTile",
        desktops: 2,
        outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.cols(3) }],
        config: {},
    }, opts));
}

// Window geometry that never matches a tile (cascade from 37,41).
function floatGeom(i) { return [37 + 23 * i, 41 + 19 * i, 701, 503]; }

const DIRS = ["left", "right", "up", "down"];

const LAYOUTS = {
    cols3: () => layouts.cols(3),
    grid2x2: () => layouts.grid(2, 2),
    grid3x2: () => layouts.grid(3, 2),
    master3: () => layouts.masterStack(3),
    cols6: () => layouts.cols(6),
};

// Scenario registry --------------------------------------------------------
const scenarios = {};

// Place the Nth window into a layout that already holds N-1 placed windows.
for (const lname of Object.keys(LAYOUTS)) {
    for (const stack of [false, true]) {
        for (let N = 1; N <= 12; N++) {
            const name = "place/" + lname + (stack ? "/stack" : "") + "/N" + N;
            scenarios[name] = (src, measure) => {
                const world = makeWorld({
                    outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: LAYOUTS[lname]() }],
                    config: { StackExtra: stack },
                });
                world.load(src);
                for (let i = 0; i < N - 1; i++) world.addWindow({ geometry: floatGeom(i) });
                measure(world, "place", 1, () => world.addWindow({ geometry: floatGeom(N - 1) }));
                return world;
            };
        }
    }
}

// Interactive move storm of a tiled window (move flag set, user-untiled).
scenarios["storm/move"] = (src, measure) => {
    const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.cols(3) }] });
    world.load(src);
    const ws = [];
    for (let i = 0; i < 3; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
    measure(world, "move", 300, () => world.interactiveMove(ws[0], 300, floatGeom(7)));
    return world;
};

// Geometry storm of a floating, not user-untiled window (e.g. an app resizing
// itself, or KWin animating it): the full handler path runs on every event.
scenarios["storm/float"] = (src, measure) => {
    const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.grid(3, 2) }] });
    world.load(src);
    const ws = [];
    for (let i = 0; i < 7; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
    const w = ws[6]; // 7th window: no free tile, StackExtra=false -> floating
    measure(world, "float", 300, () => {
        for (let i = 0; i < 300; i++) world.setGeometry(w, [300 + (i % 50), 200, 640 + (i % 7), 480]);
    });
    return world;
};

// Same, but the window remembers a tile (reserved key) - e.g. after a
// fullscreen exit that could not rebind.
scenarios["storm/float-reserved"] = (src, measure) => {
    const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.grid(3, 2) }] });
    world.load(src);
    const ws = [];
    for (let i = 0; i < 6; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
    const w = ws[5];
    world.setMinimized(w, true);
    world.setTile(w, null);  // untiled by KWin while minimized: keeps reservation
    world.setMinimized(w, false);
    measure(world, "float-reserved", 300, () => {
        for (let i = 0; i < 300; i++) world.setGeometry(w, [300 + (i % 50), 200, 640 + (i % 7), 480]);
    });
    return world;
};

// Tiled windows receiving geometry changes (tile layout resize).
scenarios["storm/tiled"] = (src, measure) => {
    const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.cols(3) }] });
    world.load(src);
    const ws = [];
    for (let i = 0; i < 3; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
    measure(world, "tiled", 300, () => {
        for (let i = 0; i < 100; i++) {
            for (const w of ws) {
                const g = world.tileGeom(w._tile);
                world.setGeometry(w, [g[0], g[1], g[2] - (i % 5) - 1, g[3]]);
            }
        }
    });
    return world;
};

// Window moved to another desktop. perDesktop: 6.4+ per-desktop layouts.
for (const per of [true, false]) {
    for (const api of ["rootTile", "tilingForScreen"]) {
        if (api === "tilingForScreen" && per) continue;
        const name = "desktop/" + api + (per ? "/perdesk" : "");
        scenarios[name] = (src, measure) => {
            const world = makeWorld({
                api, perDesktopLayouts: per,
                outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.grid(2, 2) }],
            });
            world.load(src);
            const ws = [];
            for (let i = 0; i < 4; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
            measure(world, "desktop", 2, () => {
                world.moveToDesktop(ws[1], world.desktops[1]);
                world.moveToDesktop(ws[2], world.desktops[1]);
            });
            return world;
        };
    }
}

// Directional focus / swap from every tile in every direction.
for (const lname of ["cols3", "grid2x2", "grid3x2"]) {
    for (const op of ["focus", "swap"]) {
        scenarios[op + "/" + lname] = (src, measure) => {
            const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: LAYOUTS[lname]() }] });
            world.load(src);
            const ws = [];
            const n = lname === "cols3" ? 3 : lname === "grid2x2" ? 4 : 6;
            for (let i = 0; i < n; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
            // leave one tile empty so focus has to skip a gap and swap moves into it
            world.closeWindow(ws[0]);
            const live = ws.slice(1);
            measure(world, op, live.length * 4, () => {
                for (const w of live) {
                    for (const d of DIRS) {
                        world.setActive(w);
                        world.shortcut("mastertile-" + op + "-" + d);
                    }
                }
            });
            return world;
        };
    }
}

// Fullscreen enter/exit of a tiled window.
scenarios["fullscreen"] = (src, measure) => {
    const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.grid(2, 2) }] });
    world.load(src);
    const ws = [];
    for (let i = 0; i < 4; i++) ws.push(world.addWindow({ geometry: floatGeom(i) }));
    measure(world, "fullscreen", 2, () => {
        world.setFullScreen(ws[1], true);
        world.setFullScreen(ws[1], false);
    });
    return world;
};

// Script start with N existing windows (half tiled, half floating).
for (const N of [4, 12]) {
    scenarios["startup/N" + N] = (src, measure) => {
        const world = makeWorld({ outputs: [{ name: "DP-1", rect: [0, 0, 1920, 1080], layout: layouts.grid(3, 2) }] });
        const leaves = [];
        (function walk(t) { if (!t._children.length) leaves.push(t); else t._children.forEach(walk); })(world.rootFor({ _output: world.outputs[0], _desktops: [world.desktops[0]] }));
        for (let i = 0; i < N; i++) {
            const w = world.preexisting({ geometry: floatGeom(i) });
            if (i % 2 === 0) world.setTile(w, leaves[(i / 2) % leaves.length]);
            else if (i % 4 === 1) world.setGeometry(w, world.tileGeom(leaves[(i + 3) % leaves.length]));
        }
        measure(world, "startup", 1, () => world.load(src));
        return world;
    };
}

// Seeded random scenario generator ------------------------------------------
function mulberry32(a) {
    return function () {
        a |= 0; a = a + 0x6D2B79F5 | 0;
        let t = Math.imul(a ^ a >>> 15, 1 | a);
        t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
        return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
}

// Children listed in a different order than their geometry (e.g. after a
// split in KWin's tile editor), so traversal order != left-to-right order.
function shuffleTree(rnd, node) {
    if (Array.isArray(node)) return node;
    const c = node.c.map(x => shuffleTree(rnd, x));
    for (let i = c.length - 1; i > 0; i--) {
        const j = Math.floor(rnd() * (i + 1));
        const t = c[i]; c[i] = c[j]; c[j] = t;
    }
    return { r: node.r, c };
}

function randomLayout(rnd, X, W, H) {
    const lay = randomLayout0(rnd, X, W, H);
    return rnd() < 0.5 ? shuffleTree(rnd, lay) : lay;
}

function randomLayout0(rnd, X, W, H) {
    const k = Math.floor(rnd() * 6);
    switch (k) {
    case 0: return layouts.cols(1 + Math.floor(rnd() * 5), W, H, X);
    case 1: return layouts.grid(1 + Math.floor(rnd() * 3), 1 + Math.floor(rnd() * 3), W, H, X);
    case 2: return layouts.masterStack(1 + Math.floor(rnd() * 4), W, H, X);
    case 3: return layouts.empty(W, H, X);
    case 4: { // overlapping / near-duplicate leaves (geometry ties)
        const a = [X, 0, Math.round(W / 2), H], b = [X + 5, 3, Math.round(W / 2) - 4, H - 2];
        return { r: [X, 0, W, H], c: [a, b, [X + Math.round(W / 2), 0, W - Math.round(W / 2), H]] };
    }
    default: return layouts.cols(2 + Math.floor(rnd() * 3), W, H, X);
    }
}

function randomScenario(seed) {
    return (src, measure) => {
        const rnd = mulberry32(seed);
        const pick = arr => arr[Math.floor(rnd() * arr.length)];
        const nOut = rnd() < 0.3 ? 2 : 1;
        const outputs = [];
        for (let i = 0; i < nOut; i++) {
            const X = i * 1920;
            const lay = randomLayout(rnd, X, 1920, 1080);
            const lay2 = randomLayout(rnd, X, 1920, 1080);
            outputs.push({ name: "DP-" + (i + 1), rect: [X, 0, 1920, 1080], layout: lay, layoutFor: d => d === "d1" ? lay2 : lay });
        }
        const config = {
            FillOrder: Math.floor(rnd() * 5),
            CustomOrder: pick(["", "2,3,1", "3 1", "5;4;1,2", "x, 2, 2, 9"]),
            IgnoredClasses: pick(["", "ignoreme", " IgnoreMe , other"]),
            StackExtra: rnd() < 0.5,
            Debug: rnd() < 0.5,
        };
        const world = makeWorld({
            api: pick(["rootTile", "rootTile", "tilingForScreen", "name"]),
            perDesktopLayouts: rnd() < 0.5,
            outputs, config, padding: pick([0, 4, 8, 10, 20]),
        });
        // Some pre-existing windows.
        const pre = Math.floor(rnd() * 4);
        for (let i = 0; i < pre; i++) world.preexisting({ geometry: floatGeom(i), output: pick(world.outputs) });
        world.load(src);

        const allTiles = () => {
            const res = [];
            for (const m of world.roots.values()) for (const r of m.values()) {
                (function walk(t) { res.push(t); t._children.forEach(walk); })(r);
            }
            return res;
        };

        // A tile's window geometry nudged by up to +-20px per edge (tolerance is 16).
        const jitter = g => g.map(v => v + Math.floor(rnd() * 41) - 20);
        const near = () => { const g = world.tileGeom(pick(allTiles())); return rnd() < 0.5 ? jitter(g) : g; };

        const steps = 20 + Math.floor(rnd() * 60);
        measure(world, "random", steps, () => {
            for (let s = 0; s < steps; s++) {
                const r = rnd();
                const ws = world.windows;
                const w = ws.length ? pick(ws) : null;
                if (r < 0.3 || !w) {
                    world.addWindow({
                        geometry: rnd() < 0.2 ? near() : floatGeom(Math.floor(rnd() * 9)),
                        output: pick(world.outputs),
                        desktops: rnd() < 0.8 ? [world.desktops[0]] : [world.desktops[1]],
                        onAllDesktops: rnd() < 0.1,
                        dialog: rnd() < 0.05, transient: rnd() < 0.05,
                        normalWindow: rnd() < 0.95, minimized: rnd() < 0.05,
                        moveable: rnd() < 0.97, resizeable: rnd() < 0.97,
                        fullScreen: rnd() < 0.05,
                        resourceClass: rnd() < 0.1 ? "IgnoreMe" : undefined,
                    });
                } else if (r < 0.36) {
                    world.closeWindow(w);
                } else if (r < 0.44) {
                    world.setFullScreen(w, !w._p.fullScreen);
                } else if (r < 0.48) {
                    world.setMinimized(w, !w._p.minimized);
                } else if (r < 0.56) {
                    const drop = rnd() < 0.5 ? near() : floatGeom(Math.floor(rnd() * 9));
                    world.interactiveMove(w, 1 + Math.floor(rnd() * 5), drop);
                } else if (r < 0.64) {
                    const g = rnd() < 0.5 ? near() : floatGeom(Math.floor(rnd() * 9));
                    world.setGeometry(w, g);
                } else if (r < 0.70) {
                    world.moveToDesktop(w, pick(world.desktops));
                } else if (r < 0.74) {
                    world.setTile(w, rnd() < 0.3 ? null : pick(allTiles()));
                } else if (r < 0.80) {
                    w._p.move = rnd() < 0.3; w._p.resize = rnd() < 0.2;
                    world.setGeometry(w, rnd() < 0.5 ? near() : floatGeom(Math.floor(rnd() * 9)));
                    if (rnd() < 0.5) {
                        // another window appears / the user focuses while this one is mid-move
                        if (rnd() < 0.6) world.addWindow({ geometry: floatGeom(Math.floor(rnd() * 9)), output: pick(world.outputs) });
                        else { world.setActive(pick(world.windows)); world.shortcut("mastertile-" + pick(["focus", "swap"]) + "-" + pick(DIRS)); }
                    }
                    w._p.move = false; w._p.resize = false;
                } else if (r < 0.92) {
                    world.setActive(rnd() < 0.9 ? w : null);
                    world.shortcut("mastertile-" + pick(["focus", "swap"]) + "-" + pick(DIRS));
                } else if (r < 0.95) {
                    world._currentDesktop = pick(world.desktops);
                } else {
                    world.config.FillOrder = Math.floor(rnd() * 5);
                    world.config.StackExtra = rnd() < 0.5;
                    world.config.CustomOrder = pick(["", "1", "3,2,1", "2 4 6"]);
                }
            }
        });
        return world;
    };
}

// Runner ---------------------------------------------------------------------
function runScenario(fn, src, detail) {
    const marks = {};
    const measure = (world, name, events, body) => {
        const S = world.stats;
        if (detail) S.detail = {};
        const before = snap(S);
        body();
        marks[name] = { events, stats: diff(before, snap(S)), detail: S.detail };
        S.detail = null;
    };
    const world = fn(src, measure);
    return { trace: world.trace.concat(finalState(world)), marks, world };
}

root.MTScenarios = { scenarios, randomScenario, runScenario, STAT_KEYS, mulberry32 };
})(typeof module !== "undefined" && module.exports ? module.exports : globalThis);
