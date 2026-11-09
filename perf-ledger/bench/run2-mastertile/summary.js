"use strict";
// Deterministic API-traffic comparison table.
// usage: node summary.js <base main.js> <cand main.js>... [--layout L5] [--n 1,4,8,16]
const { loadScript } = require("./mock");
const { countScenario, apiOf } = require("./counts");

const args = process.argv.slice(2);
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const layout = opt("--layout", "L5");
const Ns = opt("--n", "1,4,8,16").split(",").map(Number);
const files = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--")));
const [baseFile, ...candFiles] = files;
const base = loadScript(baseFile);

for (const N of Ns) {
    const b = countScenario(base, N, layout).rows;
    console.log(`N=${N} layout=${layout}  (API accesses = reads+writes+calls; per phase, base -> candidate)`);
    for (const f of candFiles) {
        const c = countScenario(loadScript(f), N, layout).rows;
        const tb = b.reduce((s, r) => s + apiOf(r), 0);
        const tc = c.reduce((s, r) => s + apiOf(r), 0);
        const parts = b.map((r, i) => {
            const x = apiOf(r), y = apiOf(c[i]);
            return x === y ? null : `${r.phase} ${(x / r.events).toFixed(1)}->${(y / r.events).toFixed(1)}/ev`;
        }).filter(Boolean);
        console.log(`  ${f}: total ${tb} -> ${tc} (${((tb - tc) / tb * 100).toFixed(1)}% fewer)  ${parts.join(", ")}`);
    }
}
