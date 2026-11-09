#!/usr/bin/env python3
"""Generate a fake root (proc/, sys/, run/) for GameBoost's start.sh/exit.sh.

usage: genroot.py ROOT [--laptop] [--ncpu N] [--nproc N] [--game-threads N]
                       [--npci N] [--x3d]

Deterministic: same arguments -> byte-identical tree.
"""
import argparse
import os
import random

ap = argparse.ArgumentParser()
ap.add_argument("root")
ap.add_argument("--laptop", action="store_true")
ap.add_argument("--ncpu", type=int, default=32)
ap.add_argument("--nproc", type=int, default=500)
ap.add_argument("--game-threads", type=int, default=200)
ap.add_argument("--npci", type=int, default=40)
ap.add_argument("--x3d", action="store_true")
ap.add_argument("--no-children", action="store_true",
                help="no /proc/*/task/*/children files (CONFIG_PROC_CHILDREN=n)")
ap.add_argument("--powerplay", action="store_true",
                help="GPU profile file in powerplay format")
a = ap.parse_args()
rng = random.Random(1234)
R = a.root


def w(path, data, mode=0o644):
    p = os.path.join(R, path.lstrip("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(data.encode() if isinstance(data, str) else data)
    os.chmod(p, mode)


def d(path):
    os.makedirs(os.path.join(R, path.lstrip("/")), exist_ok=True)


LIMITS_HDR = "Limit                     Soft Limit           Hard Limit           Units     \n"


def limits(nice):
    rows = [
        ("Max cpu time", "unlimited", "unlimited", "seconds"),
        ("Max file size", "unlimited", "unlimited", "bytes"),
        ("Max data size", "unlimited", "unlimited", "bytes"),
        ("Max stack size", "8388608", "unlimited", "bytes"),
        ("Max core file size", "unlimited", "unlimited", "bytes"),
        ("Max resident set", "unlimited", "unlimited", "bytes"),
        ("Max processes", "127301", "127301", "processes"),
        ("Max open files", "1024", "524288", "files"),
        ("Max locked memory", "8388608", "8388608", "bytes"),
        ("Max address space", "unlimited", "unlimited", "bytes"),
        ("Max file locks", "unlimited", "unlimited", "locks"),
        ("Max pending signals", "127301", "127301", "signals"),
        ("Max msgqueue size", "819200", "819200", "bytes"),
        ("Max nice priority", str(nice), str(nice), ""),
        ("Max realtime priority", "0", "0", ""),
        ("Max realtime timeout", "unlimited", "unlimited", "us"),
    ]
    s = LIMITS_HDR
    for n, so, h, u in rows:
        s += f"{n:<26}{so:<21}{h:<21}{u:<10}\n"
    return s


def statline(pid, comm, ppid, policy=0, state="S"):
    # fields 3..52 (f[0] = field 3 = state, f[1] = ppid, f[38] = field 41 = policy)
    f = [str(rng.randint(0, 10**7)) for _ in range(50)]
    f[0] = state
    f[1] = str(ppid)
    f[2] = f[3] = str(pid)
    f[4] = "0"
    f[5] = "-1"
    f[15] = "20"
    f[16] = "0"
    f[20] = str(rng.randint(10**6, 10**12))
    f[21] = "18446744073709551615"
    f[36] = str(rng.randint(0, a.ncpu - 1))
    f[37] = "0"
    f[38] = str(policy)
    return f"{pid} ({comm}) " + " ".join(f) + "\n"


procs = []  # (pid, ppid, comm, argv list, cgroup, nice_limit, threads[(tid, comm)])


def add(pid, ppid, comm, argv, cg, nice=0, threads=None):
    procs.append((pid, ppid, comm, argv, cg, nice, threads or []))


SYS_CG = "/system.slice/"
USER_CG = "/user.slice/user-1000.slice/user@1000.service/app.slice/"
GAME_CG = USER_CG + "app-steam@autostart.service"
NOCPU_CG = USER_CG + "app-pv.scope"   # no cpu.weight -> warning path

add(1, 0, "systemd", ["/run/current-system/systemd/lib/systemd/systemd"], "/init.scope")
add(2, 0, "kthreadd", [], "/")
pid = 3
# kernel threads
nk = a.nproc // 2
for i in range(nk):
    add(pid, 2, rng.choice(["kworker/%d:1" % (i % a.ncpu), "ksoftirqd/%d" % (i % a.ncpu),
                            "migration/%d" % (i % a.ncpu), "rcu_preempt", "kswapd0",
                            "irq/%d-amdgpu" % i]), [], "/")
    pid += 1
# odd names
add(pid, 1, "a) b) c", ["/bin/odd"], SYS_CG + "odd.service"); pid += 1
add(pid, 1, "new\nline", ["/bin/nl"], SYS_CG + "nl.service"); pid += 1
add(pid, 1, "glob*[x]", ["/bin/gl"], SYS_CG + "gl.service"); pid += 1
add(pid, 1, "sp ace", ["/bin/sp"], SYS_CG + "sp.service"); pid += 1
# user processes
while pid < 3000:
    if len(procs) >= a.nproc - 12:
        break
    par = 1 if rng.random() < 0.5 else rng.choice([p[0] for p in procs if p[0] > 2 and p[1] != 2] or [1])
    nm = rng.choice(["plasmashell", "kwin_wayland", "pipewire", "bash", "fish", "firefox",
                     "Isolated Web Co", "dbus-broker", "systemd-journal", "Xwayland",
                     "kded6", "baloo_file", "konsole", "zed-editor", "sshd"])
    add(pid, par, nm, ["/run/current-system/sw/bin/" + nm, "--arg"],
        USER_CG + "app-%s.scope" % nm.split()[0])
    pid += 1

STEAM = 3000
add(STEAM, 1, "steam", ["/home/u/.local/share/Steam/ubuntu12_32/steam", "-silent"], GAME_CG,
    threads=[(3000 + 1000 + i, "steam") for i in range(1, 6)])
REAPER = 5000
add(REAPER, STEAM, "reaper",
    ["/home/u/.local/share/Steam/ubuntu12_32/reaper", "SteamLaunch", "AppId=1234", "--",
     "/home/u/.local/share/Steam/steamapps/common/Proton/proton", "waitforexitandrun",
     "C:\\Game\\game.exe"], GAME_CG)
add(5001, REAPER, "pv-adverb", ["/sr/pressure-vessel/bin/pv-adverb", "--"], NOCPU_CG,
    threads=[(5101, "pv-adverb")])
add(5002, 5001, "python3", ["python3", "/home/u/.../proton", "waitforexitandrun"], GAME_CG,
    threads=[(5102, "python3")])
add(5003, 5002, "wineserver", ["/x/files/bin/wineserver"], GAME_CG, nice=31,
    threads=[(5103, "wineserver")])
add(5004, 5002, "winedevice.exe", ["C:\\windows\\system32\\winedevice.exe"], GAME_CG, nice=31,
    threads=[(5200 + i, "winedevice.exe") for i in range(8)])
add(5005, 5002, "explorer.exe", ["C:\\windows\\system32\\explorer.exe", "/desktop"], GAME_CG,
    nice=31, threads=[(5300 + i, "explorer.exe") for i in range(5)])
gthreads = []
names = ["game.exe", "RenderThread 0", "RHIThread", "dxvk-submit", "dxvk-queue",
         "dxvk-shader-0", "TaskGraphThread", "Worker 1", "AudioThread", "PoolThread"]
for i in range(a.game_threads - 1):
    gthreads.append((6000 + i, names[i % len(names)] if i < 40 else "game.exe"))
add(5010, 5002, "game.exe", ["C:\\Game\\game.exe", "-dx12"], GAME_CG, nice=31, threads=gthreads)
add(5011, 5002, "wine64", ["/x/files/bin/wine64", "c:\\windows\\system32\\services.exe"], GAME_CG,
    nice=0, threads=[(5400, "services.exe")])
add(5012, 5010, "crashpad", ["/home/u/game/crashpad_handler"], GAME_CG, nice=0,
    threads=[(5401, "crashpad")])
# a later-spawned grandchild
add(5013, 5012, "helper", ["/home/u/game/helper"], GAME_CG, nice=0)
# children whose numeric and string order differ
add(10001, 5002, "dxvk-cache", ["/x/dxvk-cache-tool"], GAME_CG, nice=0)
add(600000, 5002, "steam-runtime", ["/x/srt-launcher"], GAME_CG, nice=0)
add(600001, 10001, "zombie", [], GAME_CG, nice=0)

# children files: by default listed under the parent's main thread; some
# under another thread (forked by it). Kernel order = fork order (numeric).
FORKED_BY = {5012: 6003, 600000: 5102}   # child -> forking thread of parent
CHILDREN = {}
pinfo = {p[0]: p for p in procs}
for (pid_, ppid_, *_rest) in procs:
    if ppid_ in pinfo:
        t = FORKED_BY.get(pid_, ppid_)
        CHILDREN.setdefault((ppid_, t), []).append(pid_)

for (pid, ppid, comm, argv, cg, nice, threads) in procs:
    base = f"/proc/{pid}"
    w(base + "/stat", statline(pid, comm, ppid))
    w(base + "/comm", comm + "\n")
    w(base + "/cmdline", "".join(x + "\0" for x in argv))
    w(base + "/cgroup", f"0::{cg}\n")
    w(base + "/limits", limits(nice))
    w(base + "/timerslack_ns", "50000\n")
    for tid, tcomm in [(pid, comm)] + threads:
        tb = f"{base}/task/{tid}"
        w(tb + "/stat", statline(tid, tcomm, ppid))
        w(tb + "/comm", tcomm + "\n")
        if not a.no_children:
            w(tb + "/children", "".join(f"{c} " for c in sorted(CHILDREN.get((pid, tid), []))))
        w(tb + "/schedstat", f"{rng.randint(10**6, 10**10)} {rng.randint(0, 10**8)} {rng.randint(0, 9000)}\n")

# cgroup weights
for cg in sorted({p[4] for p in procs}):
    if cg == NOCPU_CG:
        d("/sys/fs/cgroup" + cg)
        continue
    w("/sys/fs/cgroup" + cg + "/cpu.weight", "100\n")

# CPUs
cpu = "/sys/devices/system/cpu"
d(cpu + "/cpuidle")
d(cpu + "/cpufreq/policy0")
w(cpu + "/amd_pstate/status", "active\n")
for i in range(a.ncpu):
    c = f"{cpu}/cpu{i}/cpufreq"
    w(c + "/scaling_governor", "powersave\n")
    w(c + "/energy_performance_preference", "balance_performance\n")
    w(c + "/scaling_available_governors", "performance powersave\n")
    w(c + "/boost", "1\n")
if a.x3d:
    w("/sys/bus/platform/drivers/amd_x3d_vcache/AMDI0101:00/amd_x3d_mode", "frequency\n")

# PCI
for i in range(a.npci):
    dev = f"/sys/bus/pci/devices/0000:{i // 8:02x}:{i % 8:02x}.0"
    cls = "0x060400\n"
    if i == 17:
        cls = "0x030000\n"
        if a.powerplay:
            prof = ("NUM        MODE_NAME     SCLK_UP_HYST   SCLK_DOWN_HYST SCLK_ACTIVE_LEVEL     MCLK_UP_HYST   MCLK_DOWN_HYST MCLK_ACTIVE_LEVEL\n"
                    "  0   BOOTUP_DEFAULT:        -              -              -              -              -              -\n"
                    "  1 3D_FULL_SCREEN *:        0            100             30              0            100             10\n"
                    "  2     POWER_SAVING:       10              0             30              -              -              -\n")
        else:
            prof = "PROFILE_INDEX(NAME) CLOCK_TYPE(NAME) FPS MinActiveFreqType MinActiveFreq BoosterFreqType BoosterFreq PD_Data_limit_c PD_Data_error_coeff PD_Data_error_rate_coeff\n"
            for j, nm in enumerate(["BOOTUP_DEFAULT*", "3D_FULL_SCREEN", "POWER_SAVING", "VIDEO",
                                    "VR", "COMPUTE", "CUSTOM", "WINDOW_3D"]):
                prof += f" {j} {nm:<15}:\n"
                for ck in ["GFXCLK", "FCLK"]:
                    prof += f"                     0({ck:>13})       0       5       1       0       4     800 4587520  -65536       0\n"
        w(dev + "/pp_power_profile_mode", prof)
        w(dev + "/power_dpm_force_performance_level", "auto\n")
    elif i == 30:
        cls = "0x030200\n"   # 3D controller without AMD files
    elif i == 9:
        cls = "0x010802\n"
    w(dev + "/class", cls)
    w(dev + "/power/control", "auto\n")
w("/sys/module/pcie_aspm/parameters/policy", "[default] performance powersave powersupersave\n")

for i in range(6):
    w(f"/sys/class/scsi_host/host{i}/link_power_management_policy", "med_power_with_dipm\n")
for n in range(2):
    w(f"/sys/block/nvme{n}n1/device/power/autosuspend_delay_ms", "100\n")
    w(f"/sys/block/nvme{n}n1/device/power/control", "auto\n")
d("/sys/block/sda/device")  # no power dir glob miss is fine

w("/sys/kernel/sched_ext/state", "disabled\n")
w("/sys/kernel/debug/sched/base_slice_ns", "3000000\n")
d("/sys/class/power_supply/AC")
if a.laptop:
    d("/sys/class/power_supply/BAT0")
if not a.no_children:
    w("/proc/thread-self/children", "")
d("/run/gameboost")
w("/run/gameboost/running.flag", "pid=5000\nsince=1\nappid=1234\ncmd=x\n")
