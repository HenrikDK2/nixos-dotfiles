#!/usr/bin/env python3
"""Build a fake /sys, /proc and /run tree for one GameBoost scenario.

usage: gen.py ROOT SCENARIO [--cpus N] [--procs N] [--game-threads N]

ROOT gets:
  sys/ proc/ run/           the trees the rewritten scripts use
  resp/NAME                 stub responses (see stub.c)
  args                      start.sh arguments (the matched PIDs)
  env                       extra KEY=VALUE lines for the run (e.g. GB_REJECT)
The scripts see ROOT/sys at /sys, ROOT/run at /run and ROOT/proc at /home
(ns.sh bind-mounts them; prep.sh rewrites "/proc/" to "/home/", same length).
Everything is deterministic for a given scenario and parameters.
"""
import argparse
import os
import random
import shutil

p = argparse.ArgumentParser()
p.add_argument("root")
p.add_argument("scenario")
p.add_argument("--cpus", type=int, default=32)
p.add_argument("--procs", type=int, default=500)
p.add_argument("--game-threads", type=int, default=120)
p.add_argument("--pci", type=int, default=40)
a = p.parse_args()

R = os.path.abspath(a.root)
S = a.scenario
if os.path.exists(R):
    shutil.rmtree(R)
os.makedirs(R)
rnd = random.Random(12345)

# Scenario knobs
laptop = S.startswith("laptop")
on_ac = S in ("laptop-ac",)
ppd = S in ("desktop-ppd", "powerplay-ppd-refused", "laptop-ac")
ppd_driver = {"desktop-ppd": "amd_pstate", "powerplay-ppd-refused": "intel_pstate",
              "laptop-ac": "intel_pstate"}.get(S)
hold_ok = S != "powerplay-ppd-refused"
intel = S in ("laptop-ac", "laptop-battery", "powerplay-ppd-refused")
powerplay = S == "powerplay-ppd-refused"
reentry = S == "reentry"
cups = {"desktop-sysfs": ("active", "active"), "desktop-ppd": ("active", "inactive"),
        "reentry": ("active", "active"), "odd-procs": ("inactive", "inactive"),
        "laptop-battery": ("active", "active"), "laptop-ac": ("reloading", "failed"),
        "powerplay-ppd-refused": ("inactive", "active")}.get(S, ("active", "active"))
odd = S == "odd-procs"


def w(path, content, mode=0o644):
    full = R + path
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w" if isinstance(content, str) else "wb") as f:
        f.write(content)
    os.chmod(full, mode)


def d(path):
    os.makedirs(R + path, exist_ok=True)


# ---------------------------------------------------------------- /sys: CPU
cpu = "/sys/devices/system/cpu"
if not intel:
    w(cpu + "/amd_pstate/status", "active\n" if S != "desktop-sysfs" else "passive\n")
else:
    w(cpu + "/intel_pstate/no_turbo", "1\n")
for c in range(a.cpus):
    base = f"{cpu}/cpu{c}/cpufreq"
    w(f"{base}/scaling_governor", "powersave\n")
    w(f"{base}/scaling_available_governors", "performance powersave\n")
    w(f"{base}/energy_performance_preference", "balance_performance\n")
    w(f"{base}/energy_performance_available_preferences",
      "default performance balance_performance balance_power power\n")
    if not intel:
        w(f"{base}/boost", "1\n")
    d(f"{cpu}/cpu{c}/topology")
d(f"{cpu}/cpufreq")
if S == "desktop-sysfs":
    w(f"{cpu}/cpufreq/boost", "1\n")  # acpi-cpufreq style global boost too
if not intel and not laptop:
    w("/sys/bus/platform/drivers/amd_x3d_vcache/AMDI0101:00/amd_x3d_mode", "frequency\n")

# sched
w("/sys/kernel/debug/sched/base_slice_ns", "3000000\n")
if S == "odd-procs":
    w("/sys/kernel/sched_ext/state", "disabled\n")

