#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Volume OSD (FreeBSD 15.1 port).
#   PipeWire (pactl/wpctl) makes the change when present (exact 5% steps,
#   150% ceiling); otherwise native OSS mixer(8) is used so the keys stay
#   alive on systems without PipeWire.
#   swayosd-client renders icon + bar + percentage when installed; else
#   notify-send is the fallback. Every audio call is wrapped in timeout so
#   a stuck daemon can't hang the keys. No systemd/runit assumptions.
#   Portable parsing only: BSD grep has no -P (PCRE).
# ──────────────────────────────────────────────
ACTION="$1"
SINK="@DEFAULT_SINK@"
MAX=150

# Keybind-launched scripts may run without a session bus (greetd session
# without dbus-run-session): recover it from the snapshot file.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    for _busf in "${XDG_RUNTIME_DIR:-/nonexistent}/session-bus.address" "/var/run/user/$(id -u)/session-bus.address" "/run/user/$(id -u)/session-bus.address" "$HOME/.cache/session-bus"; do
        if [ -s "$_busf" ]; then
            DBUS_SESSION_BUS_ADDRESS=$(cat "$_busf")
            export DBUS_SESSION_BUS_ADDRESS
            break
        fi
    done
    unset _busf
fi

# 1. OSD backend: prefer swayosd-server, else notify-send.
if command -v swayosd-server >/dev/null 2>&1; then
    if ! pgrep -x swayosd-server >/dev/null 2>&1; then
        swayosd-server >/dev/null 2>&1 &
        sleep 0.4
    fi
    HAVE_OSD=1
else
    HAVE_OSD=0
fi

run_timeout() { timeout 3 "$@" 2>/dev/null; }

osd() { # osd <icon> <fraction-0..1> <text>
    if [ "$HAVE_OSD" = "1" ]; then
        run_timeout swayosd-client --custom-icon "$1" \
            --custom-progress "$2" --custom-progress-text "$3"
    else
        notify-send -a "Volume" -i "$1" "$3" 2>/dev/null || true
    fi
}

case "$ACTION" in
    up)
        run_timeout pactl set-sink-volume "$SINK" +5% \
        || run_timeout wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ \
        || mixer vol +5 >/dev/null 2>&1 ;;
    down)
        run_timeout pactl set-sink-volume "$SINK" -5% \
        || run_timeout wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- \
        || mixer vol -5 >/dev/null 2>&1 ;;
    mute-toggle)
        run_timeout pactl set-sink-mute "$SINK" toggle \
        || run_timeout wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle \
        || mixer vol ^ >/dev/null 2>&1 ;;
    mic-toggle)
        if [ "$HAVE_OSD" = "1" ]; then
            run_timeout swayosd-client --input-volume mute-toggle
        else
            run_timeout wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle 2>/dev/null \
                || notify-send -a "Volume" "Microphone toggle needs PipeWire or SwayOSD" 2>/dev/null || true
        fi
        exit 0 ;;
esac

# Portable percentage parse (no grep -P): pactl prints "… 75% …".
PCT=$(run_timeout pactl get-sink-volume "$SINK" | grep -oE '[0-9]+%' | tr -d '%' | head -1)
# Fallback: wpctl reports "Volume: 0.75" (fraction) or "0.75 [MUTED]".
if [[ -z "$PCT" ]]; then
    FRAC_RAW=$(run_timeout wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [[ -n "$FRAC_RAW" ]]; then
        PCT=$(awk -v f="$FRAC_RAW" 'BEGIN{ printf "%d", f*100 }')
    fi
fi
# Fallback: native OSS mixer prints e.g. "Mixer vol is currently set to 75:75".
if [[ -z "$PCT" ]]; then
    MIXER_RAW=$(mixer vol 2>/dev/null | grep -oE '[0-9]+' | head -1)
    if [[ -n "$MIXER_RAW" ]]; then
        PCT="$MIXER_RAW"
    fi
fi

# Audio stack unreachable: still show an OSD so the key feels alive.
if [[ -z "$PCT" ]]; then
    osd audio-volume-muted 0 "No audio"
    exit 0
fi

if [ "$PCT" -gt "$MAX" ]; then
    run_timeout pactl set-sink-volume "$SINK" "$MAX%" \
    || run_timeout wpctl set-volume @DEFAULT_AUDIO_SINK@ "$MAX%" || true
    PCT=$MAX
fi

MUTED=0
if run_timeout pactl get-sink-mute "$SINK" 2>/dev/null | grep -q yes \
    || run_timeout wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -qi '\[MUTED\]' \
    || mixer vol 2>/dev/null | grep -qi mute; then
    MUTED=1
fi

if [ "$MUTED" = "1" ]; then
    ICON="audio-volume-muted"
    TEXT="Muted"
elif [ "$PCT" -ge 70 ]; then
    ICON="audio-volume-high"
    TEXT="$PCT%"
elif [ "$PCT" -ge 35 ]; then
    ICON="audio-volume-medium"
    TEXT="$PCT%"
else
    ICON="audio-volume-low"
    TEXT="$PCT%"
fi

FRAC=$(awk -v p="$PCT" -v m="$MAX" 'BEGIN{ f=p/m; if (f>1) f=1; if (f<0) f=0; printf "%.2f", f }')
osd "$ICON" "$FRAC" "$TEXT"
