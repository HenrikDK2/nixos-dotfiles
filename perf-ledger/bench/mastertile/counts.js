#!/usr/bin/env node
// Deterministic KWin bridge-crossing counts per event, per scenario.
// usage: node counts.js [--json] [--detail] [--filter REGEX] label=path/main.js ...
"use strict";
const fs = require("fs");
const { scenarios, runScenario, STAT_KEYS } = require("./scenarios.js").MTScenarios;
const args = process.argv.slice(2);
const json = args.includes("--json"), detail = args.includes("--detail");
const fi = args.indexOf("--filter");
const filter = fi >= 0 ? new RegExp(args[fi + 1]) : null;
const srcs = args.filter((x, i) => !x.startsWith("--") && !(fi >= 0 && i === fi + 1)).map(x => {
    const [label, p] = x.includes("=") ? x.split("=") : [x, x];
    return { label, src: fs.readFileSync(p, "utf8") };
});
const out = {};
for (const [name, fn] of Object.entries(scenarios)) {
    if (filter && !filter.test(name)) continue;
    out[name] = {};
    for (const s of srcs) {
        const r = runScenario(fn, s.src, detail);
        for (const [m, v] of Object.entries(r.marks)) {
            const st = v.stats, e = v.events;
            const bridge = st.read + st.write + st.call + st.dyn;
            out[name][s.label] = { events: e, bridge: bridge / e, all: (bridge + st.value) / e,
                read: st.read / e, write: st.write / e, call: st.call / e, value: st.value / e, dyn: st.dyn / e,
                detail: detail ? v.detail : undefined };
        }
    }
}
if (json) { console.log(JSON.stringify(out, null, 1)); process.exit(0); }
const labels = srcs.map(s => s.label);
const f = x => (Math.round(x * 100) / 100).toString();
console.log(["scenario", ...labels.map(l => l + ":bridge"), ...labels.map(l => l + ":+value"), ...(labels.length > 1 ? ["d_bridge%", "d_all%"] : [])].join("\t"));
for (const [name, r] of Object.entries(out)) {
    const row = [name, ...labels.map(l => f(r[l].bridge)), ...labels.map(l => f(r[l].all))];
    if (labels.length > 1) {
        const a = r[labels[0]], b = r[labels[labels.length - 1]];
        row.push(f(100 * (a.bridge - b.bridge) / a.bridge), f(100 * (a.all - b.all) / a.all));
    }
    console.log(row.join("\t"));
    if (detail) for (const l of labels) console.log("  " + l + " " + JSON.stringify(r[l].detail));
}
