"use strict";
// Mock KWin scripting API for mastertile/contents/code/main.js.
//
// Every QObject property read, property write and method call the script makes
// goes through a counting getter/setter/method (on the real system each one is a
// QJSEngine -> C++ round trip; list properties also allocate a fresh JS array).
// The driver (scenario / random generators) mutates state through underscore
// fields and `kwin*` helpers, which are NOT counted.
//
// Counters:
//   reads  - QObject property reads (Window.*, Tile.*, Output.name, workspace.*)
//   writes - QObject property writes (Window.tile, workspace.activeWindow)
//   calls  - method calls (workspace.windowList, workspace.rootTile, readConfig, ...)
//   expando - reads/writes of the script's own `mt` expando on window wrappers
//             (reported separately: a JS-side property, not a C++ call)

const fs = require("fs");
const vm = require("vm");

class Signal {
    constructor() { this.handlers = []; }
    connect(fn) { this.handlers.push(fn); }
    disconnect(fn) {
        const i = this.handlers.indexOf(fn);
        if (i >= 0) this.handlers.splice(i, 1);
    }
    emit(...args) {
        if (this.handlers.length && Signal.onEmit) Signal.onEmit();
        for (const h of this.handlers.slice()) h(...args);
    }
}

const rect = (x, y, width, height) => ({ x, y, width, height });
const copyRect = r => ({ x: r.x, y: r.y, width: r.width, height: r.height });
const sameRect = (a, b) => a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height;

const TILE_PADDING = 4;

