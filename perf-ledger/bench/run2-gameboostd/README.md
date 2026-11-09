# gameboostd benchmark harness

Runs gameboostd.c's hot paths (full_scan, drain_events + check_pending,
split_alts) without root, netlink or a real game, against a deterministic
fake /proc tree; plus real-/proc runs in a private PID namespace (root).

## Setup

    ./gen_tree.sh                  # /dev/shm/gbd_tree/{desktop,gaming,plain}, events.txt,
                                   # /dev/shm/gbd_hold, /dev/shm/gbd_spawner, /dev/shm/gbd_corpus.txt
    ./build.sh SRC.c OUT [CFLAGS]  # driver binary for one gameboostd.c variant (default -O2)

Patterns are taken from scripts/main.sh by `patterns.sh` (exactly as main.sh
builds them, with the `[/\]` slash class). Override with `MAIN_SH=...`.

Trees (gen_proc.py, fixed seed): `desktop` = 546 pid dirs (170 kernel threads
with empty cmdline, NixOS/KDE services with /nix/store paths, Firefox content
processes, Steam + steamwebhelper (long cmdlines), Discord, shells, plus the
90 still-running processes of the event workload, 9 of them Wine/Proton
command lines); `gaming` = same with a Proton game stack (reaper, proton,
pressure-vessel, wineserver, C:\windows\... services, the game .exe);
`plain` = desktop without the event processes (no Wine/steamapps lines).
Only `cmdline` exists per pid: that is all gameboostd reads.

`events.txt`: 300 exec events (70% short-lived tools already gone at check
time, 27% still running, 3% Wine starts that also get a rename event).

## Metrics

    ./ir.sh DRIVER         # callgrind Ir (deterministic), steady state:
      scan_desktop / scan_gaming / scan_plain : Ir per full_scan (warm-up scan excluded)
      events        : Ir per exec event in drain_events + check_pending, one drain per 50 events
      events_chunk1 : same, one drain per event (low exec rate: the common idle case)
      start         : split_alts of both patterns
    KEEP=/dev/shm/x ./ir.sh DRIVER   # keep callgrind outputs + transcripts

    CPU=1 ./wall.sh DRV_A DRV_B MODE RUNS     # MODE scan_desktop|scan_gaming|scan_plain|events|events1
      ABAB alternation, taskset; in-process wall / CPU (user+sys) / user ns per op;
      median [min..max]. Events timing includes the driver's own socket sends.

    ./realproc.sh TREE BIN...      # real binaries, real /proc of a PID namespace holding
                                   # exactly TREE's processes: `-1` output md5, syscall count
                                   # (strace -f -c), callgrind Ir of the whole cold `-1` run
    ./realwall.sh TREE DRV_A DRV_B RUNS [REPS]  # driver full_scan over that real /proc, ABAB
    ./daemon_rss.sh TREE BIN...    # real daemon (proc connector works as root here):
                                   # VmHWM/VmRSS/Pss/heap after its startup scan

## Correctness

    gcc -O2 -DGBD_SRC='"path/gameboostd.c"' equiv.c -o eq
    ./eq "$(./patterns.sh MAIN | sed -n 1p)" "$(./patterns.sh MAIN | sed -n 2p)" /dev/shm/gbd_corpus.txt 20000

checks, on the corpus (every tree cmdline + hand cases, 150 mutations each)
and on random EREs/strings: compile_alt()+regexec == plain regcomp/regexec of
each alternative, has_lit == memmem, set_matches == regexec of the whole ERE,
is_game == whole-pattern logic, compile_alt validity == regcomp validity.
(Random patterns show a few split-vs-whole differences that come from the
unchanged extract_literal, e.g. "e+*"; the count must equal base's.)

Driver transcripts (`scan` prints found pids and first_cmd; `events` prints
what was checked/watched/hit) must be byte-identical between variants.

Driver detail: gameboostd.c is #included with main renamed and kill()
redirected to an oracle over the tree (still one real kill syscall per call).
Measured functions are wrapped in noinline bench_* (callgrind --toggle-collect).
