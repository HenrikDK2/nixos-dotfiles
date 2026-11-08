# Benchmark harness

Sandbox: generic Linux container (not NixOS), 4 vCPU, no GPU/KWin/games, no `perf`
(no HW counters). Tools: gcc/clang, valgrind (callgrind/massif), strace, hyperfine,
shellcheck, node 22, nix-instantiate.

Benchmarks are saved under `perf-ledger/bench/<target>/` with a README each.
