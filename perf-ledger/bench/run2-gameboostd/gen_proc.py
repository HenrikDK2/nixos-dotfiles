#!/usr/bin/env python3
"""Generate a deterministic fake /proc tree for the gameboostd harness.

  gen_proc.py OUTDIR

OUTDIR/desktop/  ~460 pid dirs: NixOS KDE desktop, Firefox, Steam idle,
                 Discord, shells, ~170 kernel threads (empty cmdline).
OUTDIR/gaming/   the same plus a running Proton game stack (reaper, proton,
                 pressure-vessel, wineserver, wine services, the game .exe).
Both also contain the alive event pids (100000+).
OUTDIR/events.txt  exec-event workload: "PID ALIVE COMM" per line. ALIVE=1:
                 a pid dir exists (process still running at check time).
                 COMM: name sent in a rename event for that pid ("-" = none).
Only `cmdline` is created: gameboostd reads nothing else per pid.
"""
import os
import random
import sys

rnd = random.Random(1234)
B32 = "0123456789abcdfghijklmnpqrsvwxyz"


def h():
    return "".join(rnd.choice(B32) for _ in range(32))


def store(name):
    return f"/nix/store/{h()}-{name}"


S = "/home/user/.local/share/Steam"


def desktop():
    p = []
    kt = ["kthreadd", "rcu_gp", "kworker/0:0H", "ksoftirqd/0", "migration/0"]
    p += [[]] * 170  # kernel threads
    p.append(["/run/current-system/systemd/lib/systemd/systemd", "--switched-root",
              "--system", "--deserialize=46"])
    sd = store("systemd-256.8")
    for b in ["systemd-journald", "systemd-udevd", "systemd-logind", "systemd-oomd",
              "systemd-resolved", "systemd-timesyncd", "systemd-machined"]:
        p.append([f"{sd}/lib/systemd/{b}"])
    p.append([f"{sd}/lib/systemd/systemd", "--user"])
    p.append(["(sd-pam)"])
    dbus = store("dbus-1.14.10")
    p.append([f"{dbus}/bin/dbus-daemon", "--system", "--address=systemd:", "--nofork",
              "--nopidfile", "--systemd-activation", "--syslog-only"])
    p.append([f"{dbus}/bin/dbus-daemon", "--session", "--address=systemd:", "--nofork",
              "--nopidfile", "--systemd-activation", "--syslog-only"])
    for n, a in [("networkmanager-1.48.10/bin/NetworkManager", ["--no-daemon"]),
                 ("polkit-125/lib/polkit-1/polkitd", ["--no-debug"]),
                 ("rtkit-0.13/libexec/rtkit-daemon", []),
                 ("power-profiles-daemon-0.23/libexec/power-profiles-daemon", []),
                 ("upower-1.90.6/libexec/upowerd", []),
                 ("udisks-2.10.1/libexec/udisks2/udisksd", []),
                 ("nix-2.24.10/bin/nix-daemon", ["--daemon"]),
                 ("openssh-9.9p1/bin/sshd", ["-D", "-f", "/etc/ssh/sshd_config"]),
                 ("bluez-5.78/libexec/bluetooth/bluetoothd", ["-f", "/etc/bluetooth/main.conf"]),
                 ("wpa_supplicant-2.11/bin/wpa_supplicant", ["-u"]),
                 ("cups-2.4.11/bin/cupsd", ["-l"]),
                 ("avahi-0.8/sbin/avahi-daemon", ["--syslog"]),
                 ("pipewire-1.2.6/bin/pipewire", []),
                 ("wireplumber-0.5.6/bin/wireplumber", []),
                 ("pipewire-1.2.6/bin/pipewire-pulse", []),
                 ("plasma-workspace-6.2.3/bin/plasmashell", ["--no-respawn"]),
                 ("plasma-workspace-6.2.3/bin/ksmserver", []),
                 ("kded-6.8.0/bin/kded6", []),
                 ("kwin-6.2.3/bin/kwin_wayland", ["--wayland-fd", "7", "--socket", "wayland-0",
                                                  "--xwayland-fd", "8", "--xwayland-fd", "9",
                                                  "--xwayland-display", ":0", "--xwayland-xauthority",
                                                  "/run/user/1000/xauth_ZkPqRv", "--xwayland"]),
                 ("xwayland-24.1.4/bin/Xwayland", [":0", "-auth", "/run/user/1000/xauth_ZkPqRv",
                                                   "-displayfd", "6", "-listenfd", "7", "-wm", "9",
                                                   "-rootless", "-enable-ei-portal"]),
                 ("baloo-6.8.0/libexec/baloo_file", []),
                 ("xdg-desktop-portal-1.18.4/libexec/xdg-desktop-portal", []),
                 ("xdg-desktop-portal-kde-6.2.3/libexec/xdg-desktop-portal-kde", []),
                 ("kactivitymanagerd-6.2.3/libexec/kactivitymanagerd", []),
                 ("polkit-kde-agent-6.2.3/libexec/polkit-kde-authentication-agent-1", []),
                 ("konsole-24.08.3/bin/konsole", []),
                 ("dolphin-24.08.3/bin/dolphin", ["--daemon"]),
                 ("kdeconnect-24.08.3/libexec/kdeconnectd", []),
                 ("gvfs-1.56.1/libexec/gvfsd", []),
                 ("at-spi2-core-2.54.0/libexec/at-spi-bus-launcher", []),
                 ("gameboost/libexec/gameboost/gameboostd", ["-m", "x", "-x", "y", "-d", "/nix/store/x"])]:
        p.append([store(n.split("/")[0]) + "/" + "/".join(n.split("/")[1:])] + a)
    for i in range(12):
        p.append([store("agetty-2.40") + "/bin/agetty", "--login-program",
                  store("shadow-4.16") + "/bin/login", "--noclear", "--keep-baud",
                  f"tty{i+1}", "115200,38400,9600", "linux"]) if i < 2 else \
            p.append([store("bash-interactive-5.2p37") + "/bin/bash"])
    for i in range(8):
        p.append([store("fish-3.7.1") + "/bin/fish"])
    # Firefox: main + content processes
    ff = store("firefox-132.0.1") + "/lib/firefox/firefox"
    ffu = store("firefox-unwrapped-132.0.1")
    p.append([ff, "--name", "firefox"])
    for i in range(14):
        p.append([ff, "-contentproc", "-childID", str(i + 1), "-isForBrowser", "-prefsLen",
                  "31336", "-prefMapSize", "244787", "-jsInitLen", "231800", "-parentBuildID",
                  "20241104190000", "-greomni", f"{ffu}/lib/firefox/omni.ja", "-appomni",
                  f"{ffu}/lib/firefox/browser/omni.ja", "-appDir", f"{ffu}/lib/firefox/browser",
                  "{8a3c0c14-2b4a-4a7e-9c35-1f1e2d6c9b20}", "2481", "true", "tab"])
    for t in ["socket", "rdd", "utility"]:
        p.append([ff, "-contentproc", "-parentBuildID", "20241104190000", "-prefsLen", "31336",
                  "-prefMapSize", "244787", "-appDir", f"{ffu}/lib/firefox/browser",
                  "{f2c1...}", "2481", "true", t])
    # Steam (idle): client, webhelpers with very long cmdlines
    rt = f"{S}/ubuntu12_64"
    p.append([store("steam-1.0.0.81") + "/bin/steam", "-silent"])
    p.append([f"{S}/ubuntu12_32/steam", "-silent", "-srt-logger-opened"])
    p.append([f"{S}/ubuntu12_32/steam-runtime/amd64/usr/bin/steam-runtime-supervisor",
              "--exit-with-parent", "--subreaper"])
    feat = ("--enable-features=PlatformHEVCDecoderSupport,ProcessPerSiteUpToMainFrameThreshold,"
            "SharedArrayBuffer,WebRtcAllowInputVolumeAdjustment")
    dfeat = ("--disable-features=SpareRendererForSitePerProcess,DcheckIsFatal,"
             "BackForwardCache,CalculateNativeWinOcclusion,HardwareMediaKeyHandling")
    for t in ["", "--type=zygote", "--type=gpu-process", "--type=utility", "--type=renderer",
              "--type=renderer", "--type=renderer", "--type=renderer"]:
        a = [f"{rt}/steamwebhelper", "-lang=en_US", f"-cachedir={S}/config/htmlcache",
             "-steampid=4211", "-buildid=1730853309", "-steamid=0", f"-logdir={S}/logs",
             "-uimode=7", "-startcount=0", "-steamuniverse=Public", "-realm=Global",
             f"-clientui={S}/clientui", f"-steampath={S}/ubuntu12_32/steam", "-launcher=0",
             "-use_xcomposite=1", "-no-restart-on-ui-mode-change", "--valve-initial-incognito-dark-mode",
             "--valve-enable-site-isolation", "--enable-smooth-scrolling", "--password-store=basic",
             "--log-file=/home/user/.local/share/Steam/logs/cef_log.txt", "--disable-quick-menu",
             feat, dfeat, "--lang=en-US", "--no-sandbox"]
        if t:
            a.insert(1, t)
        p.append(a)
    # Discord (electron): long lines
    dc = store("discord-0.0.75") + "/opt/Discord/.Discord-wrapped"
    for t in ["", "--type=zygote", "--type=gpu-process", "--type=utility", "--type=renderer"]:
        p.append([dc] + ([t] if t else []) + ["--ozone-platform-hint=auto",
                 "--enable-wayland-ime", "--enable-crash-reporter=6dbe6e23-1e2b-4b2a,no_channel",
                 "--user-data-dir=/home/user/.config/discord", "--standard-schemes=sentry-ipc",
                 "--secure-schemes=disclip,sentry-ipc", "--bypasscsp-schemes=sentry-ipc",
                 "--cors-schemes=sentry-ipc", "--fetch-schemes=disclip,sentry-ipc",
                 "--app-path=/nix/store/abc-discord/opt/Discord/resources/app.asar",
                 "--enable-sandbox", "--field-trial-handle=3,i,1234567890,987654321,262144",
                 "--variations-seed-version"])
    # Misc user apps and helpers
    for n in ["kwalletd6", "kscreen_backend_launcher", "org_kde_powerdevil", "ksecretd",
              "kaccess", "xembedsniproxy", "gmenudbusmenuproxy", "kclockd", "DiscoverNotifier",
              "plasma-browser-integration-host", "kioworker", "obexd", "akonadi_control",
              "kalendarac", "ibus-daemon", "fcitx5", "easyeffects", "mpris-proxy"]:
        p.append([store(n.lower() + "-6.2.3") + "/bin/" + n])
    # More idle shell/user processes to reach ~460
    while len(p) < 455:
        p.append([store("coreutils-9.5") + "/bin/sleep", "infinity"])
    # a couple of processes with newlines / odd chars in argv
    p.append(["python3", "-c", "import time\nwhile True:\n    time.sleep(60)\n"])
    p.append(["/bin/sh", "-c", "while :; do sleep 30; done"])
    return p


