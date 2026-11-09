#!/usr/bin/env python3
"""Deterministic synthetic corpus of command lines as seen on a NixOS + KDE
Plasma + Steam/Proton desktop. Output: one argv per line, arguments joined by
\\x1f (so arguments may contain spaces). Usage: gen_corpus.py [N] [SEED] [mix|desktop] > corpus.argv

The mix is a guess at a typical exec stream, NOT a measurement of a real
system: ~35% Nix-wrapped desktop/system programs, ~25% shell/coreutils,
~20% build tools (some very long), ~8% Steam client/runtime, ~8% Wine/Proton,
~4% game launches (native, Proton, Minecraft, ...)."""
import random
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 1
R = random.Random(SEED)

NIXB32 = "0123456789abcdfghijklmnpqrsvwxyz"  # Nix base32: no e o t u


def h():
    return "".join(R.choice(NIXB32) for _ in range(32))


def store(name):
    return f"/nix/store/{h()}-{name}"


HOME = "/home/henrik"
STEAM = f"{HOME}/.local/share/Steam"

GAMES = ["Hades", "Celeste", "Terraria", "Stardew Valley", "Hollow Knight",
         "Factorio", "RimWorld", "Cyberpunk 2077", "Elden Ring", "Baldurs Gate 3",
         "Deep Rock Galactic", "Valheim", "Satisfactory", "Monster Hunter World"]


def desktop():
    progs = [
        ("plasma-workspace-6.2.4", "plasmashell", []),
        ("kwin-6.2.4", "kwin_wayland", ["--wayland-fd", "7", "--socket", "wayland-0", "--xwayland-fd", "8", "--xwayland-display", ":0"]),
        ("konsole-24.08.3", ".konsole-wrapped", []),
        ("dolphin-24.08.3", ".dolphin-wrapped", [HOME]),
        ("firefox-133.0", ".firefox-wrapped", ["-contentproc", "-childID", str(R.randint(1, 60)), "-isForBrowser", "-prefsLen", str(R.randint(20000, 40000)), "-prefMapSize", "244787", "-jsInitLen", "234236", "-parentBuildID", "20241125144727", "-greomni", store("firefox-unwrapped-133.0") + "/lib/firefox/omni.ja", "-appDir", store("firefox-unwrapped-133.0") + "/lib/firefox/browser", "{" + h()[:8] + "-" + h()[:4] + "}", str(R.randint(1000, 30000)), "true", "tab"]),
        ("pipewire-1.2.7", "pipewire", []),
        ("wireplumber-0.5.7", "wireplumber", []),
        ("dbus-1.14.10", "dbus-daemon", ["--session", "--address=systemd:", "--nofork", "--nopidfile", "--systemd-activation", "--syslog-only"]),
        ("systemd-256.8", "systemd-executor" if R.random() < .5 else "systemd-tmpfiles", ["--deserialize", str(R.randint(3, 60)), "--log-level", "info", "--log-target", "journal-or-kmsg"]),
        ("kio-6.8.0", "kioworker", [store("kio-extras-24.08.3") + "/lib/qt-6/plugins/kf6/kio/file.so", "file", "", ""]),
        ("baloo-6.8.0", "baloo_file_extractor", []),
        ("discord-0.0.76", "Discord", ["--type=renderer", "--enable-crash-reporter=" + h()[:8], "--app-path=" + store("discord-0.0.76") + "/opt/Discord/resources/app.asar", "--no-sandbox", "--lang=en-US", "--num-raster-threads=4", "--enable-main-frame-before-activation", "--renderer-client-id=" + str(R.randint(4, 30)), "--time-ticks-at-unix-epoch=-1733" + str(R.randint(100000000, 999999999)), "--launch-time-ticks=" + str(R.randint(10000000, 99999999)), "--shared-files", "--field-trial-handle=3,i,1234567890123456789,9876543210987654321,262144", "--variations-seed-version"]),
        ("vscode-1.95.3", "code", ["--type=utility", "--utility-sub-type=node.mojom.NodeService", "--lang=en-US", "--service-sandbox-type=none", "--dns-result-order=ipv4first", "--inspect-port=0", "--crashpad-handler-pid=" + str(R.randint(1000, 9000))]),
        ("xdg-desktop-portal-1.18.4", "xdg-desktop-portal", []),
        ("power-profiles-daemon-0.23", "power-profiles-daemon", []),
        ("networkmanager-1.48.10", "NetworkManager", ["--no-daemon"]),
        ("mesa-24.2.7", "glxinfo", ["-B"]),
        ("gamemode-1.8.2", "gamemoded", []),
        ("spectacle-24.08.3", ".spectacle-wrapped", ["--background", "--region"]),
    ]
    pkg, prog, args = R.choice(progs)
    base = store(pkg) + "/bin/" + prog
    if prog.startswith(".") and R.random() < .3:  # the bash wrapper itself
        return [store("bash-5.2p37") + "/bin/bash", "-e", store(pkg) + "/bin/" + prog[1:-8]] + args
    return [base] + args