# ---------------------------------------------------------------- /sys: PCI
pci = "/sys/bus/pci/devices"
for i in range(a.pci):
    dev = f"{pci}/0000:{i // 8:02x}:{i % 8:02x}.0"
    cls = "0x060400" if i % 5 else "0x0c0330"
    if i == 3:
        cls = "0x030000"  # the GPU
    if i == 7 and S == "desktop-sysfs":
        cls = "0x038000"  # an iGPU without pp_power_profile_mode writes
    w(f"{dev}/class", cls + "\n")
    w(f"{dev}/power/control", "auto\n" if i % 3 else "on\n")
    if i == 3:
        if powerplay:
            prof = ("NUM        MODE_NAME     SCLK_UP_HYST   SCLK_DOWN_HYST\n"
                    "  0   BOOTUP_DEFAULT *:        -        -\n"
                    "  1 3D_FULL_SCREEN :        0      100\n"
                    "  2   POWER_SAVING :       10        0\n")
        else:
            prof = ("PROFILE_INDEX(NAME) CLOCK_TYPE(NAME) FPS MinActiveFreqType\n"
                    "  0 BOOTUP_DEFAULT*:\n"
                    "                    0(       GFXCLK)       0       5\n"
                    "  1 3D_FULL_SCREEN :\n"
                    "                    0(       GFXCLK)       1       5\n"
                    "  2   POWER_SAVING :\n"
                    "  3          VIDEO :\n"
                    "  4             VR :\n"
                    "  5        COMPUTE :\n"
                    "  6         CUSTOM :\n"
                    "  8 WINDOW_3D :")
        w(f"{dev}/pp_power_profile_mode", prof)
        w(f"{dev}/power_dpm_force_performance_level", "auto\n")
    if i == 7 and S == "desktop-sysfs":
        w(f"{dev}/pp_power_profile_mode", "nothing useful\n")
w("/sys/module/pcie_aspm/parameters/policy", "[default] performance powersave powersupersave\n")

# ---------------------------------------------------------------- /sys: storage
for h in range(6):
    w(f"/sys/class/scsi_host/host{h}/link_power_management_policy", "med_power_with_dipm\n")
for n in range(2):
    w(f"/sys/block/nvme{n}n1/device/power/autosuspend_delay_ms", "1000\n")
    w(f"/sys/block/nvme{n}n1/device/power/control", "auto\n")
d("/sys/block/nvme9n1/device")  # no power dir: skipped

if laptop:
    w("/sys/class/power_supply/BAT0/capacity", "80\n")

# ---------------------------------------------------------------- /proc
# kernel threads, system services, the session, then the game tree.
GAME_CG = "/user.slice/user-1000.slice/user@1000.service/app.slice/app-steam@autostart.service"
LIMITS_TMPL = """Limit                     Soft Limit           Hard Limit           Units
Max cpu time              unlimited            unlimited            seconds
Max file size             unlimited            unlimited            bytes
Max data size             unlimited            unlimited            bytes
Max stack size            8388608              unlimited            bytes
Max core file size        unlimited            unlimited            bytes
Max resident set          unlimited            unlimited            bytes
Max processes             126435               126435               processes
Max open files            524288               524288               files
Max locked memory         8388608              8388608              bytes
Max address space         unlimited            unlimited            bytes
Max file locks            unlimited            unlimited            locks
Max pending signals       126435               126435               signals
Max msgqueue size         819200               819200               bytes
Max nice priority         {nice:<21}{nice:<21}
Max realtime priority     0                    0
Max realtime timeout      unlimited            unlimited            us
"""

cgroups_made = set()
children = {}  # ppid -> [pid], for task/TID/children (written at the end)
comms = {}  # pid -> comm, for the canned `pgrep -lx` answer
procs_tids = {}


def stat_line(pid, comm, ppid, policy=0, threads=1):
    f = ["S", str(ppid), str(pid), str(pid), "0", "-1", "4194560", "1234", "0", "12", "0",
         "100", "50", "0", "0", "20", "0", str(threads), "0", "123456", "1234567", "2345",
         "18446744073709551615", "1", "1", "0", "0", "0", "0", "0", "4096", "0", "0", "0",
         "0", "17", "3", "0", str(policy), "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"]  # policy = field 41
    return f"{pid} ({comm}) " + " ".join(f) + "\n"


