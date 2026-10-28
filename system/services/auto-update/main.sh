readonly gate_flag=/tmp/gameboost-running.flag \
         gate_stamp=/var/lib/generation-stamp \
         gate_min_age=86400 \
         flake="@flakeDir@" \
         host="@hostName@" \
         heavy_re='linux-|mesa|cachyos|proton|wine'

# ---------- Gate 1: GameBoost running ----------
if [[ -e $gate_flag ]]; then
  echo "GameBoost is running; skipping."
  exit 1
fi

# ---------- Gate 2: last upgrade too recent ----------
if read -r gate_created _ 2>/dev/null < "$gate_stamp"; then
  gate_age=$((EPOCHSECONDS - gate_created))
  if ((gate_age >= 0 && gate_age < gate_min_age)); then
    if ((gate_age < 3600)); then
      gate_ago="$((gate_age / 60)) min ago"
    else
      gate_ago="$((gate_age / 3600))h ago"
    fi
    echo "Last upgrade was $gate_ago (< $((gate_min_age / 3600))h); skipping."
    exit 1
  fi
fi

# ---------- Gate 3: third-party cache ready? ----------
# Only reached once the gates above pass. Updates the lock, and rolls it
# back if heavy packages would have to be built locally.
lock="$flake/flake.lock"
backup="$lock.bak"
ok=0

cp "$lock" "$backup" || { echo "cannot back up flake.lock; skipping."; exit 1; }

cleanup() {
  if [[ $ok -eq 1 ]]; then
    rm -f "$backup"
  else
    mv -f "$backup" "$lock"
  fi
}
trap cleanup EXIT

if ! nix flake update --flake "$flake"; then
  echo "flake update failed; skipping."
  exit 1
fi

if ! out=$(nix build \
    "$flake#nixosConfigurations.$host.config.system.build.toplevel" \
    --dry-run --impure 2>&1); then
  echo "dry-run failed; skipping."
  echo "$out"
  exit 1
fi

to_build=$(printf '%s\n' "$out" \
  | awk '/will be built:/{f=1;next} /will be fetched|^this path|^these/{f=0} f' \
  | grep -E "$heavy_re" || true)

if [[ -n $to_build ]]; then
  echo "Cache not ready; would build locally, skipping:"
  echo "$to_build"
  exit 1
fi

echo "Cache ready; proceeding with upgrade."
ok=1
