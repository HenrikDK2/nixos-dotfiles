"use strict";

// FillOrder values must match the dropdown in config.ui.
// 0 = left to right (the default when no other case matches).
const ORDER_RIGHT_TO_LEFT = 1;
const ORDER_CENTER_RIGHT_FIRST = 2;
const ORDER_CENTER_LEFT_FIRST = 3;
const ORDER_CUSTOM = 4;

const GEOM_TOLERANCE_PX = 16;

const log = message => print("mastertile: " + message);

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
    // Settings changes clear this cache, so tile count is sufficient as its key.
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
// Root-tile lookups, tried in order until one works; the winner is remembered.
const rootStrategies = {
    rootTile: (window, desktop) => workspace.rootTile(window.output, desktop),
    output: window => workspace.tilingForScreen(window.output)?.rootTile,
    name: window => workspace.tilingForScreen(window.output.name)?.rootTile,
};
let tilingMode = null;

function rootTileFor(window) {
    if (!window || !window.output) return null;

    const desktop = window.desktops?.length
        ? window.desktops[0]
        : workspace.currentDesktop;

    if (tilingMode) return rootStrategies[tilingMode](window, desktop) || null;

    for (const [mode, lookup] of Object.entries(rootStrategies)) {
        try {
            const root = lookup(window, desktop);
            if (root) {
                tilingMode = mode;
                return root;
            }
        } catch (e) {
            // Unsupported on this KWin version; try the next API.
        }
    }

    return null;
}

function collectLeaves(tile) {
    // Iterative depth-first traversal avoids recursion limits and preserves child order.
    const result = [];
    const stack = [tile];

    while (stack.length) {
        const current = stack.pop();
        const children = current.tiles;

        if (children.length === 0) {
            result.push(current);
            continue;
        }

        for (let i = children.length - 1; i >= 0; i--) {
            stack.push(children[i]);
        }
    }

    return result;
}

function rectKey(g) {
    return `${Math.round(g.x)},${Math.round(g.y)},${Math.round(g.width)},${Math.round(g.height)}`;
}

function createTileSnapshot(root, sortByGeometry) {
    const entries = collectLeaves(root).map((tile, traversalIndex) => {
        const geometry = tile.absoluteGeometry;

        return {
            tile,
            x: geometry.x,
            y: geometry.y,
            width: geometry.width,
            height: geometry.height,
            key: rectKey(geometry),
            traversalIndex,
        };
    });

    if (sortByGeometry) {
        entries.sort((a, b) =>
            Math.round(a.x) - Math.round(b.x) ||
            Math.round(a.y) - Math.round(b.y) ||
            a.traversalIndex - b.traversalIndex
        );
    }

    const byTile = new Map();
    for (const entry of entries) byTile.set(entry.tile, entry);

    return { root, entries, byTile };
}

function snapshotForRoot(root, snapshotCache) {
    if (snapshotCache?.has(root)) return snapshotCache.get(root);

    const snapshot = createTileSnapshot(root, false);
    if (snapshotCache) snapshotCache.set(root, snapshot);

    return snapshot;
}

function matchesGeometry(windowGeometry, tileGeometry) {
    if (!windowGeometry || !tileGeometry) return false;

    return Math.abs(windowGeometry.x - tileGeometry.x) <= GEOM_TOLERANCE_PX &&
        Math.abs(windowGeometry.y - tileGeometry.y) <= GEOM_TOLERANCE_PX &&
        Math.abs(windowGeometry.width - tileGeometry.width) <= GEOM_TOLERANCE_PX &&
        Math.abs(windowGeometry.height - tileGeometry.height) <= GEOM_TOLERANCE_PX;
}

function findLeafEntryMatchingGeometry(window, snapshot) {
    // A root with no children is not treated as a geometry-matched layout.
    if (!snapshot?.root || snapshot.root.tiles.length === 0) return null;

    const windowGeometry = window.frameGeometry;
    return snapshot.entries.find(entry => matchesGeometry(windowGeometry, entry)) || null;
}

function findLeafMatchingGeometry(window, snapshot) {
    if (!snapshot) {
        const root = rootTileFor(window);
        if (root) snapshot = createTileSnapshot(root, false);
    }

    const entry = findLeafEntryMatchingGeometry(window, snapshot);
    return entry ? entry.tile : null;
}

function findTileEntryByStateInSnapshot(window, state, snapshot) {
    if (!snapshot) return null;

    return snapshot.byTile.get(state.tile) ||
        (state.key && snapshot.entries.find(entry => entry.key === state.key)) ||
        findLeafEntryMatchingGeometry(window, snapshot);
}

