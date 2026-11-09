"use strict";
// Fixed, realistic event scenario for N windows. Each phase is a list of
// driver actions ("events"); the harness measures KWin API traffic and time
// per phase.
const { createEnv, LAYOUTS, rect } = require("./mock");

const CLASSES = ["firefox", "org.kde.konsole", "code", "org.kde.dolphin", "discord", "steam"];

function makeEnv(script, opts = {}) {
    const env = createEnv({ config: opts.config || {}, detailed: opts.detailed, tilingApi: opts.tilingApi, log: opts.log });
    const layout = LAYOUTS[opts.layout || "L5"];
    env.setupRoots(out => (out._id === 0 ? layout : LAYOUTS.L3));
    // Non-normal windows that are always in windowList(): desktop, panel, notification.
    for (let i = 0; i < 3; i++) {
        env.addExisting({ output: env.outputs[0], desktops: [], normalWindow: false, resourceClass: "plasmashell" });
    }
    env.load(script);
    return env;
}

// Returns [{ name, run(env, ctx) -> number of events }]
function phases(N) {
    const out0 = env => env.outputs[0];
    const d = (env, i) => env.desktops[i];
    const normals = env => env.windows.filter(w => w._normal);
    return [
        { name: "open", run(env, ctx) {
            ctx.wins = [];
            for (let i = 0; i < N; i++) {
                ctx.wins.push(env.addWindow({
                    output: out0(env), desktops: [d(env, 0)], resourceClass: CLASSES[i % CLASSES.length],
                    geometry: rect(880 + i * 8, 420 + i * 8, 800, 600),
                }));
            }
            return N;
        } },
        { name: "tileResize", run(env) {
            const root = env.rootFor(0, 0);
            for (let s = 0; s < 10; s++) {
                root._weights[0] += (s % 2 ? -0.05 : 0.07);
                env.relayout(root);
            }
            return 10;
        } },
        { name: "appGeometry", run(env, ctx) {
            let n = 0;
            for (let k = 0; k < 5; k++) {
                for (const w of ctx.wins) {
                    const g = w._geom;
                    env.moveTo(w, rect(g.x, g.y, g.width + (k % 2 ? -1 : 1), g.height));
                    n++;
                }
            }
            return n;
        } },
        { name: "drag", run(env, ctx) {
            const w = ctx.wins[0];
            const home = w._tile;
            env.startMove(w, true);
            for (let s = 0; s < 30; s++) env.moveTo(w, rect(300 + s * 17, 200 + s * 9, w._geom.width, w._geom.height));
            env.finishMove(w);
            env.startMove(w, false);
            for (let s = 0; s < 29; s++) env.moveTo(w, rect(900 - s * 11, 500 - s * 7, w._geom.width, w._geom.height));
            if (home) env.moveTo(w, env.tileGeomForWindow(home));
            env.finishMove(w);
            // The next app/KWin geometry change lets the script re-tile it.
            if (home) {
                const g = env.tileGeomForWindow(home);
                env.moveTo(w, rect(g.x + 1, g.y, g.width, g.height));
            }
            return 65;
        } },
        { name: "fullscreen", run(env, ctx) {
            const a = ctx.wins[Math.min(1, N - 1)];
            const b = ctx.wins[Math.min(2, N - 1)];
            env.setFullScreen(a, true, false);
            env.setFullScreen(a, false);
            env.setFullScreen(b, true, true);
            env.setFullScreen(b, false);
            return 4;
        } },
        { name: "focus", run(env, ctx) {
            env.setActive(ctx.wins[0]);
            for (const dir of ["left", "right", "up", "down", "right", "left", "down", "up"]) {
                env.shortcut("mastertile-focus-" + dir);
            }
            return 8;
        } },
        { name: "swap", run(env, ctx) {
            env.setActive(ctx.wins[0]);
            for (const dir of ["right", "left", "up", "down"]) env.shortcut("mastertile-swap-" + dir);
            return 4;
        } },
        { name: "desktop", run(env, ctx) {
            const w = ctx.wins[N - 1];
            env.setDesktops(w, [d(env, 1)]);
            env.setDesktops(w, [d(env, 0)]);
            return 2;
        } },
        { name: "minimizeOpen", run(env, ctx) {
            env.setMinimized(ctx.wins[0], true);
            ctx.wins.push(env.addWindow({
                output: out0(env), desktops: [d(env, 0)], resourceClass: "org.kde.kate",
                geometry: rect(700, 300, 900, 700),
            }));
            env.setMinimized(ctx.wins[0], false);
            return 1;
        } },
        { name: "close", run(env, ctx) {
            for (const w of ctx.wins) env.closeWindow(w);
            return ctx.wins.length;
        } },
    ];
}

module.exports = { makeEnv, phases, CLASSES };
