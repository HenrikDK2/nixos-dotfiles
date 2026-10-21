"use strict";

// FillOrder values (must match the dropdown in config.ui)
const ORDER_LEFT_TO_RIGHT = 0;
const ORDER_RIGHT_TO_LEFT = 1;
const ORDER_CENTER_RIGHT_FIRST = 2;
const ORDER_CENTER_LEFT_FIRST = 3;
const ORDER_CUSTOM = 4;

// Geometry tolerance (px) when matching a restored window to its tile rectangle
const GEOM_TOLERANCE_PX = 16;

// ---------------------------------------------------------------------------
// Settings (parsed once, re-parsed only when a value changes)
// ---------------------------------------------------------------------------
let cachedRaw = null;
let cachedCfg = null;
const orderCache = new Map();

function readSettings() {
    const fillOrder = readConfig("FillOrder", ORDER_CENTER_RIGHT_FIRST);
    const customOrder = readConfig("CustomOrder", "");
    const ignored = readConfig("IgnoredClasses", "");
    const stackExtra = readConfig("StackExtra", false);
    const debug = readConfig("Debug", false);

    const raw = [fillOrder, customOrder, ignored, stackExtra, debug].join("\u0001");
    if (raw === cachedRaw) return cachedCfg;

    cachedRaw = raw;
    orderCache.clear();
    cachedCfg = {
        fillOrder: parseInt(fillOrder, 10),
        customOrder: String(customOrder),
        ignored: new Set(String(ignored).split(",").map(s => s.trim().toLowerCase()).filter(Boolean)),
        stackExtra: stackExtra === true,
        debug: debug === true,
    };
    return cachedCfg;
}

// ---------------------------------------------------------------------------
// Fill order for any number of tiles n (0-based indices, left to right)
// ---------------------------------------------------------------------------
function buildOrder(cfg, n) {
    if (orderCache.has(n)) return orderCache.get(n);

    const indices = Array.from({ length: n }, (_, i) => i);
    let result;

    switch (cfg.fillOrder) {
    case ORDER_RIGHT_TO_LEFT:
        result = indices.reverse();
        break;

    case ORDER_CENTER_RIGHT_FIRST:
    case ORDER_CENTER_LEFT_FIRST: {
        const center = (n - 1) / 2;
        const rightFirst = cfg.fillOrder === ORDER_CENTER_RIGHT_FIRST;
        result = indices.sort((a, b) => {
            const da = Math.abs(a - center), db = Math.abs(b - center);
            if (da !== db) return da - db;
            return rightFirst ? b - a : a - b;
        });
        break;
    }

    case ORDER_CUSTOM: {
        const seen = new Set();
        const out = [];
        for (const part of cfg.customOrder.split(/[\s,;]+/)) {
            const v = parseInt(part, 10) - 1; // 1-based in the UI
            if (v >= 0 && v < n && !seen.has(v)) {
                seen.add(v);
                out.push(v);
            }
        }
        for (let i = 0; i < n; i++) {
            if (!seen.has(i)) out.push(i);
        }
        result = out;
        break;
    }

    default:
        result = indices;
        break;
    }

    orderCache.set(n, result);
    return result;
}

// ---------------------------------------------------------------------------
// Tiles & Desktops (Supports Plasma 6.0 - 6.3 tilingForScreen & 6.4+ rootTile)
// ---------------------------------------------------------------------------
let tilingMode = null; // "rootTile" | "output" | "name"

function rootTileFor(window) {
    if (!window || !window.output) return null;

    if (tilingMode === "rootTile") {
        const desktop = (window.desktops && window.desktops.length > 0)
            ? window.desktops[0]
            : workspace.currentDesktop;
        return workspace.rootTile(window.output, desktop);
    }
    if (tilingMode === "output") {
        const m = workspace.tilingForScreen(window.output);
        return m ? m.rootTile : null;
    }
    if (tilingMode === "name") {
        const m = workspace.tilingForScreen(window.output.name);
        return m ? m.rootTile : null;
    }

    // Probe Plasma 6.4+ workspace.rootTile(output, desktop) first
    try {
        if (typeof workspace.rootTile === "function") {
            const desktop = (window.desktops && window.desktops.length > 0)
                ? window.desktops[0]
                : workspace.currentDesktop;
            const r = workspace.rootTile(window.output, desktop);
            if (r) {
                tilingMode = "rootTile";
                return r;
            }
        }
    } catch (e) {}

    // Probe workspace.tilingForScreen(output)
    try {
        const m = workspace.tilingForScreen(window.output);
        if (m && m.rootTile) {
            tilingMode = "output";
            return m.rootTile;
        }
    } catch (e) {}

    // Probe workspace.tilingForScreen(output.name)
    try {
        const m = workspace.tilingForScreen(window.output.name);
        if (m && m.rootTile) {
            tilingMode = "name";
            return m.rootTile;
        }
    } catch (e) {}

    return null;
}