def shell():
    sh = R.choice(["/run/current-system/sw/bin/bash", store("bash-5.2p37") + "/bin/bash", "/bin/sh", "bash", "sh"])
    c = R.random()
    if c < .15:
        return [sh, "-c", R.choice(["echo $$", "test -e /run/gameboost/running.flag", "systemctl --user is-active foo.service", "exec nix-daemon --daemon"])]
    if c < .30:
        return [sh, R.choice([store("nix-2.24.10") + "/libexec/nix-update-hook.sh", f"{HOME}/.local/bin/backup.sh", "/etc/profile.d/vte.sh", f"{HOME}/nixos/scripts/rebuild.sh"])] + R.choice([[], ["--quiet"], ["-v", "now"]])
    if c < .40:
        return [f"{HOME}/.local/bin/" + R.choice(["sync-notes.sh", "wallpaper.sh", "fan-curve.sh"])] + R.choice([[], ["start"]])
    tool = R.choice(["cat", "ls", "grep", "find", "xargs", "awk", "sed", "rsync", "tar", "sort", "head", "tr", "date", "id", "stat", "pgrep", "sleep", "env", "readlink", "basename", "mkdir", "rm", "cp"])
    pfx = R.choice(["", "/run/current-system/sw/bin/", store("coreutils-9.5") + "/bin/", store("findutils-4.10.0") + "/bin/"])
    args = {
        "cat": [R.choice(["/proc/meminfo", "/sys/class/drm/card1/device/power_dpm_force_performance_level", f"{HOME}/.config/kwinrc"])],
        "ls": ["-la", R.choice([HOME, "/tmp", f"{STEAM}/steamapps/common"])],
        "grep": ["-q", R.choice(["AppId", "MemAvailable", "steam"]), R.choice(["/proc/meminfo", "/etc/os-release"])],
        "find": [R.choice([HOME, "/tmp", "/nix/var/nix/gcroots"]), "-maxdepth", "2", "-name", R.choice(["*.log", "*.tmp", "core*"]), "-mtime", "+7"],
        "xargs": ["-0", "rm", "-f"],
        "awk": ["-F:", "{print $1}", "/etc/passwd"],
        "sed": ["-n", "s/^model name.*: //p", "/proc/cpuinfo"],
        "rsync": ["-a", "--delete", f"{HOME}/Documents/", "/mnt/backup/Documents/"],
        "tar": ["-czf", f"/tmp/backup-{R.randint(1, 999)}.tar.gz", f"{HOME}/.config"],
        "pgrep": ["-f", R.choice(["steam", "wineserver", "gamescope"])],
        "sleep": [R.choice(["1", "0.5", "60", "infinity"])],
        "env": ["-i", "PATH=/run/current-system/sw/bin", "bash", "-l"],
    }.get(tool, [R.choice(["-f", "-p", "--", "-u"]), f"{HOME}/" + h()[:6]])
    if R.random() < .1:
        return [R.choice(["sudo", "/run/wrappers/bin/sudo", "timeout", "doas"])] + (["60"] if R.random() < .5 else []) + [pfx + tool] + args
    return [pfx + tool] + args


