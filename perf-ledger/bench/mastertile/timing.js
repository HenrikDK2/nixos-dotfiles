#!/usr/bin/env node
// Interleaved A/B(/C...) timing of the measured part of selected scenarios.
// usage: node [--jitless] timing.js [--batches 15] [--reps R] [--scen REGEX] label=path ...
// Each batch runs every variant (order rotated per batch) `reps` times per
// scenario; reports per-event ns: median and min-max over batches, and the
// median of per-batch paired ratios vs the first variant.
"use strict";
const fs = require("fs");
const { scenarios, runScenario } = require("./scenarios.js").MTScenarios;
const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const batches = Number(opt("--batches", 15));
const repsOverride = opt("--reps", null);
const scenRe = new RegExp(opt("--scen", "^(place/cols3/N3|place/cols3/N8|place/grid3x2/N6|place/grid3x2/stack/N12|storm/move|storm/tiled|storm/float|focus/grid3x2|swap/grid3x2|desktop/rootTile/perdesk|startup/N12)$"));
const srcs = args.filter((x, i) => !x.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--"))).map(x => {
    const [label, p] = x.split("=");
    return { label, src: fs.readFileSync(p, "utf8") };
});
const now = () => process.hrtime.bigint();

function timeOnce(fn, src) {
    let ns = 0n, events = 0;
    const measure = (world, name, ev, body) => {
        const t0 = now(); body(); ns += now() - t0; events += ev;
    };
    fn(src, measure);
    return [Number(ns), events];
}

const names = Object.keys(scenarios).filter(n => scenRe.test(n));
const median = a => { const s = a.slice().sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const results = {};
for (const name of names) {
    const fn = scenarios[name];
    // reps: aim for ~1e4 measured events per variant per batch, min 20 runs
    const [ns0, ev0] = timeOnce(fn, srcs[0].src);
    const target = Number(opt("--events", 3000));
    const reps = repsOverride ? Number(repsOverride) : Math.max(10, Math.ceil(target / ev0));
    for (let w = 0; w < 2; w++) for (const s of srcs) for (let r = 0; r < reps; r++) timeOnce(fn, s.src); // warm-up
    const per = srcs.map(() => []);
    for (let b = 0; b < batches; b++) {
        for (let k = 0; k < srcs.length; k++) {
            const v = (b + k) % srcs.length;
            let ns = 0, ev = 0;
            for (let r = 0; r < reps; r++) { const [a, e] = timeOnce(fn, srcs[v].src); ns += a; ev += e; }
            per[v].push(ns / ev);
        }
    }
    results[name] = per;
    const base = per[0];
    const cols = srcs.map((s, v) => {
        const m = median(per[v]);
        const ratio = v === 0 ? "" : " ratio=" + median(per[v].map((x, i) => x / base[i])).toFixed(3) +
            " (" + (100 * (1 - median(per[v].map((x, i) => x / base[i])))).toFixed(1) + "% faster)";
        return `${s.label}: ${m.toFixed(0)} ns/ev [${Math.min(...per[v]).toFixed(0)}-${Math.max(...per[v]).toFixed(0)}]${ratio}`;
    });
    console.log(`${name} (reps=${reps}, batches=${batches})\n  ` + cols.join("\n  "));
}
if (opt("--json", null)) fs.writeFileSync(opt("--json"), JSON.stringify(results));
