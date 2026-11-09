#!/usr/bin/env python3
"""realkill.py SRC_A SRC_B: kill_lingering_processes of two exit.sh versions on
the REAL /proc with real pgrep, in a fresh PID namespace (re-execs itself under
`unshare -p -f --mount-proc`). killall is the logging stub. For every mix of
gamescope-wl / gamescopereaper / winedevice.exe (0-2) / other *.exe processes
(0-2), plus look-alike names, both versions must make the same killall calls.
Also reports the CPU of each version's call (median of 15) with 450 extra
processes."""
import itertools, os, resource, shutil, statistics, subprocess, sys, tempfile, time
B = os.path.dirname(os.path.abspath(__file__))
if os.getpid() != 1 and os.environ.get("GB_RK_INNER") != "1":
    os.environ["GB_RK_INNER"] = "1"
    os.execvp("unshare", ["unshare", "-p", "-f", "--mount-proc", sys.executable] + sys.argv)
srcs = sys.argv[1:]
tmp = tempfile.mkdtemp()
binp = shutil.which("sleep")
names = ["gamescope-wl", "gamescopereaper", "winedevice.exe", " gamescope-wl", "winedeviceXexe",
         "gamescope-wl2"]
for n in names:
    shutil.copy(binp, os.path.join(tmp, n))
libs = []
for s in srcs:
    lib = os.path.join(tmp, f"lib{len(libs)}.sh")
    open(lib, "w").write("".join(open(f"{s}/exit.sh").readlines()[:-1]))
    libs.append(lib)
log = os.path.join(tmp, "log")
env = {"PATH": f"{B}/build/killall-only:/usr/bin:/bin", "LC_ALL": "C", "GB_LOG": log}
os.makedirs(f"{B}/build/killall-only", exist_ok=True)
if not os.path.exists(f"{B}/build/killall-only/killall"):
    os.symlink("../stub", f"{B}/build/killall-only/killall")

def spawn(name, argv0=None):
    return subprocess.Popen([os.path.join(tmp, name), "300"] if argv0 is None else
                            ["bash", "-c", f'exec -a "{argv0}" {binp} 300'])

def run(lib):
    if os.path.exists(log):
        os.unlink(log)
    subprocess.run(["bash", "-c", f". {lib}; kill_lingering_processes; echo rc=$?"], env=env,
                   stdout=open(log + ".out", "w"))
    # bash does not always wait for the <(pgrep) process; it is reparented
    # to us (PID 1 here): reap it so its CPU time is counted
    time.sleep(0.03)
    try:
        while os.waitpid(-1, os.WNOHANG)[0] > 0:
            pass
    except ChildProcessError:
        pass
    calls = open(log).read() if os.path.exists(log) else ""
    return calls + open(log + ".out").read()

cases = bad = 0
for wl, reaper, wd, exe, odd in itertools.product([0, 1], [0, 1], [0, 1, 2], [0, 1, 2], [0, 1]):
    ps = []
    ps += [spawn("gamescope-wl") for _ in range(wl)]
    ps += [spawn("gamescopereaper") for _ in range(reaper)]
    ps += [spawn("winedevice.exe") for _ in range(wd)]
    ps += [spawn(None, f"C:\\\\game\\\\g{i}.exe") for i in range(exe)]
    if odd:
        ps += [spawn(" gamescope-wl"), spawn("winedeviceXexe"), spawn("gamescope-wl2")]
    time.sleep(0.15)
    outs = [run(l) for l in libs]
    cases += 1
    if len(set(outs)) != 1:
        bad += 1
        print("MISMATCH", dict(wl=wl, reaper=reaper, wd=wd, exe=exe, odd=odd), outs)
    for p in ps:
        p.kill()
    for p in ps:
        try:
            p.wait()
        except ChildProcessError:
            pass
print(f"realkill: {cases} cases, {bad} mismatches")
# CPU with ~450 processes (no matches, so no killall / pgrep -fc)
ps = [spawn("gamescope-wl2") for _ in range(450)]
time.sleep(1)
cpu = {i: [] for i in range(len(libs))}
for r in range(15):
    for i in (range(len(libs)) if r % 2 == 0 else reversed(range(len(libs)))):
        r0 = resource.getrusage(resource.RUSAGE_CHILDREN)
        run(libs[i])
        r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu[i].append(((r1.ru_utime - r0.ru_utime) + (r1.ru_stime - r0.ru_stime)) * 1000)
for i, s in enumerate(srcs):
    v = sorted(cpu[i])
    print(f"cpu {os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(s))))}: "
          f"median {statistics.median(v):.2f} ms, min-max {v[0]:.2f}-{v[-1]:.2f} (bash startup + source + call)")
for p in ps:
    p.kill()
sys.exit(1 if bad else 0)
