// Minimal mock of the KWin 6 scripting API used by the mastertile script.
//
// Engine-agnostic (runs under node and QuickJS `qjs`). Every access that in
// real KWin crosses the JS <-> C++ bridge is counted in world.stats:
//   read   : Q_PROPERTY read on a KWin QObject (window/tile/workspace/output)
//   write  : Q_PROPERTY write (window.tile = ..., workspace.activeWindow = ...)
//   call   : invokable / global call (windowList, rootTile, readConfig, connect ...)
//   value  : member read on a returned QRectF value (geometry.x/.y/.width/.height)
//   dyn    : read of the script's own expando property `window.mt` (in QV4 this
//            first misses the QObject property cache, then hits the JS object)
// Arrays (tiles, windows, desktops, windowList()) are fresh copies on every read,
// like QList -> JS conversions. QObject wrappers keep their identity.
//
// Side effects visible to the script are recorded in world.trace so that two
// versions of the script can be compared on identical inputs.
(function (root) {
"use strict";

function makeStats() {
    return { read: 0, write: 0, call: 0, value: 0, dyn: 0, detail: null };
}

function hit(S, kind, name) {
    S[kind]++;
    if (S.detail) {
        const k = kind + ":" + name;
        S.detail[k] = (S.detail[k] || 0) + 1;
    }
}

class Rect {
    constructor(S, x, y, w, h) { this._S = S; this._x = x; this._y = y; this._w = w; this._h = h; }
    get x() { hit(this._S, "value", "x"); return this._x; }
    get y() { hit(this._S, "value", "y"); return this._y; }
    get width() { hit(this._S, "value", "width"); return this._w; }
    get height() { hit(this._S, "value", "height"); return this._h; }
}

class Signal {
    constructor(S, name) { this._S = S; this._name = name; this._slots = []; }
    connect(fn) { hit(this._S, "call", "connect"); this._slots.push(fn); }
    disconnect(fn) {
        hit(this._S, "call", "disconnect");
        const i = this._slots.indexOf(fn);
        if (i >= 0) this._slots.splice(i, 1);
    }
    emit(...args) {
        // Copy so slots connected during emission are not run (Qt semantics).
        const slots = this._slots.slice();
        for (let i = 0; i < slots.length; i++) slots[i](...args);
    }
}

class Tile {
    constructor(world, rect, children) {
        this._w = world;
        this.id = "t" + (world._tileSeq++);
        this._rect = rect;           // [x, y, w, h]
        this._children = children || [];
        this._windows = [];
    }
    get tiles() { hit(this._w.stats, "read", "tile.tiles"); return this._children.slice(); }
    get windows() { hit(this._w.stats, "read", "tile.windows"); return this._windows.slice(); }
    get absoluteGeometry() {
        hit(this._w.stats, "read", "tile.absoluteGeometry");
        const r = this._rect;
        return new Rect(this._w.stats, r[0], r[1], r[2], r[3]);
    }
}

class Output {
    constructor(world, name, rect) { this._w = world; this._name = name; this._rect = rect; }
    get name() { hit(this._w.stats, "read", "output.name"); return this._name; }
}

class Desktop {
    constructor(world, id) { this._w = world; this.id = id; }
}

const SIGNALS = [
    "tileChanged", "desktopsChanged", "fullScreenChanged", "frameGeometryChanged",
    "interactiveMoveResizeStarted", "interactiveMoveResizeFinished", "closed",
];

class Window {
    constructor(world, opts) {
        this._w = world;
        this.id = opts.id;
        this._p = {
            resourceClass: opts.resourceClass || "app" + opts.id,
            normalWindow: opts.normalWindow !== undefined ? opts.normalWindow : true,
            dialog: !!opts.dialog,
            transient: !!opts.transient,
            moveable: opts.moveable !== undefined ? opts.moveable : true,
            resizeable: opts.resizeable !== undefined ? opts.resizeable : true,
            fullScreen: !!opts.fullScreen,
            minimized: !!opts.minimized,
            move: false,
            resize: false,
            onAllDesktops: !!opts.onAllDesktops,
        };
        this._output = opts.output;
        this._desktops = opts.onAllDesktops ? [] : (opts.desktops || [world.desktops[0]]);
        this._geom = (opts.geometry || [100, 100, 800, 600]).slice();
        this._tile = null;
        this._mt = undefined;
        this._sig = {};
        for (const s of SIGNALS) this._sig[s] = new Signal(world.stats, s);
    }

    // --- script-visible properties -------------------------------------
    get mt() { hit(this._w.stats, "dyn", "mt"); return this._mt; }
    set mt(v) { hit(this._w.stats, "dyn", "mt="); this._mt = v; }

    get output() { hit(this._w.stats, "read", "win.output"); return this._output; }
    get desktops() { hit(this._w.stats, "read", "win.desktops"); return this._desktops.slice(); }
    get frameGeometry() {
        hit(this._w.stats, "read", "win.frameGeometry");
        const g = this._geom;
        return new Rect(this._w.stats, g[0], g[1], g[2], g[3]);
    }
    get tile() { hit(this._w.stats, "read", "win.tile"); return this._tile; }
    set tile(t) {
        hit(this._w.stats, "write", "win.tile");
        this._w.trace.push("tile " + this.id + " <- " + (t ? t.id : "null"));
        this._w.setTile(this, t);
    }

    // --- mock-side helpers (not counted) -------------------------------
    sig(name) { return this._sig[name]; }
}

for (const p of ["resourceClass", "normalWindow", "dialog", "transient", "moveable",
                 "resizeable", "fullScreen", "minimized", "move", "resize", "onAllDesktops"]) {
    Object.defineProperty(Window.prototype, p, {
        get() { hit(this._w.stats, "read", "win." + p); return this._p[p]; },
        configurable: true,
    });
}
for (const s of SIGNALS) {
    Object.defineProperty(Window.prototype, s, {
        get() { hit(this._w.stats, "read", "win." + s); return this._sig[s]; },
        configurable: true,
    });
}

// Layout specs: a node is [x, y, w, h] for a leaf or { r: [x,y,w,h], c: [...] }.
function buildTree(world, spec) {
    if (Array.isArray(spec)) return new Tile(world, spec, []);
    return new Tile(world, spec.r, spec.c.map(c => buildTree(world, c)));
}

class World {
    // opts: { api: "rootTile" | "tilingForScreen" | "name", outputs: [{name, rect, layout}],
    //         desktops: n, perDesktopLayouts: bool, config: {...}, padding: px }
    constructor(opts) {
        this.stats = makeStats();
        this.trace = [];
        this._tileSeq = 0;
        this.opts = opts;
        this.padding = opts.padding !== undefined ? opts.padding : 4;
        this.desktops = [];
        for (let i = 0; i < (opts.desktops || 2); i++) this.desktops.push(new Desktop(this, "d" + i));
        this._currentDesktop = this.desktops[0];
        this.outputs = [];
        this.roots = new Map(); // output -> Map(desktop -> root)
        for (const o of opts.outputs) {
            const out = new Output(this, o.name, o.rect);
            this.outputs.push(out);
            const perDesk = new Map();
            let shared = null;
            for (const d of this.desktops) {
                if (opts.perDesktopLayouts || !shared) {
                    const layout = (o.layoutFor && o.layoutFor(d.id)) || o.layout;
                    shared = buildTree(this, layout);
                }
                perDesk.set(d, shared);
            }
            this.roots.set(out, perDesk);
        }
        this.windows = [];
        this._active = null;
        this.config = Object.assign({}, opts.config || {});
        this.shortcuts = new Map();
        const world = this;
        const S = this.stats;

        const windowAdded = new Signal(S, "windowAdded");
        this.windowAddedSignal = windowAdded;
        const ws = {
            windowList() { hit(S, "call", "windowList"); return world.windows.slice(); },
            get windowAdded() { hit(S, "read", "ws.windowAdded"); return windowAdded; },
            get currentDesktop() { hit(S, "read", "ws.currentDesktop"); return world._currentDesktop; },
            get activeWindow() { hit(S, "read", "ws.activeWindow"); return world._active; },
            set activeWindow(w) {
                hit(S, "write", "ws.activeWindow");
                world.trace.push("activate " + (w ? w.id : "null"));
                world._active = w;
            },
        };
        const api = opts.api || "rootTile";
        if (api === "rootTile") {
            ws.rootTile = function (output, desktop) {
                hit(S, "call", "rootTile");
                const m = world.roots.get(output);
                return (m && m.get(desktop)) || null;
            };
        } else {
            ws.tilingForScreen = function (arg) {
                hit(S, "call", "tilingForScreen");
                let out = arg;
                if (api === "name") {
                    if (typeof arg !== "string") throw new TypeError("expected screen name");
                    out = world.outputs.find(o => o._name === arg);
                } else if (!(arg instanceof Output)) {
                    return null;
                }
                const m = world.roots.get(out);
                if (!m) return null;
                const rootTile = m.get(world.desktops[0]);
                return { get rootTile() { hit(S, "read", "tm.rootTile"); return rootTile; } };
            };
        }
        this.workspace = ws;
        this.globals = {
            workspace: ws,
            readConfig(key, def) {
                hit(S, "call", "readConfig");
                return Object.prototype.hasOwnProperty.call(world.config, key) ? world.config[key] : def;
            },
            print(msg) { hit(S, "call", "print"); world.trace.push("print " + msg); },
            registerShortcut(name, text, keys, fn) {
                hit(S, "call", "registerShortcut");
                world.shortcuts.set(name, fn);
            },
        };
    }

    load(src) {
        const f = new Function("workspace", "readConfig", "print", "registerShortcut", src);
        const g = this.globals;
        f(g.workspace, g.readConfig, g.print, g.registerShortcut);
    }

    rootFor(win, desktop) { return this.roots.get(win._output).get(desktop || win._desktops[0] || this._currentDesktop); }

    tileGeom(t) {
        const r = t._rect, p = this.padding;
        return [r[0] + p, r[1] + p, r[2] - 2 * p, r[3] - 2 * p];
    }

    // Window::setTile: leave old tile, join new one, move to its geometry, emit.
    setTile(win, t) {
        if (win._tile === t) return;
        if (win._tile) {
            const ws = win._tile._windows;
            ws.splice(ws.indexOf(win), 1);
        }
        win._tile = t;
        if (t) {
            t._windows.push(win);
            if (!win._p.fullScreen) this.setGeometry(win, this.tileGeom(t));
        }
        win._sig.tileChanged.emit(t);
    }

    setGeometry(win, g) {
        const o = win._geom;
        if (o[0] === g[0] && o[1] === g[1] && o[2] === g[2] && o[3] === g[3]) return;
        win._geom = g.slice();
        win._sig.frameGeometryChanged.emit();
    }

    // --- drivers (mock side, not counted as bridge activity) ---------------
    addWindow(opts) {
        const id = opts.id !== undefined ? opts.id : "w" + this.windows.length;
        const w = new Window(this, Object.assign({ output: this.outputs[0] }, opts, { id }));
        this.windows.push(w);
        this.windowAddedSignal.emit(w);
        return w;
    }

    preexisting(opts) {
        const id = opts.id !== undefined ? opts.id : "w" + this.windows.length;
        const w = new Window(this, Object.assign({ output: this.outputs[0] }, opts, { id }));
        this.windows.push(w);
        return w;
    }

    closeWindow(w) {
        if (w._tile) this.setTile(w, null);
        this.windows.splice(this.windows.indexOf(w), 1);
        if (this._active === w) this._active = null;
        w._sig.closed.emit();
    }

    setFullScreen(w, on) {
        if (w._p.fullScreen === on) return;
        w._p.fullScreen = on;
        if (on) {
            w._savedGeom = w._geom.slice();
            if (w._tile) this.setTile(w, null);   // fullscreen windows leave their tile
            const r = w._output._rect;
            this.setGeometry(w, r);
        } else {
            this.setGeometry(w, w._savedGeom || [120, 120, 800, 600]);
        }
        w._sig.fullScreenChanged.emit();
    }

    setMinimized(w, on) { w._p.minimized = on; }

    moveToDesktop(w, d) {
        w._desktops = [d];
        w._sig.desktopsChanged.emit();
    }

    // Interactive move: start, untile, `steps` geometry updates, finish at `drop`.
    interactiveMove(w, steps, drop) {
        w._p.move = true;
        w._sig.interactiveMoveResizeStarted.emit();
        if (w._tile) this.setTile(w, null);
        const g = w._geom.slice();
        for (let i = 0; i < steps; i++) {
            g[0] += 3; g[1] += (i & 1) ? 1 : -1;
            this.setGeometry(w, g);
        }
        w._p.move = false;
        if (drop) this.setGeometry(w, drop);
        w._sig.interactiveMoveResizeFinished.emit();
    }

    setActive(w) { this._active = w; }
    shortcut(name) { this.shortcuts.get(name)(); }
}

// Common layouts (output 1920x1080 at origin unless given).
const layouts = {
    cols(n, W = 1920, H = 1080, X = 0) {
        const c = [];
        for (let i = 0; i < n; i++) {
            const x0 = X + Math.round(i * W / n), x1 = X + Math.round((i + 1) * W / n);
            c.push([x0, 0, x1 - x0, H]);
        }
        return { r: [X, 0, W, H], c };
    },
    // root -> n columns -> each column split into m rows
    grid(n, m, W = 1920, H = 1080, X = 0) {
        const c = [];
        for (let i = 0; i < n; i++) {
            const x0 = X + Math.round(i * W / n), x1 = X + Math.round((i + 1) * W / n);
            const rows = [];
            for (let j = 0; j < m; j++) {
                const y0 = Math.round(j * H / m), y1 = Math.round((j + 1) * H / m);
                rows.push([x0, y0, x1 - x0, y1 - y0]);
            }
            c.push({ r: [x0, 0, x1 - x0, H], c: rows });
        }
        return { r: [X, 0, W, H], c };
    },
    // master column + stack of k rows on the right
    masterStack(k, W = 1920, H = 1080, X = 0) {
        const mw = Math.round(W * 0.6);
        const rows = [];
        for (let j = 0; j < k; j++) {
            const y0 = Math.round(j * H / k), y1 = Math.round((j + 1) * H / k);
            rows.push([X + mw, y0, W - mw, y1 - y0]);
        }
        return { r: [X, 0, W, H], c: [[X, 0, mw, H], { r: [X + mw, 0, W - mw, H], c: rows }] };
    },
    empty(W = 1920, H = 1080, X = 0) { return { r: [X, 0, W, H], c: [] }; },
};

root.KWinMock = { World, layouts, makeStats };
})(typeof module !== "undefined" && module.exports ? module.exports : globalThis);