function findTileByState(window, state, snapshotCache) {
    const root = rootTileFor(window);
    if (!root) return null;

    const snapshot = snapshotForRoot(root, snapshotCache);
    const entry = findTileEntryByStateInSnapshot(window, state, snapshot);

    return entry ? entry.tile : null;
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
    if (!state || !tile) return;

    state.tile = tile;
    state.key = rectKey(tile.absoluteGeometry);
    state.userUntiled = false;
}

function tryRestoreTile(window, snapshotCache) {
    const state = window.mt;

    if (!state || window.fullScreen || window.minimized ||
        window.move || window.resize || window.tile) {
        return;
    }

    const tile = findTileByState(window, state, snapshotCache);

    if (tile) {
        window.tile = tile;
        rememberTileState(state, tile);
    }
}

function rememberWindowTileState(window, state, snapshotCache) {
    if (window.tile) {
        rememberTileState(state, window.tile);
    } else if (!window.fullScreen && !state.userUntiled) {
        const root = snapshotCache && rootTileFor(window);
        const snapshot = root ? snapshotForRoot(root, snapshotCache) : null;
        const tile = findLeafMatchingGeometry(window, snapshot);
        if (tile) rememberTileState(state, tile);
    }
}

function track(window, snapshotCache) {
    if (trackedWindows.has(window) && window.mt) return;
    trackedWindows.add(window);

    const state = window.mt = {
        tile: null,
        key: null,
        userUntiled: false,
    };

    // Signal callbacks must resolve the current tree, not reuse an old snapshot.
    const remember = () => rememberWindowTileState(window, state, null);

    rememberWindowTileState(window, state, snapshotCache);
    window.tileChanged.connect(remember);

    try {
        window.desktopsChanged.connect(() => {
            if (window.onAllDesktops || state.userUntiled) return;
            placeWindow(window, true);
        });
    } catch (e) {
        // Keep compatibility with versions lacking this signal.
    }

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
                log(window.resourceClass +
                    " entered fullscreen (reserved key: " + state.key + ")");
            }
            return;
        }

        tryRestoreTile(window);

        if (cfg.debug) {
            log(window.resourceClass + " exited fullscreen (tile: " +
                (window.tile ? "rebound" : "reserved via key " + state.key) + ")");
        }
    });

    window.frameGeometryChanged.connect(() => {
        if (window.fullScreen || window.minimized || window.move || window.resize ||
            window.tile || state.userUntiled) {
            return;
        }

        const root = rootTileFor(window);
        if (!root) return;

        const snapshot = createTileSnapshot(root, false);
        const entry = findTileEntryByStateInSnapshot(window, state, snapshot);

        if (entry && matchesGeometry(window.frameGeometry, entry)) {
            window.tile = entry.tile;
            rememberTileState(state, entry.tile);
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
    } catch (e) {
        // Interactive move/resize signals vary across supported KWin versions.
    }

    try {
        window.closed.connect(() => trackedWindows.delete(window));
    } catch (e) {
        // Keep tracking functional when the optional closed signal is unavailable.
    }
}

// ---------------------------------------------------------------------------
// Occupancy
// ---------------------------------------------------------------------------
function computeOccupancies(snapshot, selfWindow, snapshotCache) {
    const { entries } = snapshot;
    const occupancy = new Map(entries.map(entry => [entry.tile, new Set()]));

    // Explicit tile occupants may not be discoverable by geometry matching.
    for (const entry of entries) {
        const occupants = occupancy.get(entry.tile);

        for (const window of entry.tile.windows) {
            if (window !== selfWindow && !window.minimized &&
                sharesContext(selfWindow, window)) {
                occupants.add(window);
            }
        }
    }

    const windows = workspace.windowList();

    for (const window of windows) {
        if (window === selfWindow || !window.normalWindow || window.minimized ||
            window.dialog || window.transient || !sharesContext(selfWindow, window)) {
            continue;
        }

        track(window, snapshotCache);

        if (!window.fullScreen && !window.tile && window.mt && !window.mt.userUntiled) {
            tryRestoreTile(window, snapshotCache);
        }

        const fullScreen = window.fullScreen;
        const assignedTile = window.tile;
        const state = window.mt;
        const hasReservation = Boolean(state && !state.userUntiled);
        const frameGeometry = fullScreen ? null : window.frameGeometry;

        for (const entry of entries) {
            const tile = entry.tile;
            const occupants = occupancy.get(tile);

            if (occupants.has(window)) continue;

            const reserved = hasReservation &&
                (state.tile === tile || state.key === entry.key);

            if (assignedTile === tile ||
                (fullScreen && reserved) ||
                (!fullScreen && matchesGeometry(frameGeometry, entry)) ||
                (!fullScreen && reserved && !assignedTile)) {
                occupants.add(window);
            }
        }
    }

    return occupancy;
}

// ---------------------------------------------------------------------------
// Placement
// ---------------------------------------------------------------------------
function placeWindow(window, desktopChanged = false) {
    if (!window.normalWindow) return;
    track(window);

    if (window.fullScreen || window.dialog || window.transient ||
        !window.moveable || !window.resizeable ||
        (window.tile && !desktopChanged)) {
        return;
    }

    const cfg = readSettings();
    if (cfg.ignored.has(String(window.resourceClass).toLowerCase())) return;

    const root = rootTileFor(window);
    if (!root || root.tiles.length === 0) return;

    const snapshot = createTileSnapshot(root, true);

    // Keep the current tile if it already belongs to the destination layout.
    if (desktopChanged && window.tile && snapshot.byTile.has(window.tile)) {
        return;
    }

    const { entries } = snapshot;
    const snapshotCache = new Map([[root, snapshot]]);
    const order = buildOrder(cfg, entries.length);
    const occupancy = computeOccupancies(snapshot, window, snapshotCache);

    let target = null;
    let fewest = Infinity;

    for (const index of order) {
        const tile = entries[index].tile;
        const count = occupancy.get(tile).size;

        if (count === 0) {
            target = tile;
            break;
        }

        // Strict comparison preserves fill-order tie breaks.
        if (cfg.stackExtra && count < fewest) {
            fewest = count;
            target = tile;
        }
    }

    if (cfg.debug) {
        const counts = entries.map(
            (entry, i) => "T" + (i + 1) + ":" + occupancy.get(entry.tile).size
        ).join(" ");

        const targetIndex = target
            ? entries.findIndex(entry => entry.tile === target) + 1
            : 0;

        log(window.resourceClass + " -> " +
            (target ? "tile " + targetIndex + " of " + entries.length : "floating") +
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
function directionalTile(snapshot, source, direction, accept) {
    const sourceGeometry = snapshot.byTile.get(source) || source.absoluteGeometry;
    const sourceX = sourceGeometry.x + sourceGeometry.width / 2;
    const sourceY = sourceGeometry.y + sourceGeometry.height / 2;
    const horizontal = direction === "left" || direction === "right";
    const sign = direction === "left" || direction === "up" ? -1 : 1;

    let best = null;
    let bestScore = Infinity;

    for (const entry of snapshot.entries) {
        if (entry.tile === source || (accept && !accept(entry.tile))) continue;

        const dx = entry.x + entry.width / 2 - sourceX;
        const dy = entry.y + entry.height / 2 - sourceY;
        const primaryDelta = horizontal ? dx : dy;

        if (primaryDelta * sign <= 0) continue;

        const primary = Math.abs(primaryDelta);
        const secondary = Math.abs(horizontal ? dy : dx);
        const score = primary + secondary * 1.5;

        if (score < bestScore) {
            bestScore = score;
            best = entry.tile;
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

    const tileGeometry = tile.absoluteGeometry;

    return workspace.windowList().find(window => {
        if (!eligible(window)) return false;
        if (window.tile === tile) return true;
        if (window.tile) return false;

        return matchesGeometry(window.frameGeometry, tileGeometry);
    }) || null;
}

function activeTileContext() {
    const window = workspace.activeWindow;
    if (!window || !window.normalWindow || window.fullScreen) return null;

    const root = rootTileFor(window);
    if (!root) return null;

    const snapshot = createTileSnapshot(root, true);
    const tile = window.tile || findLeafMatchingGeometry(window, snapshot);
    if (!tile) return null;

    return { window, tile, snapshot };
}

function moveFocus(direction) {
    const context = activeTileContext();
    if (!context) return;

    // Skip empty tiles so focus can jump across gaps.
    const tile = directionalTile(
        context.snapshot, context.tile, direction,
        candidate => windowForTile(candidate, context.window) !== null
    );
    const window = windowForTile(tile, context.window);

    if (window) workspace.activeWindow = window;
}

function swapWindow(direction) {
    const context = activeTileContext();
    if (!context) return;

    const targetTile = directionalTile(context.snapshot, context.tile, direction);
    if (!targetTile) return;

    const targetWindow = windowForTile(targetTile, context.window);

    if (targetWindow) {
        context.window.tile = targetTile;
        targetWindow.tile = context.tile;

        rememberTileState(context.window.mt, targetTile);
        rememberTileState(targetWindow.mt, context.tile);
    } else {
        // Move into the tile only if nothing occupies or has reserved it
        // (e.g. a fullscreen window that will return to it).
        const snapshotCache = new Map([[context.snapshot.root, context.snapshot]]);
        const occupants = computeOccupancies(
            context.snapshot, context.window, snapshotCache
        ).get(targetTile);

        if (occupants.size > 0) return;

        context.window.tile = targetTile;
        rememberTileState(context.window.mt, targetTile);
    }

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

workspace.windowList().forEach(window => {
    if (window.normalWindow) track(window);
});

workspace.windowAdded.connect(placeWindow);
