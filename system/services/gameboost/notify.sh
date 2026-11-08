#!/bin/bash

# Desktop notification for the active graphical session's user.
# usage: notify.sh MESSAGE   (called by gameboostd on mode switches)
#
# "Switching to power-saving mode" replaces the earlier "performance mode"
# notification instead of stacking under it: the notification id is kept in
# $ID_FILE together with the user and the notification server's bus name, and
# reused only while both still match (after a plasmashell restart its ids
# start over and could belong to another app's notification).

readonly ID_FILE=/run/gameboost/notify-id

# as_user UID GID CMD...: run CMD as the user, on their session bus.
as_user() {
    local uid=$1 gid=$2
    shift 2
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" DISPLAY=:0 \
        setpriv --reuid="$uid" --regid="$gid" --init-groups "$@"
}

# send UID GID MESSAGE
send() {
    local uid=$1 gid=$2 owner id old_uid old_owner old_id replace=()

    # "exec 2>/dev/null;" rather than a trailing redirection: bash then runs
    # the command in the $(...) subshell itself, without a second fork.
    owner=$(exec 2>/dev/null; as_user "$uid" "$gid" busctl --user call org.freedesktop.DBus \
        /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications)
    owner=${owner#s }
    owner=${owner//\"/}

    if [[ -n $owner ]] && read -r old_uid old_owner old_id 2>/dev/null < "$ID_FILE" &&
        [[ $old_uid == "$uid" && $old_owner == "$owner" && $old_id =~ ^[0-9]+$ ]]; then
        replace=(--replace-id="$old_id")
    fi

    # -e: transient, kept out of the notification history.
    id=$(as_user "$uid" "$gid" notify-send --print-id --transient --expire-time=3000 \
        --app-name=GameBoost "${replace[@]}" GameBoost "$3")

    if [[ -n $owner && $id =~ ^[0-9]+$ ]]; then
        printf '%s %s %s\n' "$uid" "$owner" "$id" > "$ID_FILE.tmp" && mv -f "$ID_FILE.tmp" "$ID_FILE"
    fi
    echo "Notification sent: $3"
}

# notify_block MESSAGE: notify the session's user if the session read by
# match_sessions (active, type, user) is active and graphical; send's exit
# status goes to $status.
notify_block() {
    local ids re='^uid=([0-9]+)(\([^)]*\))? gid=([0-9]+)'

    [[ $active == yes && $type =~ ^(x11|wayland)$ ]] || return 1
    ids=$(LC_ALL=C id "$user") || return 1
    [[ $ids =~ $re ]] || return 1

    send "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}" "$1"
    status=$?
}

# match_sessions MESSAGE < "loginctl show-session" output: notify the first
# active graphical session (sessions are separated by blank lines).
match_sessions() {
    local active='' type='' user='' key value

    while IFS='=' read -r key value; do
        if [[ -z $key && -z $value ]]; then
            notify_block "$1" && return 0
            active='' type='' user=''
            continue
        fi
        case $key in
            Active) active=$value ;;
            Type) type=$value ;;
            Name) user=$value ;;
        esac
    done
    notify_block "$1"
}

notify_user() {
    local session sessions=() out status=0

    while read -r session _; do
        sessions+=("$session")
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
    ((${#sessions[@]})) || return 0

    # One loginctl call for all sessions; it stops at the first session that
    # is gone, so then one call per session.
    if out=$(exec 2>/dev/null; loginctl show-session "${sessions[@]}" -p Active -p Type -p Name); then
        match_sessions "$1" <<< "$out"
    else
        for session in "${sessions[@]}"; do
            match_sessions "$1" < <(loginctl show-session "$session" -p Active -p Type -p Name 2>/dev/null) &&
                break
        done
    fi
    return "$status"
}

# gameboostd starts this without waiting, so the "performance" and
# "power-saving" calls of a short game can overlap: one at a time.
exec 9> "${ID_FILE%/*}/notify.lock"
flock 9

notify_user "$1"
