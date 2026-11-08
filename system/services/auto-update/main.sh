readonly gate_flag=/run/gameboost/running.flag \
         gate_deferred=/run/nixos-upgrade.deferred \
         gate_stamp=/var/lib/generation-stamp \
         gate_min_age=86400 \
         flake="@flakeDir@"

readonly git_cmd=(git -C "$flake"
  -c user.name="nixos-autoupgrade"
  -c user.email="autoupgrade@localhost"
  -c safe.directory="$flake")

# schedule_check EPOCH: one more check at that time (nixos-upgrade-due.timer).
# A wall-clock timer, so time spent asleep counts and a check that came due
# during sleep runs right after resume.
schedule_check() {
  systemctl stop nixos-upgrade-due.timer 2>/dev/null
  systemd-run --quiet --collect --unit=nixos-upgrade-due \
    --on-calendar="$(date -d "@$1" '+%F %T')" \
    --timer-property=AccuracySec=1min \
    --timer-property=RemainAfterElapse=no \
    "$(command -v systemctl)" start --no-block nixos-upgrade.service ||
    echo "Could not schedule the next check; it runs at the next boot."
}

# After a successful upgrade (ExecStartPost): next check when it is due.
if [[ ${1:-} == schedule-next ]]; then
  schedule_check $((EPOCHSECONDS + gate_min_age))
  exit 0
fi

# Exit codes (ExecCondition): 0 = upgrade now, 1 = skip quietly,
# 255 = failed, so nixos-upgrade.service is retried (Restart=on-failure).

# ---------- Gate 1: GameBoost running ----------
# GameBoost's exit.sh starts the upgrade again when the game ends.
if [[ -e $gate_flag ]]; then
  : > "$gate_deferred"
  echo "GameBoost is running; skipping until the game ends."
  exit 1
fi
rm -f "$gate_deferred"

# ---------- Gate 2: last upgrade too recent ----------
if read -r gate_created _ 2>/dev/null < "$gate_stamp"; then
  gate_age=$((EPOCHSECONDS - gate_created))
  if ((gate_age >= 0 && gate_age < gate_min_age)); then
    if ((gate_age < 3600)); then
      gate_ago="$((gate_age / 60)) min ago"
    else
      gate_ago="$((gate_age / 3600))h ago"
    fi
    gate_left=$((gate_min_age - gate_age))
    schedule_check $((gate_created + gate_min_age))
    echo "Last upgrade was $gate_ago (< $((gate_min_age / 3600))h); skipping," \
      "next check in $((gate_left / 3600))h $((gate_left % 3600 / 60))min."
    exit 1
  fi
fi

# ---------- Update flake (only reached when an upgrade is due) ----------
if ! nix flake update --flake "$flake"; then
  echo "flake update failed; retrying in an hour."
  exit 255
fi

# ---------- Commit updated flake.lock ----------
# Skip only if something OTHER than flake.lock is staged, so a leftover
# staged flake.lock (e.g. from an earlier failed commit) can't block us.
if ! "${git_cmd[@]}" diff --cached --quiet -- . ':(exclude)flake.lock'; then
  echo "Other changes are already staged; skipping flake.lock commit."
  exit 0
fi

if ! "${git_cmd[@]}" add -- flake.lock; then
  echo "Failed to stage flake.lock; skipping."
  exit 0
fi

if ! "${git_cmd[@]}" diff --cached --quiet -- flake.lock; then
  # Path-limited commit: only ever commits flake.lock.
  if ! "${git_cmd[@]}" commit -m "Update flake.lock" -- flake.lock; then
    echo "Failed to commit flake.lock; skipping."
    exit 0
  fi
else
  echo "flake.lock unchanged; nothing to commit."
fi