def proc(pid, ppid, comm, cmdline, cg="/system.slice", nice=0, threads=None, kthread=False,
         thread_names=None):
    base = f"/proc/{pid}"
    tids = threads or [pid]
    children.setdefault(ppid, []).append(pid)
    comms[pid] = comm[:15]
    procs_tids[pid] = tids
    w(base + "/stat", stat_line(pid, comm, ppid, threads=len(tids)))
    w(base + "/comm", comm[:15] + "\n")
    w(base + "/cmdline", b"" if kthread else b"\0".join(x.encode() for x in cmdline) + b"\0")
    w(base + "/cgroup", "0::/\n" if kthread else f"0::{cg}\n")
    w(base + "/limits", LIMITS_TMPL.format(nice=nice))
    for k, t in enumerate(tids):
        tn = (thread_names[k] if thread_names and k < len(thread_names) else comm)[:15]
        tb = f"{base}/task/{t}"
        pol = 1 if (S.startswith("render-busy") and thread_names and k == 13) else 0  # one SCHED_FIFO thread ("Job 4")
        w(tb + "/stat", stat_line(t, tn, ppid, policy=pol, threads=len(tids)))
        w(tb + "/comm", tn + "\n")
        w(tb + "/schedstat", f"{1000000 * (k + 1)} 2000 {k}\n")
        w(tb + "/timerslack_ns", "50000\n")
    if not kthread and cg not in cgroups_made and cg != "/":
        cgroups_made.add(cg)
        if "noweight" not in cg:
            w(f"/sys/fs/cgroup{cg}/cpu.weight", "100\n")
        else:
            d(f"/sys/fs/cgroup{cg}")


nextpid = [10]


def newpid(step=1):
    nextpid[0] += step
    return nextpid[0]


proc(1, 0, "systemd", ["/run/current-system/systemd/lib/systemd/systemd"], cg="/init.scope")
proc(2, 0, "kthreadd", [], kthread=True)
n_k = a.procs * 3 // 10
for i in range(n_k):
    proc(newpid(), 2, f"kworker/{i % 32}:{i // 32}-events", [], kthread=True)
n_sys = a.procs * 2 // 10
for i in range(n_sys):
    proc(newpid(), 1, f"svc{i}", [f"/nix/store/xxx-svc{i}/bin/svc{i}", "--daemon"],
         cg=f"/system.slice/svc{i}.service")
# user session
plasma = newpid(7)
proc(plasma, 1, "plasmashell", ["/run/current-system/sw/bin/plasmashell", "--no-respawn"],
     cg="/user.slice/user-1000.slice/user@1000.service/session.slice/plasma-plasmashell.service",
     threads=list(range(plasma, plasma + 1)) + [plasma + 1 + k for k in range(30)])
nextpid[0] = plasma + 40
n_user = a.procs - n_k - n_sys - 40
for i in range(n_user):
    pid = newpid()
    proc(pid, plasma if i % 2 else 1, f"app{i}", [f"/usr/bin/app{i}", "--arg", f"x{i}"],
         cg=f"/user.slice/user-1000.slice/user@1000.service/app.slice/app-{i % 20}.scope")

# game tree
nextpid[0] = 30000
steam = newpid()
proc(steam, 1, "steam", ["/home/u/.local/share/Steam/ubuntu12_32/steam", "-srt-logger-opened"],
     cg=GAME_CG, threads=[steam] + [steam + 1 + k for k in range(20)])
nextpid[0] = steam + 30
reaper = newpid()
proc(reaper, steam, "reaper",
     ["/home/u/.local/share/Steam/ubuntu12_32/reaper", "SteamLaunch", "AppId=1091500", "--",
      "/home/u/.local/share/Steam/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point"],
     cg=GAME_CG)
adverb = newpid()
proc(adverb, reaper, "pv-adverb", ["/usr/lib/pressure-vessel/from-host/bin/pv-adverb", "--"],
     cg=GAME_CG, threads=[adverb, adverb + 1])
nextpid[0] += 1
python = newpid()
proc(python, adverb, "python3", ["python3", "/home/u/.steam/root/compatibilitytools.d/proton",
                                  "waitforexitandrun", "Z:/game/Cyberpunk2077.exe"], cg=GAME_CG)
wserver = newpid()
proc(wserver, 1, "wineserver", ["/files/bin/wineserver"], cg=GAME_CG, nice=31,
     threads=[wserver, wserver + 1])
