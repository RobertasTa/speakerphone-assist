#!/usr/bin/env bash
# speakerphone-assist — give an unprivileged Proxmox LXC container access to USB sound cards.
#
# Run on the Proxmox HOST (not inside the container):
#   ./pve-speakerphone-lxc.sh <CTID>            # show sound cards and the config that would be added
#   ./pve-speakerphone-lxc.sh <CTID> --apply    # add it (a backup of the container config is made first)
#
# What it adds to /etc/pve/lxc/<CTID>.conf:
#   - permission for ALSA devices (character major 116),
#   - a bind mount of /dev/snd,
#   - an idmap that keeps the host "audio" group as the same group inside the container
#     (without it the container sees the devices as nobody:nogroup and cannot open them),
# and, if missing, the matching "root:<audio gid>:1" line in /etc/subgid.
#
# GPL-3.0-or-later. https://github.com/RobertasTa/speakerphone-assist
set -euo pipefail

usage() { sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ $# -ge 1 ] || usage
CTID="$1"; shift
APPLY=0
for a in "$@"; do
    case "$a" in
        --apply) APPLY=1 ;;
        *) usage ;;
    esac
done

CONF="/etc/pve/lxc/${CTID}.conf"
[ -f "$CONF" ] || { echo "No container config: $CONF"; exit 1; }
grep -q '^unprivileged: 1' "$CONF" || echo "NOTE: container $CTID is not unprivileged — the idmap part is not needed for privileged containers."

echo "== Sound cards on this host =="
printf '%-5s %-12s %-10s %s\n' "card" "id" "usb" "name / serial"
for d in /proc/asound/card[0-9]*; do
    [ -d "$d" ] || continue
    n="${d##*card}"
    id="$(cat "$d/id")"
    usb="-"; [ -e "$d/usbid" ] && usb="$(cat "$d/usbid")"
    name="$(sed -n "s/^ *${n} \[[^]]*\]: //p" /proc/asound/cards | head -1)"
    serial=""
    for l in /dev/snd/by-id/*; do
        [ -e "$l" ] || continue
        [ "$(readlink "$l")" = "../controlC${n}" ] && serial="$(basename "$l")"
    done
    printf '%-5s %-12s %-10s %s %s\n' "$n" "$id" "$usb" "$name" "${serial:+| $serial}"
done
echo
echo "Use the 'id' column of your speakerphone as --card for setup-lva.sh (for example: --card ${id:-A350})."
echo "⚠ The card must not be used by anything else (host or another container) — PipeWire will not start if it cannot open it."
echo

GID="$(getent group audio | cut -d: -f3)"
[ -n "$GID" ] || { echo "Host has no 'audio' group"; exit 1; }
REST=$((65536 - GID - 1))

WANT=(
    "lxc.cgroup2.devices.allow: c 116:* rwm"
    "lxc.mount.entry: /dev/snd dev/snd none bind,optional,create=dir"
)
if grep -q '^lxc.idmap' "$CONF"; then
    echo "NOTE: $CONF already has lxc.idmap lines — not adding a second set. Make sure group $GID maps to $GID."
    IDMAP=()
else
    IDMAP=(
        "lxc.idmap: u 0 100000 65536"
        "lxc.idmap: g 0 100000 ${GID}"
        "lxc.idmap: g ${GID} ${GID} 1"
        "lxc.idmap: g $((GID + 1)) $((100000 + GID + 1)) ${REST}"
    )
fi

ADD=()
for line in "${WANT[@]}" "${IDMAP[@]}"; do
    grep -qxF "$line" "$CONF" || ADD+=("$line")
done
SUBGID_OK=1
grep -qx "root:${GID}:1" /etc/subgid || SUBGID_OK=0

echo "== Container $CTID =="
if [ ${#ADD[@]} -eq 0 ]; then
    echo "Config already has everything."
else
    echo "Lines to add to $CONF:"
    printf '  %s\n' "${ADD[@]}"
fi
[ $SUBGID_OK -eq 1 ] || echo "Line to add to /etc/subgid:  root:${GID}:1"

if [ $APPLY -eq 0 ]; then
    echo
    echo "Dry run. Re-run with --apply to write these changes."
    exit 0
fi

if [ ${#ADD[@]} -gt 0 ]; then
    cp -p "$CONF" "/root/lxc-${CTID}.conf.bak-$(date +%Y%m%d-%H%M%S)"
    printf '%s\n' "${ADD[@]}" >> "$CONF"
    echo "Written. Backup of the old config is in /root/."
fi
if [ $SUBGID_OK -eq 0 ]; then
    echo "root:${GID}:1" >> /etc/subgid
    echo "Added root:${GID}:1 to /etc/subgid."
fi
echo "Restart the container for the change to take effect:  pct reboot ${CTID}"
