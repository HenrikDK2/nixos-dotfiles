import subprocess, statistics, sys
scens = sys.argv[1].split(','); rounds=int(sys.argv[2]); N='200000'
res={}
for r in range(rounds):
    order = ['old','new'] if r%2==0 else ['new','old']
    for s in scens:
        vals={}
        for v in order:
            out=subprocess.run(['./build/bench',v,s,N,'3'],capture_output=True,text=True).stdout.split()
            vals[v]=statistics.median(float(x) for x in out)
        res.setdefault(s,{'old':[],'new':[],'ratio':[]})
        res[s]['old'].append(vals['old']); res[s]['new'].append(vals['new']); res[s]['ratio'].append(vals['new']/vals['old'])
for s,d in res.items():
    q=lambda a: statistics.quantiles(a,n=4)
    print(f"{s}: old {statistics.median(d['old']):.1f} [{min(d['old']):.1f}-{max(d['old']):.1f}]  new {statistics.median(d['new']):.1f} [{min(d['new']):.1f}-{max(d['new']):.1f}]  ratio med {statistics.median(d['ratio']):.3f} IQR {q(d['ratio'])[0]:.3f}-{q(d['ratio'])[2]:.3f}")