nextpid[0] += 1
wine_nice = 31 if S != "desktop-sysfs" else 0
# winedevice.exe only where the scenario wants exit.sh to see one
wd = "winedevice.exe" if S in ("desktop-sysfs", "reentry", "laptop-ac", "powerplay-ppd-refused") else "winedevic2.exe"
for nm in ("services.exe", wd, wd, "plugplay.exe", "explorer.exe",
           "rpcss.exe", "svchost.exe"):
    pid = newpid()
    proc(pid, python, nm, [f"C:\\windows\\system32\\{nm}"], cg=GAME_CG, nice=wine_nice,
         threads=[pid] + [pid + 1 + k for k in range(5)])
    nextpid[0] = pid + 6
game = newpid()
tn = ["Cyberpunk2077.e", "RenderThread 0", "dxvk-submit", "dxvk-queue", "dxvk-frame",
      "TaskGraphThread", "WorkerThread", "Audio", "PhysX"]
if S == "render-busy-nopref":
    tn[1] = "MainLoop"  # no known render-thread name: the busiest thread wins
gthreads = [game + k for k in range(a.game_threads)]
tnames = tn + [f"dxvk-shader-{k}" if k % 3 == 0 else f"Job {k}" for k in range(a.game_threads)]
proc(game, python, "Cyberpunk2077.e", ["Z:\\game\\Cyberpunk2077.exe", "--launcher-skip"],
     cg=GAME_CG + ("" if S != "odd-procs" else "/noweight"), nice=wine_nice, threads=gthreads,
     thread_names=tnames)
nextpid[0] = game + a.game_threads + 5
crash = newpid()
proc(crash, game, "CrashReporter", ["Z:\\game\\CrashReporter.exe"], cg=GAME_CG, nice=wine_nice)
helper = newpid()
proc(helper, reaper, "srt-bwrap", ["/usr/lib/pressure-vessel/srt-bwrap", "--args", "12"],
     cg="/user.slice/user-1000.slice/user@1000.service/app.slice/app-other.scope")
start_args = [reaper, game]

if odd:
    # comm with ") ", spaces, newline, glob characters; a process whose stat
    # vanished (no ppid); a native game reniced normally.
    o1 = newpid()
    proc(o1, game, "a) b) (c", ["weird) name"], cg=GAME_CG)
    o2 = newpid()
    proc(o2, game, "x\ny *", ["/Games/x.x86_64"], cg=GAME_CG + "/noweight")
    o3 = newpid()
    d(f"/proc/{o3}")
    w(f"/proc/{o3}/stat", "")  # gone while reading
    o4 = newpid()
    proc(o4, o2, "wine64-preloader", ["/opt/wine/bin/wine64-preloader", "x.exe"],
         cg=GAME_CG, nice="unlimited")
    o5 = newpid()
    proc(o5, o2, "wine", ["wine", "y.exe"], cg=GAME_CG, nice=20)
    start_args.append(999999)  # a PID that is already gone
    start_args.append(reaper)  # duplicate

pg = {"desktop-sysfs": "1234 gamescopereaper\\n2345 winedevice.exe",
      "desktop-ppd": "1234 gamescope-wl\\n1235 gamescopereaper",
      "reentry": "2345 winedevice.exe", "odd-procs": "",
      "laptop-battery": "1234 gamescopereaper", "laptop-ac": "2345 winedevice.exe",
      "powerplay-ppd-refused": "2345 winedevice.exe\\n2346 winedevice.exe"}.get(S, "")
exe_count = {"desktop-sysfs": "1", "reentry": "3", "laptop-ac": "1",
             "powerplay-ppd-refused": "2"}.get(S, "0")
# processes behind the canned `pgrep -lx` answer, so a /proc scan finds them
for entry in filter(None, pg.split("\\n")):
    pid_, nm = entry.split(" ", 1)
    proc(int(pid_), 1, nm, [f"C:\\windows\\system32\\{nm}" if nm.endswith(".exe") else f"/usr/bin/{nm}"],
         cg="/user.slice/user-1000.slice/user@1000.service/app.slice/app-gamescope.scope")
# what the real `pgrep -lx 'gamescope-wl|gamescopereaper|winedevice.exe'` prints here
pg = "\\n".join(f"{p_} {c_}" for p_, c_ in sorted(comms.items())
                 if c_ in ("gamescope-wl", "gamescopereaper") or
                 (len(c_) == 14 and c_.startswith("winedevice") and c_.endswith("exe")))

