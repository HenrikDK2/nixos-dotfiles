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
    setpriv --reuid="$uid" --regid="$gid" --init-groups \
        env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" DISPLAY=:0 "$@"
}

# send UID GID MESSAGE
send() {
    local uid=$1 gid=$2 owner id old_uid old_owner old_id replace=()

    owner=$(as_user "$uid" "$gid" busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications 2>/dev/null)
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

notify_user() {
    local session user uid gid active type key value

    while read -r session _; do
        active='' type='' user=''
        while IFS='=' read -r key value; do
            case $key in
                Active) active=$value ;;
                Type) type=$value ;;
                Name) user=$value ;;
            esac
        done < <(loginctl show-session "$session" -p Active -p Type -p Name 2>/dev/null)

        [[ $active == yes && $type =~ ^(x11|wayland)$ ]] || continue
        uid=$(id -u "$user") || continue
        gid=$(id -g "$user") || continue

        send "$uid" "$gid" "$1"
        return
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
}

# gameboostd starts this without waiting, so the "performance" and
# "power-saving" calls of a short game can overlap: one at a time.
exec 9> "${ID_FILE%/*}/notify.lock"
flock 9

notify_user "$1"
