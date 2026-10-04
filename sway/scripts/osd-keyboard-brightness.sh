#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Keyboard-backlight OSD via swayosd-server.
#   `cycle` wraps max → off (brightnessctl has no wrap for kbd).
# ──────────────────────────────────────────────
ACTION="$1"
DEV="*kbd*"

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

case "$ACTION" in
    up) brightnessctl --device="$DEV" set 1+ >/dev/null 2>&1 ;;
    down) brightnessctl --device="$DEV" set 1- >/dev/null 2>&1 ;;
    cycle)
        LEVEL=$(brightnessctl --device="$DEV" get 2>/dev/null)
        MAX=$(brightnessctl --device="$DEV" max 2>/dev/null)
        if [[ "$LEVEL" =~ ^[0-9]+$ && "$MAX" =~ ^[0-9]+$ ]] && ((MAX > 0)) && ((LEVEL >= MAX)); then
            brightnessctl --device="$DEV" set 0 >/dev/null 2>&1
        else
            brightnessctl --device="$DEV" set 1+ >/dev/null 2>&1
        fi
        ;;
esac

# swayosd-client is optional on FreeBSD (no port guarantee): never fail the key.
if command -v swayosd-client >/dev/null 2>&1; then
    swayosd-client --brightness=+0 --device "$DEV" 2>/dev/null || true
else
    LEVEL_NOW=$(brightnessctl --device="$DEV" get 2>/dev/null || echo "?")
    notify-send -a "Keyboard" -i keyboard-brightness "Keyboard brightness: $LEVEL_NOW" 2>/dev/null || true
fi