function collectLeaves(tile, out) {
    const children = tile.tiles;
    if (children.length === 0) {
        out.push(tile);
    } else {
        for (let i = 0; i < children.length; i++) collectLeaves(children[i], out);
    }
    return out;
}

// Leaf tiles sorted left to right (then top to bottom).
function sortedLeaves(root) {
    return collectLeaves(root, [])
        .map(tile => {
            const g = tile.absoluteGeometry;
            return { tile: tile, x: Math.round(g.x), y: Math.round(g.y) };
        })
        .sort((a, b) => (a.x - b.x) || (a.y - b.y))
        .map(entry => entry.tile);
}

function rectKey(g) {
    return Math.round(g.x) + "," + Math.round(g.y) + "," + Math.round(g.width) + "," + Math.round(g.height);
}

function tileKey(tile) {
    return rectKey(tile.absoluteGeometry);
}

// Check if a window's frameGeometry sits inside/matches a tile's absoluteGeometry
function matchesTileGeometry(window, tile) {
    const wg = window.frameGeometry;
    const tg = tile.absoluteGeometry;
    if (!wg || !tg) return false;
    return Math.abs(wg.x - tg.x) <= GEOM_TOLERANCE_PX &&
           Math.abs(wg.y - tg.y) <= GEOM_TOLERANCE_PX &&
           Math.abs(wg.width - tg.width) <= GEOM_TOLERANCE_PX &&
           Math.abs(wg.height - tg.height) <= GEOM_TOLERANCE_PX;
}

// Find which leaf tile a window is currently sitting in by its geometry
function findLeafMatchingGeometry(window) {
    const root = rootTileFor(window);
    if (!root || root.tiles.length === 0) return null;
    const leaves = collectLeaves(root, []);
    for (let i = 0; i < leaves.length; i++) {
        if (matchesTileGeometry(window, leaves[i])) return leaves[i];
    }
    return null;
}

function findTileByState(window, state) {
    const root = rootTileFor(window);
    if (!root) return null;

    const leaves = collectLeaves(root, []);
    if (state.tile && leaves.indexOf(state.tile) !== -1) {
        return state.tile;
    }
    if (state.key) {
        for (let i = 0; i < leaves.length; i++) {
            if (tileKey(leaves[i]) === state.key) return leaves[i];
        }
    }
    return findLeafMatchingGeometry(window);
}

