#!/usr/bin/env bash
set -euo pipefail

nm-online --timeout=30 --wait-for-startup --quiet || {
    echo "NetworkManager not ready; giving up." >&2
    exit 1
}

IFACE="${1:-$(nmcli -t -f DEVICE,TYPE device status |
    awk -F: '$2 == "ethernet" && !found { print $1; found = 1 }')}"

if [[ -z "$IFACE" ]]; then
    echo "No Ethernet interface found." >&2
    exit 1
fi

# Skip if already connected (state 100 = connected)
STATE="$(nmcli -g GENERAL.STATE device show "$IFACE")"
if [[ "$STATE" == 100* ]]; then
    echo "'$IFACE' already connected; nothing to do."
    exit 0
fi

# Look for an Ethernet profile that applies to this interface
# (bound to it, or not bound to any interface) and has autoconnect enabled.
FOUND=""
while IFS=: read -r UUID TYPE; do
    [[ "$TYPE" == "802-3-ethernet" ]] || continue

    mapfile -t PROP < <(nmcli -g connection.autoconnect,connection.interface-name \
        connection show uuid "$UUID")
    AUTOCONNECT="${PROP[0]:-}"
    BOUND_IFACE="${PROP[1]:-}"

    if [[ "$AUTOCONNECT" == "yes" && ( -z "$BOUND_IFACE" || "$BOUND_IFACE" == "$IFACE" ) ]]; then
        FOUND="$UUID"
        break
    fi
done < <(nmcli -t -f UUID,TYPE connection show)

if [[ -z "$FOUND" ]]; then
    echo "No autoconnect-enabled Ethernet profile for '$IFACE'; skipping."
    exit 0
fi

echo "Connecting '$IFACE' using profile $FOUND"

for attempt in 1 2 3; do
    if nmcli --wait 15 connection up uuid "$FOUND" ifname "$IFACE"; then
        exit 0
    fi

    # Ethernet is up but a secondary (VPN) failed: don't treat it as fatal
    STATE="$(nmcli -g GENERAL.STATE device show "$IFACE")"
    if [[ "$STATE" == 100* ]]; then
        echo "Ethernet is up; a secondary connection (VPN) failed." >&2
        exit 0
    fi

    echo "Attempt $attempt failed; retrying..." >&2
    sleep 2
done

exit 1
