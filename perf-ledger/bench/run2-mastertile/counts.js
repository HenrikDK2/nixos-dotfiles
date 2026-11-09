"use strict";
// Deterministic KWin API traffic per phase of the fixed scenario.
// usage: node counts.js <main.js> [--n 1,4,8,16] [--layout L5] [--json] [--keys]
const { loadScript } = require("./mock");
const { makeEnv, phases } = require("./scenario");

function countScenario(script, N, layout, config) {
    const env = makeEnv(script, { layout, config, detailed: true });
    const ctx = {};
    const rows = [];
    for (const phase of phases(N)) {
        const before = { ...env.stats, byKey: { ...env.stats.byKey } };
        const events = phase.run(env, ctx);
        const s = env.stats;
        const byKey = {};
        for (const k of Object.keys(s.byKey)) {
            const dlt = s.byKey[k] - (before.byKey[k] || 0);
            if (dlt) byKey[k] = dlt;
        }
        rows.push({
            phase: phase.name, events,
            reads: s.reads - before.reads, writes: s.writes - before.writes,
            calls: s.calls - before.calls, expando: s.expando - before.expando,
            emits: s.emits - before.emits, byKey,
        });
    }
    return { rows, log: env.writeLog };
}

function apiOf(r) { return r.reads + r.writes + r.calls; }

if (require.main === module) {
    const args = process.argv.slice(2);
    const file = args[0];
    const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
    const Ns = opt("--n", "1,4,8,16").split(",").map(Number);
    const layout = opt("--layout", "L5");
    const script = loadScript(file);
    const out = {};
    for (const N of Ns) {
        const { rows } = countScenario(script, N, layout);
        out[N] = rows;
        if (!args.includes("--json")) {
            console.log(`N=${N} layout=${layout}`);
            let tot = { events: 0, reads: 0, writes: 0, calls: 0, expando: 0, emits: 0 };
            for (const r of rows) {
                for (const k of Object.keys(tot)) tot[k] += r[k];
                console.log(`  ${r.phase.padEnd(13)} ev=${String(r.events).padStart(3)} emits=${String(r.emits).padStart(4)} ` +
                    `reads=${String(r.reads).padStart(6)} writes=${String(r.writes).padStart(3)} calls=${String(r.calls).padStart(4)} ` +
                    `api=${String(apiOf(r)).padStart(6)} api/ev=${(apiOf(r) / r.events).toFixed(1).padStart(7)} expando=${r.expando}`);
                if (args.includes("--keys")) {
                    for (const [k, v] of Object.entries(r.byKey).sort((a, b) => b[1] - a[1])) console.log(`      ${k}: ${v}`);
                }
            }
            console.log(`  ${"TOTAL".padEnd(13)} ev=${tot.events} emits=${tot.emits} reads=${tot.reads} writes=${tot.writes} calls=${tot.calls} api=${tot.reads + tot.writes + tot.calls} expando=${tot.expando}`);
        }
    }
    if (args.includes("--json")) console.log(JSON.stringify(out));
}

module.exports = { countScenario, apiOf };