def game_stack():
    g = f"{S}/steamapps/common/ELDEN RING/Game"
    pr = f"{S}/steamapps/common/Proton 9.0 (Beta)"
    pfx = f"{S}/steamapps/compatdata/1245620/pfx"
    sn = f"{S}/steamapps/common/SteamLinuxRuntime_sniper"
    p = []
    p.append([f"{S}/ubuntu12_32/reaper", "SteamLaunch", "AppId=1245620", "--",
              f"{S}/ubuntu12_32/steam-launch-wrapper", "--", f"{sn}/_v2-entry-point",
              "--verb=waitforexitandrun", "--", f"{pr}/proton", "waitforexitandrun",
              f"{g}/start_protected_game.exe"])
    p.append([f"{S}/ubuntu12_32/steam-launch-wrapper", "--", f"{sn}/_v2-entry-point",
              "--verb=waitforexitandrun", "--", f"{pr}/proton", "waitforexitandrun",
              f"{g}/start_protected_game.exe"])
    p.append([f"{sn}/pressure-vessel/bin/pressure-vessel-wrap", "--batch", "--filesystem=/home/user",
              "--", f"{pr}/proton", "waitforexitandrun", f"{g}/start_protected_game.exe"])
    p.append([f"{sn}/pressure-vessel/libexec/steam-runtime-tools-0/srt-bwrap", "--args", "37",
              "--", f"{pr}/proton", "waitforexitandrun"])
    p.append(["python3", f"{pr}/proton", "waitforexitandrun", f"{g}/start_protected_game.exe"])
    p.append([f"{pr}/files/bin/wineserver"])
    for w in ["services.exe", "winedevice.exe", "winedevice.exe", "plugplay.exe", "svchost.exe -k LocalServiceNetworkRestricted",
              "explorer.exe /desktop", "rpcss.exe", "tabtip.exe", "conhost.exe --unix --width 80 --height 25"]:
        p.append([f"C:\\windows\\system32\\{w}"])
    p.append(["Z:\\home\\user\\.local\\share\\Steam\\steamapps\\common\\ELDEN RING\\Game\\eldenring.exe"])
    p.append([f"{g}/../../../../steamapps/common/Proton 9.0 (Beta)/files/bin/wine64-preloader",
              f"{pr}/files/bin/wine64", "c:\\windows\\system32\\steam.exe", f"{g}/start_protected_game.exe"])
    return p


