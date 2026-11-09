#!/usr/bin/env node
// Behavioural equivalence: run every deterministic scenario and N random seeded
// scenarios against two sources; compare full traces (tile writes, activations,
// print output, final window/tile/state). Exit 1 on the first mismatch.
// usage: node equiv.js <old main.js> <new main.js> [seeds=1000]
"use strict";
const fs = require("fs");
const { scenarios, randomScenario, runScenario } = require("./scenarios.js").MTScenarios;
const [a, b, seedsArg] = process.argv.slice(2);
if (!a || !b) { console.error("usage: node equiv.js OLD NEW [seeds]"); process.exit(2); }
const srcA = fs.readFileSync(a, "utf8"), srcB = fs.readFileSync(b, "utf8");
const seeds = Number(seedsArg || 1000);

function run(fn, src) {
    try { return runScenario(fn, src, false).trace; }
    catch (e) { return ["THROW " + (e && e.message)]; }
}
function cmp(name, fn) {
    const ta = run(fn, srcA), tb = run(fn, srcB);
    const n = Math.max(ta.length, tb.length);
    for (let i = 0; i < n; i++) {
        if (ta[i] !== tb[i]) {
            console.log("MISMATCH " + name + " at trace[" + i + "]\n  old: " + ta[i] + "\n  new: " + tb[i]);
            return false;
        }
    }
    return ta.length;
}
let ok = 0, lines = 0, tileWrites = 0, prints = 0;
for (const [name, fn] of Object.entries(scenarios)) {
    const r = cmp(name, fn); if (r === false) process.exit(1); ok++; lines += r;
}
for (let s = 0; s < seeds; s++) {
    const fn = randomScenario(s);
    const r = cmp("random/" + s, fn); if (r === false) process.exit(1); ok++; lines += r;
    if (s < 200) {
        const t = run(fn, srcA);
        tileWrites += t.filter(l => l.startsWith("tile ")).length;
        prints += t.filter(l => l.startsWith("print ")).length;
    }
}
console.log(`EQUIVALENT: ${ok} scenarios (${Object.keys(scenarios).length} fixed + ${seeds} random), ${lines} trace lines compared; ` +
    `first 200 seeds exercised ${tileWrites} tile writes, ${prints} log lines`);
