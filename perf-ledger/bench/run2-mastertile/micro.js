"use strict";
// Micro-benchmark of single handlers after the scenario's "open" phase (N=8, L5):
//   fgc-tiled:  frameGeometryChanged on a tiled window
//   fgc-drag:   frameGeometryChanged during an interactive move
//   fgc-float:  frameGeometryChanged on an untiled overflow window
//   place:      windowAdded placement of a 9th window (then closed again)
// Prints JSON { "8": { case: ns_per_call } } (shape accepted by ab.js --tool micro.js).
// usage: node micro.js <main.js> [--iters 200000]
const { loadScript, rect } = require("./mock");
const { makeEnv, phases } = require("./scenario");

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const iters = Number(opt("--iters", "200000"));
const script = loadScript(args[0]);
const env = makeEnv(script, { layout: "L5", detailed: false, log: false });
const ctx = {};
phases(8)[0].run(env, ctx);

const tiled = ctx.wins[0];
const floating = ctx.wins.find(w => !w._tile);
const dragged = ctx.wins[1];

function time(fn, n) {
    for (let i = 0; i < Math.min(n, 20000); i++) fn();
    const t0 = process.hrtime.bigint();
    for (let i = 0; i < n; i++) fn();
    return Number(process.hrtime.bigint() - t0) / n;
}

const out = {};
out["fgc-tiled"] = time(() => tiled._sig.frameGeometryChanged.emit(), iters);
out["fgc-float"] = time(() => floating._sig.frameGeometryChanged.emit(), iters / 10);
env.startMove(dragged, true);
out["fgc-drag"] = time(() => dragged._sig.frameGeometryChanged.emit(), iters);
env.finishMove(dragged);
out.place = time(() => {
    const w = env.addWindow({ output: env.outputs[0], desktops: [env.desktops[0]], resourceClass: "kate", geometry: rect(700, 300, 900, 700) });
    env.closeWindow(w);
}, iters / 100);
console.log(JSON.stringify({ 8: out }));
