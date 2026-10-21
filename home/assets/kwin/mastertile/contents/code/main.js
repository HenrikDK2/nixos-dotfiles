"use strict";

// FillOrder values (must match the dropdown in config.ui)
const ORDER_LEFT_TO_RIGHT = 0;
const ORDER_RIGHT_TO_LEFT = 1;
const ORDER_CENTER_RIGHT_FIRST = 2;
const ORDER_CENTER_LEFT_FIRST = 3;
const ORDER_CUSTOM = 4;

const GEOM_TOLERANCE_PX = 16;

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------
let cachedRaw = null;
let cachedCfg = null;
const orderCache = new Map();

function readSettings() {
    const values = [
        readConfig("FillOrder", ORDER_CENTER_RIGHT_FIRST),
        readConfig("CustomOrder", ""),
        readConfig("IgnoredClasses", ""),
        readConfig("StackExtra", false),
        readConfig("Debug", false),
    ];
    const raw = values.join("\u0001");

    if (raw === cachedRaw) return cachedCfg;

    cachedRaw = raw;
    orderCache.clear();

    const [fillOrder, customOrder, ignored, stackExtra, debug] = values;
    cachedCfg = {
        fillOrder: parseInt(fillOrder, 10),
        customOrder: String(customOrder),
        ignored: new Set(
            String(ignored).split(",").map(s => s.trim().toLowerCase()).filter(Boolean)
        ),
        stackExtra: stackExtra === true,
        debug: debug === true,
    };

    return cachedCfg;
}

// ---------------------------------------------------------------------------
// Fill order
// ---------------------------------------------------------------------------
function buildOrder(cfg, n) {
    if (orderCache.has(n)) return orderCache.get(n);

    const indices = Array.from({ length: n }, (_, i) => i);
    let result = indices;

    switch (cfg.fillOrder) {
    case ORDER_RIGHT_TO_LEFT:
        result = indices.reverse();
        break;

    case ORDER_CENTER_RIGHT_FIRST:
    case ORDER_CENTER_LEFT_FIRST: {
        const center = (n - 1) / 2;
        const rightFirst = cfg.fillOrder === ORDER_CENTER_RIGHT_FIRST;

        result.sort((a, b) => {
            const distance = Math.abs(a - center) - Math.abs(b - center);
            return distance || (rightFirst ? b - a : a - b);
        });
        break;
    }

    case ORDER_CUSTOM: {
        const seen = new Set();
        result = [];

        for (const part of cfg.customOrder.split(/[\s,;]+/)) {
            const index = parseInt(part, 10) - 1;

            if (index >= 0 && index < n && !seen.has(index)) {
                seen.add(index);
                result.push(index);
            }
        }

        for (let i = 0; i < n; i++) {
            if (!seen.has(i)) result.push(i);
        }
        break;
    }
    }

    orderCache.set(n, result);
    return result;
}

// ---------------------------------------------------------------------------
// Tiles & desktops (Plasma 6.0–6.3 and 6.4+)
// ---------------------------------------------------------------------------
let tilingMode = null;

function rootTileFor(window) {
    if (!window || !window.output) return null;

    const desktop = window.desktops?.length
        ? window.desktops[0]
        : workspace.currentDesktop;

    if (tilingMode === "rootTile") {
        return workspace.rootTile(window.output, desktop);
    }

    if (tilingMode === "output" || tilingMode === "name") {
        const output = tilingMode === "name" ? window.output.name : window.output;
        const manager = workspace.tilingForScreen(output);
        return manager ? manager.rootTile : null;
    }

    try {
        if (typeof workspace.rootTile === "function") {
            const root = workspace.rootTile(window.output, desktop);
            if (root) {
                tilingMode = "rootTile";
                return root;
            }
        }
    } catch (e) {}

    for (const [mode, output] of [
        ["output", window.output],
        ["name", window.output.name],
    ]) {
        try {
            const manager = workspace.tilingForScreen(output);
            if (manager?.rootTile) {
                tilingMode = mode;
                return manager.rootTile;
            }
        } catch (e) {}
    }

    return null;
}

function collectLeaves(tile, result = []) {
    if (tile.tiles.length === 0) {
        result.push(tile);
    } else {
        for (const child of tile.tiles) collectLeaves(child, result);
    }
    return result;
}

function sortedLeaves(root) {
    return collectLeaves(root)
        .map(tile => {
            const { x, y } = tile.absoluteGeometry;
            return { tile, x: Math.round(x), y: Math.round(y) };
        })
        .sort((a, b) => a.x - b.x || a.y - b.y)
        .map(entry => entry.tile);
}

function rectKey(geometry) {
    const { x, y, width, height } = geometry;
    return [x, y, width, height].map(Math.round).join(",");
}

function tileKey(tile) {
    return rectKey(tile.absoluteGeometry);
}

function matchesTileGeometry(window, tile) {
    const windowGeometry = window.frameGeometry;
    const tileGeometry = tile.absoluteGeometry;
    if (!windowGeometry || !tileGeometry) return false;

    return ["x", "y", "width", "height"].every(
        key => Math.abs(windowGeometry[key] - tileGeometry[key]) <= GEOM_TOLERANCE_PX
    );
}

