// QuickJS (bytecode interpreter, no JIT) interleaved timing.
// usage: qjs --std qjs-timing.js BENCH_DIR BATCHES SCEN_REGEX TARGET_EVENTS label=path ...
"use strict";
const argv = scriptArgs.slice(1);
const dir = argv[0], batches = Number(argv[1]), scenRe = new RegExp(argv[2]), target = Number(argv[3]);
std.loadScript(dir + "/kwin-mock.js");
std.loadScript(dir + "/scenarios.js");
const { scenarios } = globalThis.MTScenarios;
const srcs = argv.slice(4).map(x => { const [label, p] = x.split("="); return { label, src: std.loadFile(p) }; });
function timeOnce(fn, src) {
    let ms = 0, events = 0;
    fn(src, (world, name, ev, body) => { const t0 = Date.now(); body(); ms += Date.now() - t0; events += ev; });
    return [ms, events];
}
const median = a => { const s = a.slice().sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
for (const name of Object.keys(scenarios).filter(n => scenRe.test(n))) {
    const fn = scenarios[name];
    const ev0 = timeOnce(fn, srcs[0].src)[1];
    const reps = Math.max(10, Math.ceil(target / ev0));
    for (const s of srcs) for (let r = 0; r < reps; r++) timeOnce(fn, s.src);
    const per = srcs.map(() => []);
    for (let b = 0; b < batches; b++) {
        for (let k = 0; k < srcs.length; k++) {
            const v = (b + k) % srcs.length;
            let ms = 0, ev = 0;
            for (let r = 0; r < reps; r++) { const [a, e] = timeOnce(fn, srcs[v].src); ms += a; ev += e; }
            per[v].push(ms * 1e6 / ev);
        }
    }
    const out = srcs.map((s, v) => {
        const r = v ? median(per[v].map((x, i) => x / per[0][i])) : 1;
        return s.label + ": " + median(per[v]).toFixed(0) + " ns/ev [" + Math.min(...per[v]).toFixed(0) + "-" +
            Math.max(...per[v]).toFixed(0) + "]" + (v ? " ratio=" + r.toFixed(3) + " (" + (100 * (1 - r)).toFixed(1) + "% faster)" : "");
    });
    print(name + " (reps=" + reps + ", batches=" + batches + ")\n  " + out.join("\n  "));
}
