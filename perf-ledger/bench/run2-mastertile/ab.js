"use strict";
// A/B wall-time comparison: runs time.js for A and B in separate node
// processes, alternating ABAB..., pinned to one CPU.
// usage: node ab.js <A main.js> <B main.js> [--runs 12] [--iters 400] [--cpu 3] [--n 1,4,8,16] [--tool time.js|micro.js]
const { execFileSync } = require("child_process");
const path = require("path");

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const [A, B] = args;
const runs = Number(opt("--runs", "12"));
const iters = opt("--iters", "400");
const cpu = opt("--cpu", "3");
const Ns = opt("--n", "1,4,8,16");
const timeJs = path.join(__dirname, opt("--tool", "time.js"));

const samples = { A: [], B: [] };
for (let r = 0; r < runs; r++) {
    const order = r % 2 === 0 ? ["A", "B"] : ["B", "A"];
    for (const which of order) {
        const file = which === "A" ? A : B;
        const extra = opt("--tool", "time.js") === "time.js" ? ["--n", Ns, "--iters", iters] : ["--iters", opt("--iters", "200000")];
        const out = execFileSync("taskset", ["-c", cpu, process.execPath, timeJs, file, ...extra], { encoding: "utf8" });
        samples[which].push(JSON.parse(out));
    }
}

const median = xs => { const s = xs.slice().sort((a, b) => a - b); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const fmt = x => (x >= 1e5 ? (x / 1000).toFixed(1) + "us" : x.toFixed(0) + "ns");
const summary = {};
for (const N of Object.keys(samples.A[0])) {
    summary[N] = {};
    for (const phase of Object.keys(samples.A[0][N])) {
        const a = samples.A.map(s => s[N][phase]);
        const b = samples.B.map(s => s[N][phase]);
        const ma = median(a), mb = median(b);
        summary[N][phase] = {
            A: { median: ma, min: Math.min(...a), max: Math.max(...a) },
            B: { median: mb, min: Math.min(...b), max: Math.max(...b) },
            deltaPct: (ma - mb) / ma * 100,
        };
        console.log(`N=${N.padStart(2)} ${phase.padEnd(13)} A ${fmt(ma).padStart(8)} [${fmt(Math.min(...a))}..${fmt(Math.max(...a))}]  ` +
            `B ${fmt(mb).padStart(8)} [${fmt(Math.min(...b))}..${fmt(Math.max(...b))}]  improvement ${((ma - mb) / ma * 100).toFixed(1)}%`);
    }
}
if (args.includes("--json")) console.log(JSON.stringify(summary));