function findLeafMatchingGeometry(window) {
    const root = rootTileFor(window);
    if (!root || root.tiles.length === 0) return null;

    return collectLeaves(root).find(tile => matchesTileGeometry(window, tile)) || null;
}

function findTileByState(window, state) {
    const root = rootTileFor(window);
    if (!root) return null;

    const leaves = collectLeaves(root);

    if (state.tile && leaves.includes(state.tile)) return state.tile;

    if (state.key) {
        const match = leaves.find(tile => tileKey(tile) === state.key);
        if (match) return match;
    }

    return findLeafMatchingGeometry(window);
}

function sharesContext(a, b) {
    if (a.output !== b.output) return false;
    if (a.onAllDesktops || b.onAllDesktops) return true;

    if (a.desktops?.length && b.desktops?.length) {
        return a.desktops.some(desktop => b.desktops.includes(desktop));
    }

    return true;
}

// ---------------------------------------------------------------------------
// Window tracking & fullscreen restoration
// ---------------------------------------------------------------------------
const trackedWindows = new Set();

function rememberTileState(state, tile) {
    if (!tile) return;

    state.tile = tile;
    state.key = tileKey(tile);
    state.userUntiled = false;
}

function tryRestoreTile(window) {
    const state = window.mt;
    if (!state || window.fullScreen || window.minimized || window.move || window.resize || window.tile) {
        return;
    }

    const tile = findTileByState(window, state);
    if (tile) {
        window.tile = tile;
        rememberTileState(state, tile);
    }
}

function track(window) {
    if (trackedWindows.has(window) && window.mt) return;
    trackedWindows.add(window);

    const state = window.mt = {
        tile: null,
        key: null,
        userUntiled: false,
    };

    const remember = () => {
        if (window.tile) {
            rememberTileState(state, window.tile);
        } else if (!window.fullScreen && !state.userUntiled) {
            const tile = findLeafMatchingGeometry(window);
            if (tile) rememberTileState(state, tile);
        }
    };

    remember();
    window.tileChanged.connect(remember);

    window.fullScreenChanged.connect(() => {
        const cfg = readSettings();

        if (window.fullScreen) {
            state.userUntiled = false;

            if (window.tile) {
                rememberTileState(state, window.tile);
            } else if (!state.tile && !state.key) {
                const tile = findLeafMatchingGeometry(window);
                if (tile) rememberTileState(state, tile);
            }

            if (cfg.debug) {
                print("mastertile: " + window.resourceClass +
                      " entered fullscreen (reserved key: " + state.key + ")");
            }
            return;
        }

        tryRestoreTile(window);

        if (cfg.debug) {
            print("mastertile: " + window.resourceClass +
                  " exited fullscreen (tile: " +
                  (window.tile ? "rebound" : "reserved via key " + state.key) + ")");
        }
    });

    window.frameGeometryChanged.connect(() => {
        if (window.fullScreen || window.minimized || window.move || window.resize ||
            window.tile || state.userUntiled) {
            return;
        }

        const tile = findTileByState(window, state);
        if (tile && matchesTileGeometry(window, tile)) {
            window.tile = tile;
            rememberTileState(state, tile);
        }
    });

    try {
        window.interactiveMoveResizeStarted.connect(() => {
            if (window.fullScreen) return;
            state.userUntiled = true;
            state.tile = null;
            state.key = null;
        });

        window.interactiveMoveResizeFinished.connect(() => {
            if (window.fullScreen) return;

            if (window.tile) {
                rememberTileState(state, window.tile);
            } else {
                const tile = findLeafMatchingGeometry(window);
                if (tile) rememberTileState(state, tile);
            }
        });
    } catch (e) {}

    try {
        window.closed.connect(() => trackedWindows.delete(window));
    } catch (e) {}
}

// ---------------------------------------------------------------------------
// Occupancy
// ---------------------------------------------------------------------------
function computeOccupancies(leaves, selfWindow) {
    const occupancy = new Map(leaves.map(tile => [tile, new Set()]));
    const keys = new Map(leaves.map(tile => [tile, tileKey(tile)]));

    // Include windows KWin explicitly reports on each tile.
    for (const tile of leaves) {
        const occupants = occupancy.get(tile);

        for (const window of tile.windows) {
            if (window !== selfWindow && !window.minimized && sharesContext(selfWindow, window)) {
                occupants.add(window);
            }
        }
    }

    // Also account for fullscreen windows and restored windows lacking tile assignments.
    for (const window of workspace.windowList()) {
        if (window === selfWindow || !window.normalWindow || window.minimized ||
            window.dialog || window.transient || !sharesContext(selfWindow, window)) {
            continue;
        }

        track(window);

        if (!window.fullScreen && !window.tile && window.mt && !window.mt.userUntiled) {
            tryRestoreTile(window);
        }

        for (const tile of leaves) {
            const occupants = occupancy.get(tile);
            if (occupants.has(window)) continue;

            const reserved = window.mt && !window.mt.userUntiled &&
                (window.mt.tile === tile || window.mt.key === keys.get(tile));

            if (window.tile === tile ||
                (window.fullScreen && reserved) ||
                (!window.fullScreen && matchesTileGeometry(window, tile)) ||
                (!window.fullScreen && reserved && !window.tile)) {
                occupants.add(window);
            }
        }
    }

    return occupancy;
}