def build():
    c = R.random()
    if c < .30:
        src = R.choice(["src/main.c", "src/util/hash.c", "lib/regex/regcomp.c", "kernel/sched/fair.c"])
        inc = []
        for _ in range(R.randint(3, 30)):
            inc += ["-I" + store(R.choice(["glib-2.82.1-dev", "openssl-3.3.2-dev", "zlib-1.3.1-dev", "systemd-256.8-dev", "qtbase-6.8.0"])) + "/include"]
        return [store("gcc-13.3.0") + "/libexec/gcc/x86_64-unknown-linux-gnu/13.3.0/cc1", "-quiet"] + inc + ["-D_FORTIFY_SOURCE=3", "-DNDEBUG", src, "-quiet", "-dumpbase", src.split("/")[-1], "-mtune=generic", "-march=x86-64", "-O2", "-Wall", "-fPIC", "-fstack-protector-strong", "-o", "/build/cc" + h()[:6] + ".s"]
    if c < .45:
        return [store("binutils-2.43.1") + "/bin/as", "--64", "-o", "build/" + h()[:8] + ".o", "/build/cc" + h()[:6] + ".s"]
    if c < .55:
        return [store("binutils-2.43.1") + "/bin/ld", "-plugin", store("gcc-13.3.0") + "/libexec/gcc/x86_64-unknown-linux-gnu/13.3.0/liblto_plugin.so", "--eh-frame-hdr", "-m", "elf_x86_64", "-pie", "-o", "build/app"] + ["build/" + h()[:8] + ".o" for _ in range(R.randint(2, 40))] + ["-lc", "-lgcc"]
    if c < .75:
        args = [store("rustc-1.83.0") + "/bin/rustc", "--crate-name", R.choice(["serde", "tokio", "syn", "regex_automata", "hyper"]), "--edition=2021", f"{HOME}/.cargo/registry/src/index.crates.io-6f17d22bba15001f/serde-1.0.215/src/lib.rs", "--error-format=json", "--json=diagnostic-rendered-ansi,artifacts,future-incompat", "--crate-type", "lib", "--emit=dep-info,metadata,link", "-C", "embed-bitcode=no", "-C", "debuginfo=2", "--cfg", 'feature="default"', "--cfg", 'feature="std"', "-C", "metadata=" + h()[:16], "-C", "extra-filename=-" + h()[:16], "--out-dir", f"{HOME}/src/proj/target/debug/deps", "-L", f"dependency={HOME}/src/proj/target/debug/deps"]
        for _ in range(R.randint(0, 40)):
            n = R.choice(["proc_macro2", "quote", "unicode_ident", "memchr", "bytes", "libc", "cfg_if", "itoa"])
            args += ["--extern", f"{n}={HOME}/src/proj/target/debug/deps/lib{n}-{h()[:16]}.rmeta"]
        return args + ["--cap-lints", "allow"]
    if c < .85:
        return [store("gnumake-4.4.1") + "/bin/make", "-j16", "-l16", R.choice(["all", "install", "check"])]
    if c < .92:
        return [store("ninja-1.12.1") + "/bin/ninja", "-j16"]
    return [store("nodejs-22.11.0") + "/bin/node", f"{HOME}/src/web/node_modules/.bin/" + R.choice(["vite", "tsc", "eslint"]), "--config", "vite.config.ts"]