function sharesContext(a, b) {
    if (a.output !== b.output) return false;
    if (a.onAllDesktops || b.onAllDesktops) return true;
    if (a.desktops && b.desktops && a.desktops.length > 0 && b.desktops.length > 0) {
        for (let i = 0; i < a.desktops.length; i++) {
            if (b.desktops.indexOf(a.desktops[i]) !== -1) return true;
        }
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Fullscreen & Geometry Tracking
// ---------------------------------------------------------------------------
const trackedWindows = new Set();

function tryRestoreTile(window) {
    const state = window.mt;
    if (!state || window.fullScreen || window.minimized) return;
    if (window.move || window.resize) return;
    if (window.tile) return;

    const target = findTileByState(window, state);
    if (target) {
        window.tile = target;
        state.tile = target;
        state.key = tileKey(target);
    }
}

function track(window) {
    if (trackedWindows.has(window) && window.mt) return;
    trackedWindows.add(window);

    const state = {
        tile: null,
        key: null,
        userUntiled: false,
    };
    window.mt = state;

    const remember = () => {
        const tile = window.tile;
        if (tile) {
            state.tile = tile;
            state.key = tileKey(tile);
            state.userUntiled = false;
        } else if (!window.fullScreen && !state.userUntiled) {
            const geomLeaf = findLeafMatchingGeometry(window);
            if (geomLeaf) {
                state.tile = geomLeaf;
                state.key = tileKey(geomLeaf);
            }
        }
    };
    remember();

    window.tileChanged.connect(remember);

    window.fullScreenChanged.connect(() => {
        const cfg = readSettings();
        if (window.fullScreen) {
            state.userUntiled = false;
            if (window.tile) {
                state.tile = window.tile;
                state.key = tileKey(window.tile);
            } else if (!state.tile && !state.key) {
                const geomLeaf = findLeafMatchingGeometry(window);
                if (geomLeaf) {
                    state.tile = geomLeaf;
                    state.key = tileKey(geomLeaf);
                }
            }
            if (cfg.debug) {
                print("mastertile: " + window.resourceClass + " entered fullscreen (reserved key: " + state.key + ")");
            }
        } else {
            tryRestoreTile(window);
            if (cfg.debug) {
                print("mastertile: " + window.resourceClass + " exited fullscreen (tile: " +
                      (window.tile ? "rebound" : "reserved via key " + state.key) + ")");
            }
        }
    });

    window.frameGeometryChanged.connect(() => {
        if (window.fullScreen || window.minimized) return;
        if (window.move || window.resize) return;

        if (!window.tile && !state.userUntiled) {
            const target = findTileByState(window, state);
            if (target && matchesTileGeometry(window, target)) {
                window.tile = target;
                state.tile = target;
                state.key = tileKey(target);
            }
        }
    });

    try {
        window.interactiveMoveResizeStarted.connect(() => {
            if (!window.fullScreen) {
                state.userUntiled = true;
                state.tile = null;
                state.key = null;
            }
        });
        window.interactiveMoveResizeFinished.connect(() => {
            if (!window.fullScreen) {
                if (window.tile) {
                    state.userUntiled = false;
                    state.tile = window.tile;
                    state.key = tileKey(window.tile);
                } else {
                    const geomLeaf = findLeafMatchingGeometry(window);
                    if (geomLeaf) {
                        state.userUntiled = false;
                        state.tile = geomLeaf;
                        state.key = tileKey(geomLeaf);
                    }
                }
            }
        });
    } catch (e) {}

    try {
        window.closed.connect(() => {
            trackedWindows.delete(window);
        });
    } catch (e) {}
}

// ---------------------------------------------------------------------------
// Bulletproof Occupancy Calculation
// ---------------------------------------------------------------------------
function computeOccupancies(leaves, selfWindow) {
    const keyMap = new Map();
    const occMap = new Map();

    for (let i = 0; i < leaves.length; i++) {
        const leaf = leaves[i];
        keyMap.set(leaf, tileKey(leaf));
        occMap.set(leaf, new Set());
    }

    // 1. Add windows KWin explicitly reports inside `leaf.windows`
    for (let i = 0; i < leaves.length; i++) {
        const leaf = leaves[i];
        const set = occMap.get(leaf);
        const tileWins = leaf.windows;
        for (let j = 0; j < tileWins.length; j++) {
            const tw = tileWins[j];
            if (tw !== selfWindow && !tw.minimized && sharesContext(selfWindow, tw)) {
                set.add(tw);
            }
        }
    }

    // 2. Scan all workspace windows to catch fullscreen windows AND windows that
    //    exited fullscreen with the tile's geometry while `w.tile` remained null.
    const all = workspace.windowList();
    for (let i = 0; i < all.length; i++) {
        const w = all[i];
        if (w === selfWindow || !w.normalWindow || w.minimized) continue;
        if (w.dialog || w.transient) continue;
        if (!sharesContext(selfWindow, w)) continue;

        track(w);

        if (!w.fullScreen && !w.tile && w.mt && !w.mt.userUntiled) {
            tryRestoreTile(w);
        }

        for (let j = 0; j < leaves.length; j++) {
            const leaf = leaves[j];
            const set = occMap.get(leaf);
            if (set.has(w)) continue;

            const lKey = keyMap.get(leaf);
            const hasReservation = w.mt && !w.mt.userUntiled && (w.mt.tile === leaf || w.mt.key === lKey);

            if (w.tile === leaf) {
                set.add(w);
            } else if (w.fullScreen && hasReservation) {
                set.add(w);
            } else if (!w.fullScreen && matchesTileGeometry(w, leaf)) {
                set.add(w);
            } else if (!w.fullScreen && hasReservation && !w.tile) {
                set.add(w);
            }
        }
    }

    return occMap;
}

// ---------------------------------------------------------------------------
// Placement
// ---------------------------------------------------------------------------
function placeWindow(window) {
    if (!window.normalWindow) return;
    track(window);

    if (window.tile || window.fullScreen) return;
    if (window.dialog || window.transient) return;
    if (!window.moveable || !window.resizeable) return;

    const cfg = readSettings();
    if (cfg.ignored.has(String(window.resourceClass).toLowerCase())) return;

    const root = rootTileFor(window);
    if (!root || root.tiles.length === 0) return; // no custom layout on this screen

    const leaves = sortedLeaves(root);
    const order = buildOrder(cfg, leaves.length);
    const occMap = computeOccupancies(leaves, window);

    // First free tile in the chosen order.
    let target = null;
    for (let i = 0; i < order.length; i++) {
        const leaf = leaves[order[i]];
        if (occMap.get(leaf).size === 0) {
            target = leaf;
            break;
        }
    }

    // All full: optionally use the least-filled tile (earliest in order on ties).
    if (!target && cfg.stackExtra && order.length > 0) {
        let best = Infinity;
        for (let i = 0; i < order.length; i++) {
            const leaf = leaves[order[i]];
            const n = occMap.get(leaf).size;
            if (n < best) {
                best = n;
                target = leaf;
            }
        }
    }

    if (cfg.debug) {
        const counts = leaves.map((l, idx) => "T" + (idx + 1) + ":" + occMap.get(l).size).join(" ");
        print("mastertile: " + window.resourceClass + " -> " +
              (target ? "tile " + (leaves.indexOf(target) + 1) + " of " + leaves.length : "floating") +
              " [" + counts + "]");
    }

    if (target) {
        window.tile = target;
        if (window.mt) {
            window.mt.tile = target;
            window.mt.key = tileKey(target);
            window.mt.userUntiled = false;
        }
    }
}

workspace.windowList().forEach(w => { if (w.normalWindow) track(w); });
workspace.windowAdded.connect(placeWindow);
