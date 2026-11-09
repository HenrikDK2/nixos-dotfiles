#!/usr/bin/env python3
"""realtree.py SRC_A SRC_B...: compare tree_pids of several start.sh versions on
the REAL /proc. Spawns a process tree with odd comm names (via prctl), children
forked from non-main threads, nested shells, zombies and a short-lived churn of
processes, then calls tree_pids ROOT in each version and compares TREE (as a
multiset, and in order)."""
import ctypes, os, subprocess, sys, threading, time, tempfile

libc = ctypes.CDLL(None, use_errno=True)
def setname(n):
    libc.prctl(15, ctypes.c_char_p(n.encode()), 0, 0, 0)  # PR_SET_NAME

NAMES = ["a) b) (c", "x\ny *", ") ", "))", "( (", "p) S 1 2", "[0-9]*", "normal"]
def child_tree(depth):
    # runs in a forked child
    setname(NAMES[depth % len(NAMES)])
    kids = []
    def spawn_from_thread():
        p = os.fork()
        if p == 0:
            setname(NAMES[(depth + 3) % len(NAMES)])
            if depth < 3:
                child_tree(depth + 1)
            time.sleep(60); os._exit(0)
        kids.append(p)
    ths = [threading.Thread(target=spawn_from_thread) for _ in range(2)]
    for t in ths: t.start()
    for t in ths: t.join()
    # a zombie child: exits, never reaped
    z = os.fork()
    if z == 0:
        os._exit(0)
    # extra idle threads
    for _ in range(3):
        threading.Thread(target=time.sleep, args=(60,), daemon=True).start()
    if depth == 0:
        subprocess.Popen(["bash", "-c", "sleep 60 & sleep 60 & wait"])

root = os.fork()
if root == 0:
    child_tree(0)
    time.sleep(60)
    os._exit(0)
time.sleep(1.5)
srcs = sys.argv[1:]
outs = []
for s in srcs:
    lib = tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False)
    lib.write("".join(open(f"{s}/start.sh").readlines()[:-1]))  # drop `main "$@"`
    lib.close()
    r = subprocess.run(["bash", "-c", f'. {lib.name}; tree_pids "$@"; printf "%s\\n" "${{TREE[@]}}"',
                        "x", str(root), str(root), "999999"], capture_output=True, text=True,
                       env={"LC_ALL": "C", "PATH": "/usr/bin:/bin"})
    outs.append(r.stdout.split())
    os.unlink(lib.name)
os.killpg(0, 15) if False else None
subprocess.run(["pkill", "-KILL", "-s", str(os.getsid(0)), "-f", "sleep 60"], check=False)
os.kill(root, 9)
ok = True
for s, o in zip(srcs, outs):
    same_set = sorted(o) == sorted(outs[0])
    same_order = o == outs[0]
    print(f"{s}: {len(o)} entries ({len(set(o))} distinct); multiset==first: {same_set}; order==first: {same_order}")
    ok &= same_set
sys.exit(0 if ok else 1)
