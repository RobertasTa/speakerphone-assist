#!/usr/bin/env bash
# speakerphone-assist — install Linux-Voice-Assistant + PipeWire for a USB speakerphone.
#
# Run as root on Debian/Ubuntu (tested: Ubuntu 24.04 in an unprivileged Proxmox LXC container):
#   ./setup-lva.sh --card <ALSA card id> [--name <satellite name>] [--wake <wake word id>]
#
#   --card   the speakerphone's ALSA card id: first word in [brackets] of `arecord -l`,
#            e.g. "card 2: A350 [EMEET Adapter A350]" -> --card A350
#   --name   name shown in Home Assistant (default: speakerphone)
#   --wake   wake word id (default: okay_nabu; also hey_jarvis, alexa, hey_luna, okay_computer, ...)
#   --user   system user that runs the audio server and the satellite (default: lva)
#   --ref    Linux-Voice-Assistant git ref (default: the commit this script was tested with)
#
# What it does: installs packages, creates the user (member of "audio", lingering on), clones and sets up
# Linux-Voice-Assistant, describes the speakerphone to PipeWire STATICALLY (containers have no udev, so
# PipeWire would otherwise see only a dummy device) and installs a systemd service.
#
# GPL-3.0-or-later. https://github.com/RobertasTa/speakerphone-assist
set -euo pipefail

CARD=""; NAME="speakerphone"; WAKE="okay_nabu"; RUSER="lva"
REF="b49fd8d"   # tested 2026-10-10
usage() { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
while [ $# -gt 0 ]; do
    case "$1" in
        --card) CARD="$2"; shift 2 ;;
        --name) NAME="$2"; shift 2 ;;
        --wake) WAKE="$2"; shift 2 ;;
        --user) RUSER="$2"; shift 2 ;;
        --ref)  REF="$2"; shift 2 ;;
        *) usage ;;
    esac
