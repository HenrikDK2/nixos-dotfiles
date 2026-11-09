"use strict";
// One timing run: K iterations of the fixed scenario per N (warm-up runs
// first, script load not timed). Prints JSON
//   { "<N>": { "<phase>": ns_per_event, ..., "TOTAL": ns_per_scenario } }
// usage: node time.js <main.js> [--n 1,4,8,16] [--iters 400] [--layout L5]
const { loadScript } = require("./mock");
const { makeEnv, phases } = require("./scenario");

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const script = loadScript(args[0]);
const Ns = opt("--n", "1,4,8,16").split(",").map(Number);
const iters = Number(opt("--iters", "400"));
const layout = opt("--layout", "L5");

const result = {};
for (const N of Ns) {
    const acc = {};
    const evs = {};
    // One loaded script per N, the scenario repeated on it (each run opens and
    // closes its windows), so timings reflect warmed-up handlers.
    const env = makeEnv(script, { layout, detailed: false, log: false });
    const weights = new Map();
    for (const root of env.roots.values()) {
        const walk = t => { if (t._weights) weights.set(t, t._weights.slice()); t._children.forEach(walk); };
        walk(root);
    }
    const run = (record) => {
        for (const [t, w] of weights) t._weights = w.slice();
        for (const root of env.roots.values()) env.layoutGeometry(root);
        env.setActive(null);
        const ctx = {};
        for (const phase of phases(N)) {
            const t0 = process.hrtime.bigint();
            const events = phase.run(env, ctx);
            const dt = Number(process.hrtime.bigint() - t0);
            if (record) {
                acc[phase.name] = (acc[phase.name] || 0) + dt;
                evs[phase.name] = events;
            }
        }
    };
    for (let i = 0; i < Math.max(50, iters / 4); i++) run(false); // warm-up / JIT
    for (let i = 0; i < iters; i++) run(true);
    const row = {};
    let total = 0;
    for (const k of Object.keys(acc)) {
        row[k] = acc[k] / iters / evs[k];
        total += acc[k] / iters;
    }
    row.TOTAL = total;
    result[N] = row;
}
console.log(JSON.stringify(result));
