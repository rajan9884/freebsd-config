#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Brightness OSD (FreeBSD 15.1 port).
#   freebsd-backlight makes the change (exact 5% steps via base
#   backlight(8); brightnessctl passthrough on Linux); swayosd-client
#   renders icon + bar + percentage when installed, else notify-send.
#   Backlight device varies by driver: set BACKLIGHT_DEVICE to a
#   /dev/backlight/* name fragment when yours is not probed first.
# ──────────────────────────────────────────────
ACTION="$1"
BL="$HOME/.local/bin/freebsd-backlight"
[ -x "$BL" ] || BL="freebsd-backlight"

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

# 1. OSD backend: swayosd-server when installed, else notify-send.
if command -v swayosd-server >/dev/null 2>&1; then
    if ! pgrep -x swayosd-server >/dev/null 2>&1; then
        swayosd-server >/dev/null 2>&1 &
        sleep 0.4
    fi
    HAVE_OSD=1
else
    HAVE_OSD=0
fi
osd() { # osd <fraction> <text>
    if [ "$HAVE_OSD" = "1" ]; then
        timeout 3 swayosd-client --custom-icon display-brightness \
            --custom-progress "$1" --custom-progress-text "$2" 2>/dev/null || true
    else
        notify-send -a "Brightness" -i display-brightness "$2" 2>/dev/null || true
    fi
}

case "$ACTION" in
    up) "$BL" up 5 ;;
    down) "$BL" down 5 ;;
    max) "$BL" set 100 ;;
    min) "$BL" set 1 ;;
esac

PCT="$("$BL" get 2>/dev/null)"
[[ "$PCT" =~ ^[0-9]+$ ]] || PCT=0
if [ "$PCT" = "0" ] && ! ls /dev/backlight 2>/dev/null | grep -q . \
    && ! command -v brightnessctl >/dev/null 2>&1; then
    osd 0 "No backlight"
    exit 0
fi
FRAC=$(awk -v p="$PCT" 'BEGIN{ f=p/100; if (f>1) f=1; if (f<0) f=0; printf "%.2f", f }')

osd "$FRAC" "$PCT%"
# Persist level for login restore (see sway config backlight-restore).
"$BL" save