function createEnv(options = {}) {
    const stats = {
        reads: 0, writes: 0, calls: 0, expando: 0, emits: 0,
        byKey: Object.create(null),
    };
    let counting = true;
    const detailed = options.detailed !== false;
    // Timing runs pass log: false so the trace does not grow without bound.
    const writeLog = options.log === false ? { push() {}, get length() { return 0; }, slice() { return []; } } : [];
    Signal.onEmit = () => { if (counting) stats.emits++; };

    function bump(kind, key) {
        if (!counting) return;
        stats[kind]++;
        if (detailed) stats.byKey[key] = (stats.byKey[key] || 0) + 1;
    }

    // ---------------------------------------------------------------- outputs
    class Output {
        constructor(id, geometry) { this._id = id; this._name = "OUT-" + id; this._geom = geometry; }
        get name() { bump("reads", "Output.name"); return this._name; }
    }

    // ---------------------------------------------------------------- tiles
    let tileSeq = 0;
    class Tile {
        constructor(parent) {
            this._id = "t" + (tileSeq++);
            this._parent = parent;
            this._children = [];
            this._geom = rect(0, 0, 0, 0);
            this._windows = [];
        }
        get tiles() { bump("reads", "Tile.tiles"); return this._children.slice(); }
        get absoluteGeometry() { bump("reads", "Tile.absoluteGeometry"); return copyRect(this._geom); }
        get windows() { bump("reads", "Tile.windows"); return this._windows.slice(); }
        get parent() { bump("reads", "Tile.parent"); return this._parent; }
    }

    // ---------------------------------------------------------------- windows
    let windowSeq = 0;
    class Window {
        constructor(props) {
            this._id = "w" + (windowSeq++);
            this._output = props.output;
            this._desktops = props.desktops || [];
            this._normal = props.normalWindow !== false;
            this._dialog = !!props.dialog;
            this._transient = !!props.transient;
            this._minimized = !!props.minimized;
            this._fullScreen = false;
            this._move = false;
            this._resize = false;
            this._moveable = props.moveable !== false;
            this._resizeable = props.resizeable !== false;
            this._class = props.resourceClass || "app";
            this._tile = null;
            this._geom = copyRect(props.geometry || rect(880, 420, 800, 600));
            this._mt = undefined;
            this._sig = {
                tileChanged: new Signal(),
                desktopsChanged: new Signal(),
                fullScreenChanged: new Signal(),
                frameGeometryChanged: new Signal(),
                interactiveMoveResizeStarted: new Signal(),
                interactiveMoveResizeFinished: new Signal(),
                closed: new Signal(),
            };
        }
        get output() { bump("reads", "Window.output"); return this._output; }
        get desktops() { bump("reads", "Window.desktops"); return this._desktops.slice(); }
        get onAllDesktops() { bump("reads", "Window.onAllDesktops"); return this._desktops.length === 0; }
        get normalWindow() { bump("reads", "Window.normalWindow"); return this._normal; }
        get dialog() { bump("reads", "Window.dialog"); return this._dialog; }
        get transient() { bump("reads", "Window.transient"); return this._transient; }
        get minimized() { bump("reads", "Window.minimized"); return this._minimized; }
        get fullScreen() { bump("reads", "Window.fullScreen"); return this._fullScreen; }
        get move() { bump("reads", "Window.move"); return this._move; }
        get resize() { bump("reads", "Window.resize"); return this._resize; }
        get moveable() { bump("reads", "Window.moveable"); return this._moveable; }
        get resizeable() { bump("reads", "Window.resizeable"); return this._resizeable; }
        get resourceClass() { bump("reads", "Window.resourceClass"); return this._class; }
        get frameGeometry() { bump("reads", "Window.frameGeometry"); return copyRect(this._geom); }
        set frameGeometry(r) {
            bump("writes", "Window.frameGeometry=");
            writeLog.push("G " + this._id + " " + [r.x, r.y, r.width, r.height].join(","));
            this.kwinSetGeometry(r);
        }
        get tile() { bump("reads", "Window.tile"); return this._tile; }
        set tile(t) {
            bump("writes", "Window.tile=");
            writeLog.push("T " + this._id + " " + (t ? t._id : "null"));
            this.kwinSetTile(t);
        }
        get mt() { bump("expando", "mt"); return this._mt; }
        set mt(v) { bump("expando", "mt="); this._mt = v; }

        get tileChanged() { bump("reads", "Window.<signal>"); return this._sig.tileChanged; }
        get desktopsChanged() { bump("reads", "Window.<signal>"); return this._sig.desktopsChanged; }
        get fullScreenChanged() { bump("reads", "Window.<signal>"); return this._sig.fullScreenChanged; }
        get frameGeometryChanged() { bump("reads", "Window.<signal>"); return this._sig.frameGeometryChanged; }
        get interactiveMoveResizeStarted() { bump("reads", "Window.<signal>"); return this._sig.interactiveMoveResizeStarted; }
        get interactiveMoveResizeFinished() { bump("reads", "Window.<signal>"); return this._sig.interactiveMoveResizeFinished; }
        get closed() { bump("reads", "Window.<signal>"); return this._sig.closed; }

        // ---- KWin-side (uncounted) behaviour
        kwinSetGeometry(r) {
            if (sameRect(this._geom, r)) return;
            this._geom = copyRect(r);
            this._sig.frameGeometryChanged.emit();
        }
        kwinSetTile(t) {
            if (this._tile === t) return;
            if (this._tile) {
                const list = this._tile._windows;
                list.splice(list.indexOf(this), 1);
            }
            this._tile = t;
            if (t) {
                t._windows.push(this);
                if (!this._fullScreen) {
                    const g = t._geom;
                    this.kwinSetGeometry(rect(g.x + TILE_PADDING, g.y + TILE_PADDING,
                        g.width - 2 * TILE_PADDING, g.height - 2 * TILE_PADDING));
                }
            }
            this._sig.tileChanged.emit(t);
        }
    }

    // ---------------------------------------------------------------- workspace
    const desktops = [1, 2, 3, 4].map(i => ({ _id: "d" + i, toString() { return "d" + i; } }));
    const outputs = [new Output(0, rect(0, 0, 2560, 1400)), new Output(1, rect(2560, 0, 1920, 1040))];
    const roots = new Map(); // output id + desktop id -> root tile
    const windows = [];
    let active = null;
    let current = desktops[0];
    const shortcuts = new Map();
    const config = Object.assign({}, options.config || {});

    const workspace = {
        windowList() { bump("calls", "workspace.windowList()"); return windows.slice(); },
        get stackingOrder() { bump("reads", "workspace.stackingOrder"); return windows.slice(); },
        get activeWindow() { bump("reads", "workspace.activeWindow"); return active; },
        set activeWindow(w) {
            bump("writes", "workspace.activeWindow=");
            writeLog.push("A " + (w ? w._id : "null"));
            active = w;
        },
        get currentDesktop() { bump("reads", "workspace.currentDesktop"); return current; },
        windowAdded: new Signal(),
    };
    // Plasma 6.4+: workspace.rootTile(output, desktop). Older: per-screen tiling
    // via tilingForScreen(output) or tilingForScreen(name); no rootTile().
    const tilingApi = options.tilingApi || "rootTile";
    const tilingFor = root => (root ? { get rootTile() { bump("reads", "Tiling.rootTile"); return root; } } : null);
    if (tilingApi === "rootTile") {
        workspace.rootTile = (output, desktop) => {
            bump("calls", "workspace.rootTile()");
            return roots.get(output._id + ":" + desktop._id) || null;
        };
    }
    workspace.tilingForScreen = arg => {
        bump("calls", "workspace.tilingForScreen()");
        if (tilingApi === "rootTile") throw new Error("n/a");
        const out = tilingApi === "output"
            ? outputs.find(o => o === arg)
            : outputs.find(o => o._name === arg);
        return out ? tilingFor(roots.get(out._id + ":" + desktops[0]._id)) : null;
    };

    const sandbox = {
        workspace,
        print: msg => { writeLog.push("P " + msg); },
        readConfig: (key, def) => {
            bump("calls", "readConfig()");
            return Object.prototype.hasOwnProperty.call(config, key) ? config[key] : def;
        },
        registerShortcut: (name, text, keys, cb) => { shortcuts.set(name, cb); },
    };

    // ---------------------------------------------------------------- layouts
    // spec: { dir: "h"|"v", parts: [weight | spec, ...] }
    function buildLayout(root, spec) {
        root._spec = spec;
        root._children = [];
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
        layoutGeometry(root);
    }
    function layoutGeometry(tile) {
        if (!tile._children.length) return;
        const g = tile._geom;
        const total = tile._weights.reduce((a, b) => a + b, 0);
        let offset = 0;
        tile._children.forEach((child, i) => {
            const share = tile._weights[i] / total;
            if (tile._dir === "h") {
                const w = Math.round(g.width * share);
                child._geom = rect(g.x + offset, g.y, i === tile._children.length - 1 ? g.width - offset : w, g.height);
                offset += w;
            } else {
                const h = Math.round(g.height * share);
                child._geom = rect(g.x, g.y + offset, g.width, i === tile._children.length - 1 ? g.height - offset : h);
                offset += h;
            }
            layoutGeometry(child);
        });
    }
    function leavesOf(tile) {
        if (!tile._children.length) return [tile];
        return tile._children.flatMap(leavesOf);
    }
    // KWin re-applies tile geometry to every window in a tile after a layout change.
    function relayout(root) {
        layoutGeometry(root);
        for (const leaf of leavesOf(root)) {
            const g = leaf._geom;
            for (const w of leaf._windows.slice()) {
                if (w._fullScreen) continue;
                w.kwinSetGeometry(rect(g.x + TILE_PADDING, g.y + TILE_PADDING,
                    g.width - 2 * TILE_PADDING, g.height - 2 * TILE_PADDING));
            }
        }
    }

    function setupRoots(specForOutput) {
        for (const out of outputs) {
            for (const d of desktops) {
                const root = new Tile(null);
                root._geom = copyRect(out._geom);
                const spec = specForOutput(out);
                if (spec) buildLayout(root, spec);
                roots.set(out._id + ":" + d._id, root);
            }
        }
    }

    // ---------------------------------------------------------------- driver API
    const env = {
        stats, writeLog, sandbox, workspace, desktops, outputs, roots, windows, shortcuts, config,
        Window, Tile, rect, leavesOf, relayout, layoutGeometry, setupRoots,
        setCounting(v) { counting = v; },
        rootFor(outputIndex, desktopIndex) { return roots.get(outputs[outputIndex]._id + ":" + desktops[desktopIndex]._id); },
        setActive(w) { active = w; },
        getActive() { return active; },
        setCurrentDesktop(i) { current = desktops[i]; },
        // The script body runs as a function in this realm with the KWin globals
        // as parameters (a vm context would route every global lookup, even
        // Math/Map, through slow interceptors and swamp the timings).
        load(script) {
            script(sandbox.workspace, sandbox.readConfig, sandbox.print, sandbox.registerShortcut);
        },
        addWindow(props) {
            const w = new Window(props);
            windows.push(w);
            workspace.windowAdded.emit(w);
            return w;
        },
        addExisting(props) { const w = new Window(props); windows.push(w); return w; },
        closeWindow(w) {
            w.kwinSetTile(null);
            windows.splice(windows.indexOf(w), 1);
            if (active === w) active = null;
            w._sig.closed.emit();
        },
        setDesktops(w, list) { w._desktops = list.slice(); w._sig.desktopsChanged.emit(); },
        setFullScreen(w, on, untile) {
            if (on) {
                if (untile) w.kwinSetTile(null);
                w._fullScreen = true;
                w._sig.fullScreenChanged.emit();
                w.kwinSetGeometry(copyRect(w._output._geom));
            } else {
                w._fullScreen = false;
                w._sig.fullScreenChanged.emit();
                const t = w._tile;
                if (t) {
                    const g = t._geom;
                    w.kwinSetGeometry(rect(g.x + TILE_PADDING, g.y + TILE_PADDING,
                        g.width - 2 * TILE_PADDING, g.height - 2 * TILE_PADDING));
                } else {
                    w.kwinSetGeometry(rect(700, 300, 900, 700));
                }
            }
        },
        setMinimized(w, on) { w._minimized = on; },
        startMove(w, untile = true) {
            w._move = true;
            w._sig.interactiveMoveResizeStarted.emit();
            if (untile) w.kwinSetTile(null);
        },
        moveTo(w, r) { w.kwinSetGeometry(r); },
        finishMove(w, snapTile = null) {
            w._move = false;
            if (snapTile) w.kwinSetTile(snapTile);
            w._sig.interactiveMoveResizeFinished.emit();
        },
        shortcut(name) { shortcuts.get(name)(); },
        tileGeomForWindow(t) {
            const g = t._geom;
            return rect(g.x + TILE_PADDING, g.y + TILE_PADDING, g.width - 2 * TILE_PADDING, g.height - 2 * TILE_PADDING);
        },
        // Canonical end-of-step state for correctness comparison (uncounted).
        dumpState() {
            return windows.map(w => {
                const s = w._mt;
                return w._id + ":" + (w._tile ? w._tile._id : "-") + ":" +
                    [w._geom.x, w._geom.y, w._geom.width, w._geom.height].join(",") + ":" +
                    (s ? (s.tile ? s.tile._id : "-") + "/" + s.key + "/" + s.userUntiled : "untracked");
            }).join(" ") + " active=" + (active ? active._id : "-");
        },
    };
    return env;
}