def steam():
    c = R.random()
    rt = f"{STEAM}/ubuntu12_32/steam-runtime"
    if c < .25:
        return [f"{STEAM}/ubuntu12_64/steamwebhelper", "--type=renderer", "--user-agent-product=Valve Steam Client", "--enable-blink-features=ResizeObserver,Worklet,AudioWorklet", "--lang=en-US", "--log-file=" + STEAM + "/logs/cef_log.txt", "--disable-seccomp-filter-sandbox", "--disable-gpu-compositing", "--num-raster-threads=4", "--renderer-client-id=" + str(R.randint(5, 40)), "--launch-time-ticks=" + str(R.randint(10 ** 9, 10 ** 10)), "--field-trial-handle=" + str(R.randint(10 ** 8, 10 ** 9)), "--variations-seed-version", "--buildid=1733192812", "--steamid=0"]
    if c < .35:
        return [f"{STEAM}/ubuntu12_32/steam", "-srt-logger-opened", "-nominidumps", "-nobreakpad"]
    if c < .45:
        return [store("steam-fhs") + "/bin/steam-run", "steam"]
    if c < .55:
        return [f"{STEAM}/steamapps/common/SteamLinuxRuntime_sniper/pressure-vessel/bin/pressure-vessel-wrap", "--batch", "--filesystem=" + HOME, "--variable-dir=" + f"{STEAM}/steamapps/common/SteamLinuxRuntime_sniper/var", "--runtime=sniper_platform_3.0.20241118.108552/files", "--", f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/proton", "waitforexitandrun", f"{STEAM}/steamapps/common/{R.choice(GAMES)}/Game.exe"]
    if c < .62:
        return [f"{STEAM}/steamapps/common/SteamLinuxRuntime_sniper/pressure-vessel/libexec/steam-runtime-tools-0/srt-bwrap", "--args", "40", "--", "pv-adverb", "--generate-locales", "--fd", "8", "--", "steam-runtime-launcher-service"]
    if c < .72:
        return [f"{STEAM}/ubuntu12_32/reaper", "SteamLaunch", "AppId=" + str(R.randint(200000, 2800000)), "Install=1", "--", f"{STEAM}/ubuntu12_32/steam-runtime/run.sh", "installscript.vdf"]
    if c < .82:
        return [f"{rt}/amd64/usr/bin/steam-runtime-steam-remote", "steam://rungameid/" + str(R.randint(200000, 2800000))]
    return [f"{STEAM}/ubuntu12_64/gldriverquery"] if R.random() < .5 else [f"{STEAM}/ubuntu12_64/vulkandriverquery"]


def wine():
    g = R.choice(GAMES)
    pfx = f"{STEAM}/steamapps/compatdata/{R.randint(200000, 2800000)}/pfx"
    c = R.random()
    if c < .2:
        return ["C:\\windows\\system32\\" + R.choice(["services.exe", "winedevice.exe", "plugplay.exe", "svchost.exe", "rpcss.exe", "explorer.exe", "conhost.exe", "tabtip.exe"])] + R.choice([[], ["-k", "LocalServiceNetworkRestricted"], ["/desktop"]])
    if c < .3:
        return [f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/files/bin/wineserver"]
    if c < .4:
        return [f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/files/bin/wine64", "c:\\windows\\system32\\steam.exe", f"Z:\\home\\henrik\\.local\\share\\Steam\\steamapps\\common\\{g}\\{g.replace(' ', '')}.exe"]
    if c < .5:
        return [f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/files/bin/wine-preloader", f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/files/bin/wine64", "c:\\windows\\system32\\wineboot.exe", "--init"]
    if c < .6:
        return [f"Z:\\home\\henrik\\.local\\share\\Steam\\steamapps\\common\\{g}\\_CommonRedist\\vcredist\\2019\\VC_redist.x64.exe", "/install", "/quiet", "/norestart"]
    if c < .68:
        return ["C:\\Program Files (x86)\\Steam\\steam.exe", "-silent"] if R.random() < .5 else ["C:\\Program Files\\Electronic Arts\\EA Desktop\\EA Desktop\\EALauncher.exe"]
    if c < .76:
        return [f"{STEAM}/steamapps/common/Proton - Experimental/files/lib/wine/x86_64-windows/xalia/xalia.exe"] if R.random() < .3 else [f"{HOME}/Games/{g}/drive_c/Program Files/{g}/{g.replace(' ', '')}Launcher.exe"]
    if c < .84:
        return [store("wine-staging-9.21") + "/bin/wine", f"{HOME}/Downloads/{R.choice(['setup.exe', 'installer.exe', 'Update.exe', 'dotNetFx40_Full_setup.exe'])}"]
    if c < .88:
        return [store("winetricks-20240105") + "/bin/winetricks", "-q", "vcrun2019"]
    if c < .92:  # Lutris/Heroic-style launch: Wine with a Unix path (watched)
        return [store("wine-staging-9.21") + "/bin/" + R.choice(["wine", "wine64", ".wine64-preloader-wrapped"]), f"{HOME}/Games/{g}/drive_c/Program Files/{g}/{g.replace(' ', '')}.exe"]
    return [f"Z:\\home\\henrik\\Games\\{g}\\{g.replace(' ', '')}.exe", "-dx12"]  # a game (wine renamed)


def game():
    g = R.choice(GAMES)
    c = R.random()
    if c < .3:
        return [f"{STEAM}/ubuntu12_32/reaper", "SteamLaunch", "AppId=" + str(R.randint(200000, 2800000)), "--", f"{STEAM}/ubuntu12_32/steam-launch-wrapper", "--", f"{STEAM}/steamapps/common/SteamLinuxRuntime_sniper/_v2-entry-point", "--verb=waitforexitandrun", "--", f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/proton", "waitforexitandrun", f"{STEAM}/steamapps/common/{g}/{g.replace(' ', '')}.exe"]
    if c < .45:
        return [f"{STEAM}/steamapps/common/Proton 9.0 (Beta)/proton", "waitforexitandrun", f"{STEAM}/steamapps/common/{g}/{g.replace(' ', '')}.exe"]
    if c < .6:
        return [f"{STEAM}/steamapps/common/{g}/{g.replace(' ', '')}.x86_64", "-screen-fullscreen", "1"]
    if c < .7:
        return [f"{HOME}/Games/{g}/{g.replace(' ', '')}.AppImage"]
    if c < .8:
        return [store("openjdk-21.0.5+11") + "/lib/openjdk/bin/java", "-Xmx4G", "-Djava.library.path=/tmp/natives", "-cp", f"{HOME}/.minecraft/libraries/a.jar:{HOME}/.minecraft/versions/1.21.3/1.21.3.jar", "net.minecraft.client.main.Main", "--username", "Henrik", "--version", "1.21.3", "minecraft-1.21.3.jar"]
    if c < .85:
        return [f"{HOME}/.local/share/Hytale/install/release/package/game/latest/Client/HytaleClient", "--launched"]
    if c < .9:
        return [f"{STEAM}/steamapps/common/ProjectZomboid/projectzomboid/ProjectZomboid64"] + (["-servername", "srv"] if R.random() < .3 else [])
    return [f"{STEAM}/steamapps/common/{g}/bin/x64/game.exe"] if R.random() < .5 else [f"Z:\\home\\henrik\\Games\\{g}\\Binaries\\Win64\\{g.replace(' ', '')}-Win64-Shipping.exe"]


CATS = [(desktop, .35), (shell, .25), (build, .20), (steam, .08), (wine, .08), (game, .04)]
if len(sys.argv) > 3 and sys.argv[3] == "desktop":  # no Steam/Wine/games
    CATS = [(desktop, .35 / .8), (shell, .25 / .8), (build, .20 / .8)]
out = sys.stdout
for i in range(N):
    x = R.random()
    acc = 0
    for f, w in CATS:
        acc += w
        if x < acc:
            break
    argv = f()
    out.write("\x1f".join(argv) + "\n")