done
[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
if [ -e /run/udev/control ]; then
    echo "NOTE: this system runs udev, so PipeWire can find the speakerphone by itself."
    echo "      This script is made and tested for containers (no udev); on a normal machine the official"
    echo "      Linux-Voice-Assistant install guide is the better fit. Continuing in 5 s — Ctrl+C to stop."
    sleep 5
fi
[ -n "$CARD" ] || { echo "--card is required. Your cards:"; arecord -l 2>/dev/null || cat /proc/asound/cards; exit 1; }

echo "== 1/6 packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    avahi-utils pulseaudio-utils alsa-utils pipewire pipewire-bin pipewire-alsa pipewire-pulse pipewire-audio \
    wireplumber dbus-user-session build-essential libmpv-dev libasound2-plugins ca-certificates iproute2 procps \
    git jq curl wget python3-venv python3-dev >/dev/null

grep -q " ${CARD} " /proc/asound/cards || grep -q "\[${CARD} *\]" /proc/asound/cards || {
    echo "Card '${CARD}' not found. Cards visible here:"; cat /proc/asound/cards; exit 1; }

echo "== 2/6 user ${RUSER}"
id "$RUSER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RUSER"
usermod -aG audio "$RUSER"
RUID="$(id -u "$RUSER")"; RHOME="$(getent passwd "$RUSER" | cut -d: -f6)"
mkdir -p /var/lib/systemd/linger && touch "/var/lib/systemd/linger/${RUSER}"
systemctl start "user@${RUID}.service"
RUN="/run/user/${RUID}"

echo "== 3/6 Linux-Voice-Assistant (${REF})"
LVA="${RHOME}/linux-voice-assistant"
if [ ! -d "$LVA/.git" ]; then
    runuser -u "$RUSER" -- git clone -q https://github.com/OHF-Voice/linux-voice-assistant.git "$LVA"
fi
runuser -u "$RUSER" -- git -C "$LVA" -c advice.detachedHead=false checkout -q "$REF"
(cd "$LVA" && runuser -u "$RUSER" -- script/setup >/dev/null)

echo "== 4/6 what the speakerphone supports"
# a re-run must first release the card from our own satellite and audio server
systemctl stop linux-voice-assistant 2>/dev/null || true
runuser -u "$RUSER" -- env XDG_RUNTIME_DIR="$RUN" systemctl --user stop \
    pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber 2>/dev/null || true
sleep 1
chan() {  # $1 = arecord|aplay ; prints the smallest channel count, or nothing if the card is busy
    # run as the service user: in an unprivileged container root is NOT in the audio group
    # (ALSA then says "No such device", not "permission denied")
    local f=/dev/null; [ "$1" = aplay ] && f=/dev/zero
    local p; p="$(runuser -u "$RUSER" -- "$1" -D "hw:CARD=${CARD},DEV=0" --dump-hw-params -d 1 -f S16_LE "$f" 2>&1 || true)"
    echo "$p" | sed -n 's/^CHANNELS: *\[\{0,1\}\([0-9]*\).*/\1/p' | head -1
}
MIC_CH="$(chan arecord)"; SPK_CH="$(chan aplay)"
[ -n "$MIC_CH" ] || { MIC_CH=1; echo "  (could not probe the microphone — is the card in use? assuming mono)"; }
[ -n "$SPK_CH" ] || { SPK_CH=2; echo "  (could not probe the speaker — assuming stereo)"; }
echo "  microphone channels: $MIC_CH, speaker channels: $SPK_CH"
pos() { [ "$1" -eq 1 ] && echo "MONO" || echo "FL FR"; }
SPK_CH_USE=$([ "$SPK_CH" -ge 2 ] && echo 2 || echo 1)

echo "== 5/6 PipeWire: static microphone + speaker"
mkdir -p "${RHOME}/.config/pipewire/pipewire.conf.d"
cat > "${RHOME}/.config/pipewire/pipewire.conf.d/50-speakerphone.conf" <<EOF
# speakerphone-assist: containers have no udev, so PipeWire cannot discover the card by itself.
context.objects = [
    { factory = adapter
        args = {
            factory.name     = api.alsa.pcm.source
            node.name        = "speakerphone_mic"
            node.description = "Speakerphone microphone"
            media.class      = "Audio/Source"
            api.alsa.path    = "hw:CARD=${CARD},DEV=0"
            audio.channels   = ${MIC_CH}
            audio.position   = [ $(pos "$MIC_CH") ]
            priority.session = 2000
        }
    }
    { factory = adapter
        args = {
            factory.name     = api.alsa.pcm.sink
            node.name        = "speakerphone_speaker"
            node.description = "Speakerphone speaker"
            media.class      = "Audio/Sink"
            api.alsa.path    = "hw:CARD=${CARD},DEV=0"
            audio.channels   = ${SPK_CH_USE}
            audio.position   = [ $(pos "$SPK_CH_USE") ]
            priority.session = 2000
        }
    }
]
EOF
chown -R "$RUSER:$RUSER" "${RHOME}/.config"
runuser -u "$RUSER" -- env XDG_RUNTIME_DIR="$RUN" systemctl --user restart pipewire pipewire-pulse wireplumber || true
sleep 3
if ! runuser -u "$RUSER" -- env XDG_RUNTIME_DIR="$RUN" pactl list short sources 2>/dev/null | grep -q speakerphone_mic; then
    echo "PipeWire did not create the microphone. Look at:  runuser -u $RUSER -- env XDG_RUNTIME_DIR=$RUN journalctl --user -u pipewire -n 30"
    echo "Most common reason: the card is busy (used by the host or another container)."
    exit 1
fi
echo "  PipeWire sees the speakerphone."

echo "== 6/6 systemd service"
cat > /etc/systemd/system/linux-voice-assistant.service <<EOF
[Unit]
Description=Linux Voice Assistant (speakerphone-assist)
After=network-online.target user@${RUID}.service
Wants=network-online.target

[Service]
Type=simple
User=${RUSER}
WorkingDirectory=${LVA}
Environment=XDG_RUNTIME_DIR=${RUN}
Environment=PULSE_SERVER=unix:${RUN}/pulse/native
ExecStart=${LVA}/.venv/bin/python -m linux_voice_assistant --name ${NAME} --audio-input-device "Speakerphone microphone" --audio-input-channels 1 --audio-output-device pulse/speakerphone_speaker --wake-model ${WAKE} --wake-word-dir ${RHOME}/wakewords --preferences-file ${RHOME}/lva-preferences.json
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
runuser -u "$RUSER" -- mkdir -p "${RHOME}/wakewords"
systemctl daemon-reload
systemctl enable --now linux-voice-assistant >/dev/null
sleep 6
systemctl --no-pager --lines=4 status linux-voice-assistant | sed -n '1,3p;/Server started/p' || true
echo
echo "Done. In Home Assistant: Settings -> Devices & services -> Discovered -> 'lva-<MAC>' (ESPHome) -> Add."
echo "After adding it is called '${NAME}'. Not discovered? Add integration -> ESPHome -> this machine's IP, port 6053."
echo "Your own wake words: put <id>.json (+ .tflite) into ${RHOME}/wakewords and run: systemctl restart linux-voice-assistant"