# task/TID/children: the kernel lists a process under the thread that forked
# it; here the main thread forked everything (same order as a /proc scan).
for pid, tids in procs_tids.items():
    for t in tids:
        kids = sorted(children.get(pid, []), key=str) if t == pid else []
        w(f"/proc/{pid}/task/{t}/children", "".join(f"{k} " for k in kids))

# ---------------------------------------------------------------- /run
d("/run/gameboost")
w("/run/gameboost/running.flag", f"pid={reaper}\nsince=1\nappid=1091500\ncmd=x\n")
if reentry:
    first_cpu = f"{cpu}/cpu0/cpufreq/scaling_governor"
    w("/run/gameboost/state",
      f"{first_cpu}=schedutil\n/sys/class/scsi_host/host0/link_power_management_policy=min_power\n\n")
    w("/run/gameboost/cups", "cups.socket\n")
if S in ("reentry", "laptop-ac"):
    w("/run/nixos-upgrade.deferred", "")

# ---------------------------------------------------------------- stub responses
resp = {}
resp["systemctl"] = [
    ("is-active --quiet power-profiles-daemon.service", "0" if ppd else "3", None),
    ("start gameboost-hold.service", "0" if hold_ok else "1", None),
    ("is-active cups.socket cups.service", "0" if "active" in cups else "3",
     "\\n".join(cups)),
    ("is-active --quiet gameboost.service", "0" if S != "laptop-ac" else "3", None),
]
resp["busctl"] = [("--system*get-property org.freedesktop.UPower.PowerProfiles*",
                   "0" if ppd else "1", f's "{ppd_driver}"' if ppd else None)]
resp["systemd-ac-power"] = [("*", "0" if on_ac else "1", None)]
resp["renice"] = [("*", "0", None)]
resp["ionice"] = [("-c2 -n0 -p * 999999*", "1", None), ("*", "0", None)]
if odd:
    resp["ionice"] = [("-c2 -n0 -p * *", "1", None), ("*", "0", None)]  # forces per-thread retry
resp["chrt"] = [("*", "0", None)]
resp["pgrep"] = [("-lx *", "0" if pg else "1", pg or None),
                 ("-fc *", "0" if exe_count != "0" else "1", exe_count)]
resp["killall"] = [("*", "0", None)]
for name, lines in resp.items():
    with open(f"{R}/resp_{name}.tmp", "w") as f:
        for pat, rc, out in lines:
            f.write(f"{pat}\t{rc}" + (f"\t{out}" if out is not None else "") + "\n")
os.makedirs(R + "/resp")
for name in resp:
    os.rename(f"{R}/resp_{name}.tmp", f"{R}/resp/{name}")

with open(R + "/args", "w") as f:
    f.write(" ".join(map(str, start_args)) + "\n")
env = []
if powerplay:
    env.append(f"GB_REJECT={pci}/0000:00:03.0/pp_power_profile_mode")
with open(R + "/env", "w") as f:
    f.write("".join(e + "\n" for e in env))
# sleep hook: bump the render thread's run time during the 3 s sample
# (render-busy: every game thread gets a different amount, a SCHED_FIFO job
# thread the most, so the pick depends on the policy check and on order)
if S.startswith("render-busy"):
    with open(R + "/sleep_hook", "w") as f:
        f.write(f"""#!/bin/bash
[ "$1" = 3 ] || exit 0
k=0
for f in /home/{game}/task/*/schedstat; do
    t=${{f%/schedstat}}; t=${{t##*/}}; k=$((t - {game}))
    read -r run rest < "$f"
    case $k in 13) add=2900000000 ;; 1) add=1800000000 ;; 20) add=2500000000 ;; *) add=$(( (k * 7919 % 97 + 1) * 15000000 )) ;; esac
    echo "$((run + add)) $rest" > "$f"
done
""")
    os.chmod(R + "/sleep_hook", 0o755)
else:
  with open(R + "/sleep_hook", "w") as f:
    f.write(f"""#!/bin/bash
[ "$1" = 3 ] || exit 0
for t in {game + 1} {game + 6} {game + 9}; do
    f=/home/{game}/task/$t/schedstat
    read -r run rest < "$f"
    echo "$((run + 2000000000)) $rest" > "$f"
done
""")
os.chmod(R + "/sleep_hook", 0o755)
