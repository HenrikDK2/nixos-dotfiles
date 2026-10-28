"use strict";

// Animates windows that are moved/resized by scripts or apps (e.g. Master Tile
// Placement), plus an optional pop-in for new windows. User drags and fullscreen
// state transitions are handled cleanly without visual glitches.

const MIN_CHANGE_PX = 2;
const SETTLE_MS = 60;
const FULLSCREEN_SETTLE_MS = 180;

class MasterTileAnimation {
    constructor() {
        this.onGeometryChanged = this.onGeometryChanged.bind(this);
        this.onFullScreenChanged = this.onFullScreenChanged.bind(this);
        this.onWindowClosed = this.onWindowClosed.bind(this);

        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.onAnimationEnded.bind(this));
        effects.windowAdded.connect(this.onWindowAdded.bind(this));
        effects.windowClosed.connect(this.onWindowClosed);
        effects.stackingOrder.forEach(window => this.manage(window));
        this.loadConfig();
    }

    loadConfig() {
        this.duration = animationTime(Number(effect.readConfig("Duration", 300)));
        this.curve = this.curveFor(Number(effect.readConfig("Curve", 0)));
        this.animateOpen = effect.readConfig("AnimateOpen", true) === true;
        this.openScale = Math.min(100, Math.max(50, Number(effect.readConfig("OpenScale", 90)))) / 100;
        this.excluded = new Set(
            String(effect.readConfig("ExcludedClasses", "krunner,yakuake"))
                .split(",").map(value => value.trim().toLowerCase()).filter(Boolean)
        );
        this.configVersion = (this.configVersion || 0) + 1;
    }

    curveFor(index) {
        switch (index) {
        case 1: return QEasingCurve.OutQuint;
        case 2: return QEasingCurve.OutCubic;
        case 3: return QEasingCurve.OutBack;
        default: return QEasingCurve.OutExpo;
        }
    }

    isExcluded(window) {
        const state = window.mta;
        if (state.excludedVersion !== this.configVersion) {
            state.excluded = String(window.windowClass).toLowerCase().split(" ")
                .some(part => this.excluded.has(part));
            state.excludedVersion = this.configVersion;
        }
        return state.excluded;
    }

    canAnimate(window) {
        return window.managed && window.visible && !window.minimized &&
               !window.fullScreen &&
               window.onCurrentDesktop &&
               (window.normalWindow || window.dialog || window.modal) &&
               !this.isExcluded(window);
    }

    manage(window) {
        if (window.mta) return;

        window.mta = {
            born: Date.now(),
            fsChangedAt: 0,
            wasFullScreen: Boolean(window.fullScreen),
            running: 0,
            excluded: false,
            excludedVersion: -1,
        };

        // Keep blur independent of geometry animations and window.hasAlpha,
        // which may not be reliable during initial window setup.
        window.setData(Effect.WindowForceBlurRole, true);

        window.windowFrameGeometryChanged.connect(this.onGeometryChanged);
        if (window.windowFullScreenChanged) {
            window.windowFullScreenChanged.connect(this.onFullScreenChanged);
        }
    }

    onFullScreenChanged(window) {
        const state = window && window.mta;
        if (!state) return;
        state.wasFullScreen = Boolean(window.fullScreen);
        state.fsChangedAt = Date.now();
    }

    onWindowClosed(window) {
        const state = window && window.mta;
        if (!state) return;

        state.running = 0;
        window.setData(Effect.WindowForceBlurRole, null);
    }

    onWindowAdded(window) {
        this.manage(window);
        if (this.animateOpen && window.normalWindow && this.canAnimate(window)) {
            this.begin(window, 2);
            animate({
                window,
                duration: this.duration,
                curve: this.curve,
                animations: [
                    { type: Effect.Scale, from: this.openScale, to: 1 },
                    { type: Effect.Opacity, from: 0, to: 1 },
                ],
            });
        }
    }

    begin(window, count) {
        window.mta.running += count;
    }

    onAnimationEnded(window) {
        const state = window && window.mta;
        if (!state || state.running === 0) return;
        state.running--;
    }

    onGeometryChanged(window, old) {
        const state = window.mta;
        if (!state) return;
        if (window.move || window.resize) return;

        const nowMs = Date.now();
        if (nowMs - state.born < SETTLE_MS) return;

        if (window.fullScreen || state.wasFullScreen) {
            state.wasFullScreen = Boolean(window.fullScreen);
            state.fsChangedAt = nowMs;
            return;
        }
        if (nowMs - state.fsChangedAt < FULLSCREEN_SETTLE_MS) return;

        // Most geometry notifications are for windows that must not animate
        // (hidden, minimized, excluded, or off-desktop). Check eligibility before
        // reading and comparing multiple geometry coordinates.
        if (!this.canAnimate(window)) return;

        const now = window.geometry;
        if (now.width <= 0 || now.height <= 0 || old.width <= 0 || old.height <= 0) return;
        if (Math.abs(now.x - old.x) < MIN_CHANGE_PX &&
            Math.abs(now.y - old.y) < MIN_CHANGE_PX &&
            Math.abs(now.width - old.width) < MIN_CHANGE_PX &&
            Math.abs(now.height - old.height) < MIN_CHANGE_PX) return;

        this.begin(window, 2);
        animate({
            window,
            duration: this.duration,
            curve: this.curve,
            animations: [
                {
                    type: Effect.Translation,
                    from: {
                        value1: (old.x + old.width / 2) - (now.x + now.width / 2),
                        value2: (old.y + old.height / 2) - (now.y + now.height / 2),
                    },
                    to: { value1: 0, value2: 0 },
                },
                {
                    type: Effect.Scale,
                    from: { value1: old.width / now.width, value2: old.height / now.height },
                    to: { value1: 1, value2: 1 },
                },
            ],
        });
    }
}

new MasterTileAnimation();
