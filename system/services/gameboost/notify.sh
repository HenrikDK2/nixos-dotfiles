#!/bin/bash

# Desktop notification for the active graphical session's user.
# usage: notify.sh MESSAGE   (called by gameboostd on mode switches)

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

        setpriv --reuid="$uid" --regid="$gid" --init-groups \
            env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" DISPLAY=:0 \
            notify-send --app-name=GameBoost GameBoost "$1"

        echo "Notification sent: $1"
        return
    done < <(loginctl list-sessions --no-legend 2>/dev/null)
}

notify_user "$1"
