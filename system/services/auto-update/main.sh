readonly gate_flag=/run/gameboost/running.flag \
         gate_stamp=/var/lib/generation-stamp \
         gate_min_age=86400 \
         flake="@flakeDir@"

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

# ---------- Update flake (only reached when an upgrade is due) ----------
if ! nix flake update --flake "$flake"; then
  echo "flake update failed; skipping."
  exit 1
fi

# ---------- Commit updated flake.lock ----------
# Only commit if nothing else is already staged.
if ! git -C "$flake" diff --cached --quiet; then
  echo "Other changes are already staged; skipping flake.lock commit."
  exit 0
fi

if ! git -C "$flake" add -- flake.lock; then
  echo "Failed to stage flake.lock; skipping."
  exit 0
fi

if ! git -C "$flake" diff --cached --quiet -- flake.lock; then
  if ! git -C "$flake" commit -m "Update flake.lock"; then
    echo "Failed to commit flake.lock; skipping."
    exit 0
  fi
else
  echo "flake.lock unchanged; nothing to commit."
fi
