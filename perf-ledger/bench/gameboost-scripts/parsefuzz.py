#!/usr/bin/env python3
"""parsefuzz.py: old vs tree-ifs ppid parsing of /proc/PID/stat, on generated
stat files whose comm (up to 64 bytes, as kthread/workqueue names can be) holds
')', ' ', '(', newlines, digits and glob characters. Kernel-format lines only
(comm's ')' is followed by ' STATE PPID ...'), plus empty files."""
import os, random, subprocess, tempfile
rnd = random.Random(7)
d = tempfile.mkdtemp()
alphabet = ") ( S1\n*?[]x9"
n = 3000
for i in range(n):
    comm = "".join(rnd.choice(alphabet) for _ in range(rnd.randint(0, 64)))
    ppid = rnd.choice(["1", "0", "12345", "4194304"])
    line = f"{i + 1} ({comm}) {rnd.choice('SRZDI')} {ppid} 1 1 0 -1 4194560 0 0 0 0 0 0 0 0 20 0 1 0 1 0 0\n"
    if i % 500 == 0:
        line = ""
    open(f"{d}/{i + 1}", "w").write(line)
old = r'''for f in "$1"/*; do read -r -d '' line < "$f"; head=${line%") "*}; rest=${line#"$head") }; ppid=${rest#* }; ppid=${ppid%% *}; [[ $ppid =~ ^[0-9]+$ ]] || ppid=SKIP; echo "${f##*/} $ppid"; done'''
new = r'''for f in "$1"/*; do IFS=')' read -r -d '' -a a < "$f"; ppid=${a[*]: -1}; ppid=${ppid#" "* }; ppid=${ppid%% *}; [[ $ppid == +([0-9]) ]] || ppid=SKIP; echo "${f##*/} $ppid"; done'''
o = subprocess.run(["bash", "-c", old, "x", d], capture_output=True, text=True, env={"LC_ALL": "C"}).stdout
w = subprocess.run(["bash", "-c", new, "x", d], capture_output=True, text=True, env={"LC_ALL": "C"}).stdout
ol, nl = o.splitlines(), w.splitlines()
bad = [(a, b) for a, b in zip(ol, nl) if a != b]
print(f"parsefuzz: {len(ol)} stat files, {len(bad)} mismatches", bad[:5])
