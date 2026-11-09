#!/usr/bin/env python3
"""Adversarial lines for classification equivalence tests: random
concatenations of pattern fragments, separators and noise (argv format, one
line per cmdline). Usage: gen_fuzz.py N SEED > fuzz.argv"""
import random, sys
N = int(sys.argv[1]); R = random.Random(int(sys.argv[2]))
frag = ["reaper", "SteamLaunch", "AppId=", "123", "--", " ", "/", "\\", "proton", "waitforexitandrun",
        "minecraft", ".jar", "Games", ".AppImage", ".x86_64", ".i386", "steamapps", "common", "Hytale",
        "HytaleClient", "HytaleServer.jar", "C:", "c:", "Z:", ".exe", "exe", "ProjectZomboid64", "-servername",
        "xalia", "wineserver", "wine", "winetricks", "windows", "Steam", "legacycompat", "compatdata",
        "iscriptevaluator", "d3ddriverquery64", "pv-adverb", "pressure-vessel", "bin", "libexec",
        "steam-runtime-tools-0", "srt-bwrap", "pressure-vessel-wrap", "Windower", "Black Tree Gaming Ltd",
        "Vortex", "ModOrganizer", "MO2", "mods", "explorer++", "loot", "lootcli", "link2ea://launchgame",
        "Electronic Arts", "EA Desktop", "Launcher", "launcher", "LaunchPad", "Setup", "setup", "Install",
        "Update", "update", "Redist", "dotnet", "7z", "yay", "pacman", "pgrep", "find", "xargs", "grep",
        "awk", "rsync", "tar", "cat", "sudo", "doas", "run0", "timeout", "time", "-u", " 60", "5s", ".sh",
        "bash", "dash", "sh", "-c", "\t", "x", "Q", "0", "-", "_", ".", "/nix/store/abc-", "wine64"]
for _ in range(N):
    parts = [R.choice(frag) for _ in range(R.randint(1, 14))]
    s = "".join(parts)
    # split into argv at some spaces
    argv = [a for a in s.split(" ") if a] or ["x"]
    print("\x1f".join(argv))