const LAYOUTS = {
    // 3 columns, outer ones split in two rows: 5 leaves, depth 2.
    L5: { dir: "h", parts: [{ dir: "v", parts: [1, 1] }, { weight: 1.2 }, { dir: "v", parts: [1, 1] }] },
    // 4 columns x 2 rows: 8 leaves.
    L8: { dir: "h", parts: [1, 2, 3, 4].map(() => ({ dir: "v", parts: [1, 1] })) },
    // 3 plain columns.
    L3: { dir: "h", parts: [1, 1.4, 1] },
    // Rows first, then columns: traversal order differs from x/y order.
    R4: { dir: "v", parts: [{ dir: "h", parts: [1, 1] }, { dir: "h", parts: [1, 2] }] },
    // Two hair-thin columns that both match a window within the 16px tolerance
    // (first-match order matters), nested under a row split.
    THIN: { dir: "v", parts: [{ dir: "h", parts: [1, 0.004, 0.004, { dir: "v", parts: [1, 0.01, 0.01] }] }, { weight: 0.5 }] },
};

function loadScript(file) {
    const src = fs.readFileSync(file, "utf8");
    new vm.Script(src, { filename: file }); // syntax check as a classic script
    // eslint-disable-next-line no-new-func
    return new Function("workspace", "readConfig", "print", "registerShortcut", src + "\n//# sourceURL=" + file);
}

module.exports = { createEnv, LAYOUTS, loadScript, rect };
