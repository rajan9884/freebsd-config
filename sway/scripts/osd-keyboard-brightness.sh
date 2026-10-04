#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Keyboard-backlight OSD (FreeBSD 15.1 port).
#   freebsd-backlight drives the kbd node (base backlight(8) on FreeBSD,
#   brightnessctl passthrough on Linux); swayosd-client renders when
#   installed, else notify-send. `cycle` wraps max → off. No kbd node
#   (most desktops/VMs) is a silent no-op — the key never errors.
# ──────────────────────────────────────────────
ACTION="$1"
BL="$HOME/.local/bin/freebsd-backlight"
[ -x "$BL" ] || BL="freebsd-backlight"
# Keyboard node name fragment for the helper (--device does substring match
# against /dev/backlight/*; brightnessctl device globs pass through on Linux).
DEV_ARGS=(--device kbd)

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

_have_kbd() { # kbd node present?
    [ -d /dev/backlight ] && ls /dev/backlight 2>/dev/null | grep -qiE 'kbd|keyboard'
}

case "$ACTION" in
    up) "$BL" up 34 "${DEV_ARGS[@]}" ;;
    down) "$BL" down 34 "${DEV_ARGS[@]}" ;;
    cycle)
        LEVEL="$("$BL" get "${DEV_ARGS[@]}" 2>/dev/null)"
        if [[ "$LEVEL" =~ ^[0-9]+$ ]] && ((LEVEL >= 100)); then
            "$BL" set 0 "${DEV_ARGS[@]}"
        else
            "$BL" up 34 "${DEV_ARGS[@]}"
        fi
        ;;
esac

# swayosd-client is optional on FreeBSD (no port): never fail the key.
if ! _have_kbd && ! command -v brightnessctl >/dev/null 2>&1; then
    exit 0
fi
if command -v swayosd-client >/dev/null 2>&1; then
    swayosd-client --brightness=+0 --device kbd 2>/dev/null || true
else
    LEVEL_NOW="$("$BL" get "${DEV_ARGS[@]}" 2>/dev/null || echo "?")"
    notify-send -a "Keyboard" -i keyboard-brightness "Keyboard brightness: $LEVEL_NOW%" 2>/dev/null || true
fi