// ---------------------------------------------------------------------------
// Placement
// ---------------------------------------------------------------------------
function placeWindow(window) {
    if (!window.normalWindow) return;
    track(window);

    if (window.tile || window.fullScreen || window.dialog || window.transient ||
        !window.moveable || !window.resizeable) {
        return;
    }

    const cfg = readSettings();
    if (cfg.ignored.has(String(window.resourceClass).toLowerCase())) return;

    const root = rootTileFor(window);
    if (!root || root.tiles.length === 0) return;

    const leaves = sortedLeaves(root);
    const order = buildOrder(cfg, leaves.length);
    const occupancy = computeOccupancies(leaves, window);

    let target = null;
    let fewest = Infinity;

    for (const index of order) {
        const tile = leaves[index];
        const count = occupancy.get(tile).size;

        if (count === 0) {
            target = tile;
            break;
        }

        if (cfg.stackExtra && count < fewest) {
            fewest = count;
            target = tile;
        }
    }

    if (cfg.debug) {
        const counts = leaves.map(
            (tile, i) => "T" + (i + 1) + ":" + occupancy.get(tile).size
        ).join(" ");

        print("mastertile: " + window.resourceClass + " -> " +
              (target ? "tile " + (leaves.indexOf(target) + 1) + " of " + leaves.length : "floating") +
              " [" + counts + "]");
    }

    if (target) {
        window.tile = target;
        if (window.mt) rememberTileState(window.mt, target);
    }
}

// ---------------------------------------------------------------------------
// Directional focus & swapping
// ---------------------------------------------------------------------------
function directionalTile(leaves, source, direction) {
    const a = source.absoluteGeometry;
    const ax = a.x + a.width / 2;
    const ay = a.y + a.height / 2;
    const horizontal = direction === "left" || direction === "right";
    const sign = direction === "left" || direction === "up" ? -1 : 1;

    let best = null;
    let bestScore = Infinity;

    for (const tile of leaves) {
        if (tile === source) continue;

        const g = tile.absoluteGeometry;
        const dx = g.x + g.width / 2 - ax;
        const dy = g.y + g.height / 2 - ay;
        const primaryDelta = horizontal ? dx : dy;

        if (primaryDelta * sign <= 0) continue;

        const primary = Math.abs(primaryDelta);
        const secondary = Math.abs(horizontal ? dy : dx);
        const score = primary + secondary * 1.5;

        if (score < bestScore) {
            bestScore = score;
            best = tile;
        }
    }

    return best;
}

function windowForTile(tile, current) {
    if (!tile) return null;

    const eligible = window =>
        window !== current &&
        window.normalWindow &&
        !window.minimized &&
        !window.fullScreen &&
        !window.dialog &&
        !window.transient &&
        sharesContext(current, window);

    const assigned = tile.windows.find(eligible);
    if (assigned) return assigned;

    return workspace.windowList().find(window =>
        eligible(window) &&
        (window.tile === tile || (!window.tile && matchesTileGeometry(window, tile)))
    ) || null;
}

function activeTileContext() {
    const window = workspace.activeWindow;
    if (!window || !window.normalWindow || window.fullScreen) return null;

    const root = rootTileFor(window);
    if (!root) return null;

    const tile = window.tile || findLeafMatchingGeometry(window);
    if (!tile) return null;

    return { window, tile, leaves: sortedLeaves(root) };
}

function moveFocus(direction) {
    const context = activeTileContext();
    if (!context) return;

    const tile = directionalTile(context.leaves, context.tile, direction);
    const window = windowForTile(tile, context.window);

    if (window) workspace.activeWindow = window;
}

function swapWindow(direction) {
    const context = activeTileContext();
    if (!context) return;

    const targetTile = directionalTile(context.leaves, context.tile, direction);
    const targetWindow = windowForTile(targetTile, context.window);
    if (!targetTile || !targetWindow) return;

    context.window.tile = targetTile;
    targetWindow.tile = context.tile;

    rememberTileState(context.window.mt, targetTile);
    rememberTileState(targetWindow.mt, context.tile);

    workspace.activeWindow = context.window;
}

// Register directional focus and swap shortcuts.
for (const direction of ["left", "right", "up", "down"]) {
    const title = direction[0].toUpperCase() + direction.slice(1);

    registerShortcut(
        "mastertile-focus-" + direction,
        "MasterTile: Focus window " + direction,
        "Meta+" + title,
        () => moveFocus(direction)
    );

    registerShortcut(
        "mastertile-swap-" + direction,
        "MasterTile: Swap window " + direction,
        "Meta+Shift+" + title,
        () => swapWindow(direction)
    );
}

workspace.windowList().forEach(w => { if (w.normalWindow) track(w); });
workspace.windowAdded.connect(placeWindow);
