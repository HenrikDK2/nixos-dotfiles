#!/bin/bash
# corpus.sh TREE OUT: one line per fake process cmdline, as read_cmdline_fd sees it
set -eu
for t in "$1"/desktop "$1"/gaming; do
  for d in "$t"/[0-9]*; do
    [ -f "$d/cmdline" ] || continue
    tr '\0\n' '  ' < "$d/cmdline" | sed 's/^[ \t]*//; s/[ \t]*$//'; echo
  done
done | sort -u > "$2"
# extra hand-written cases around the patterns
cat >> "$2" <<'EOT'
/home/u/.steam/ubuntu12_32/reaper SteamLaunch AppId=570 -- /x/dota2.sh
/home/u/.steam/ubuntu12_32/reaper SteamLaunch AppId=570 Install=1 -- /x
reaper SteamLaunch AppId=1 --
/x/reaper SteamLaunch AppId=12 --x
java -jar /home/u/.minecraft/versions/1.21/minecraft-1.21.jar
/home/u/Games/foo/Foo.x86_64
\home\u\Games\Bar.AppImage
/mnt/steamapps/common/Game/game.x86_64 -opengl
/opt/Hytale/bin/x/HytaleClient
Z:\home\u\Games\Foo\Foo.exe
C:\windows\system32\winedevice.exe
C:/windows/explorer.exe
c:\Program Files\Launcher\GameLauncher.exe
D:\Setup.exe
E:\Install\InstallShield.exe
F:\a\Updater.exe
G:\vc_Redist.x64.exe
ProjectZomboid64 -servername foo
ProjectZomboid64
sudo find / -name x
timeout 60 rsync -a a b
/usr/bin/bash ./run.sh
sh -x build.sh arg
start.sh
/x/7z.exe x a.zip
link2ea://launchgame/123
EOT