def exec_events():
    """Typical exec events: mostly short-lived tools (gone by check time),
    some still-running programs, a few Wine starts."""
    cu = store("coreutils-9.5")
    git = store("git-2.47.0")
    short = [
        [f"{cu}/bin/cat", "/sys/class/power_supply/BAT0/capacity"],
        [f"{cu}/bin/sleep", "1"],
        [store("gnugrep-3.11") + "/bin/grep", "-q", "--", "foo", "/etc/passwd"],
        [store("gnused-4.9") + "/bin/sed", "-e", "s/a/b/g"],
        [f"{git}/bin/git", "status", "--porcelain=v2", "--branch"],
        [f"{git}/libexec/git-core/git", "rev-parse", "--show-toplevel"],
        [store("gcc-13.3.0") + "/bin/gcc", "-O2", "-c", "-o", "foo.o", "foo.c"],
        [store("gcc-13.3.0") + "/libexec/gcc/x86_64-unknown-linux-gnu/13.3.0/cc1", "-quiet",
         "foo.c", "-quiet", "-dumpbase", "foo.c", "-mtune=generic", "-march=x86-64", "-O2",
         "-o", "/tmp/ccXyZ.s"],
        [store("binutils-2.43.1") + "/bin/as", "--64", "-o", "foo.o", "/tmp/ccXyZ.s"],
        [store("bash-5.2p37") + "/bin/bash", "-c", "echo hi"],
        [store("procps-4.0.4") + "/bin/pgrep", "-x", "steam"],
        [store("systemd-256.8") + "/bin/systemctl", "--user", "is-active", "foo.service"],
        [store("nix-2.24.10") + "/bin/nix", "eval", "--raw", ".#foo"],
        ["/run/current-system/sw/bin/fish", "-c", "fish_prompt"],
    ]
    alive = [
        [store("firefox-132.0.1") + "/lib/firefox/firefox", "-contentproc", "-childID", "33",
         "-isForBrowser", "-prefsLen", "31336", "-prefMapSize", "244787", "tab"],
        [store("konsole-24.08.3") + "/bin/konsole"],
        [store("zed-editor-0.161.2") + "/bin/zed", "--foreground"],
        [f"{S}/ubuntu12_64/steamwebhelper", "--type=renderer", "-lang=en_US",
         f"-cachedir={S}/config/htmlcache", "-steampid=4211", "--no-sandbox"],
        [store("kio-6.8.0") + "/libexec/kf6/kioworker", "/nix/store/x/lib/plugins/kf6/kio/file.so",
         "file", "", "local:/run/user/1000/dolphinXYZ.1.kioworker.socket"],
    ]
    wine = [
        [f"{S}/steamapps/common/Proton 9.0 (Beta)/files/bin/wine64-preloader",
         f"{S}/steamapps/common/Proton 9.0 (Beta)/files/bin/wine64", "C:\\windows\\system32\\steam.exe"],
        [store("wine-wow-9.20") + "/bin/wine64", "/home/user/Downloads/tool.exe"],
    ]
    ev = []
    pid = 100000
    for i in range(300):
        r = rnd.random()
        if r < 0.70:
            ev.append((pid, 0, rnd.choice(short), "-"))
        elif r < 0.97:
            ev.append((pid, 1, rnd.choice(alive), "-"))
        else:
            ev.append((pid, 1, rnd.choice(wine), "steam.exe"))
        pid += 1
    return ev


def write_tree(root, procs, events):
    os.makedirs(root, exist_ok=True)
    pid = 1
    for argv in procs:
        d = os.path.join(root, str(pid))
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "cmdline"), "wb") as f:
            f.write(b"".join(a.encode() + b"\0" for a in argv))
        pid += rnd.randint(1, 37)
    for p, alive, argv, _ in events:
        if alive:
            d = os.path.join(root, str(p))
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "cmdline"), "wb") as f:
                f.write(b"".join(a.encode() + b"\0" for a in argv))
    # non-pid entries like the real /proc
    for n in ["self", "sys", "net", "meminfo", "1x"]:
        os.makedirs(os.path.join(root, n), exist_ok=True)


def main():
    out = sys.argv[1]
    d = desktop()
    g = game_stack()
    ev = exec_events()
    write_tree(os.path.join(out, "desktop"), d, ev)
    rnd.seed(99)
    write_tree(os.path.join(out, "gaming"), d[:-len(g) - 2] + g + d[-2:], ev)
    with open(os.path.join(out, "events.txt"), "w") as f:
        for p, alive, _, comm in ev:
            f.write(f"{p} {alive} {comm}\n")


main()
