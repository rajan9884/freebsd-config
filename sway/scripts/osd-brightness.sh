#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Brightness OSD (FreeBSD 15.1 port).
#   brightnessctl makes the change (exact 5% steps, backlight
#   class only); swayosd-client renders icon + bar + percentage
#   when installed, else notify-send. (swayosd's own ±N math is
#   percent-based and asymmetric — not trustworthy here.)
#   FreeBSD backlight devices differ by driver (acpi_video0,
#   intel_backlight, …): `-c backlight` picks the class default;
#   override with BRIGHTNESSCTL_DEVICE if yours is not first.
# ──────────────────────────────────────────────
ACTION="$1"
DEV_ARGS=()
[ -n "${BRIGHTNESSCTL_DEVICE:-}" ] && DEV_ARGS=(--device="$BRIGHTNESSCTL_DEVICE")

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
    up) brightnessctl "${DEV_ARGS[@]}" -c backlight set 5%+ >/dev/null 2>&1 ;;
    down) brightnessctl "${DEV_ARGS[@]}" -c backlight set 5%- >/dev/null 2>&1 ;;
    max) brightnessctl "${DEV_ARGS[@]}" -c backlight set 100% >/dev/null 2>&1 ;;
    min) brightnessctl "${DEV_ARGS[@]}" -c backlight set 1% >/dev/null 2>&1 ;;
esac

INFO=$(brightnessctl "${DEV_ARGS[@]}" -c backlight -m 2>/dev/null | head -1)
if [[ -z "$INFO" ]]; then
    osd 0 "No backlight"
    exit 0
fi
CUR=$(printf '%s' "$INFO" | cut -d, -f3)
MAXV=$(printf '%s' "$INFO" | cut -d, -f5)
PCT=$(printf '%s' "$INFO" | cut -d, -f4 | tr -d '%')
[[ "$CUR" =~ ^[0-9]+$ ]] || CUR=0
[[ "$MAXV" =~ ^[0-9]+$ && "$MAXV" != "0" ]] || MAXV=100
[[ "$PCT" =~ ^[0-9]+$ ]] || PCT=0
FRAC=$(awk -v c="$CUR" -v m="$MAXV" 'BEGIN{ f=(m>0)?c/m:0; if (f>1) f=1; if (f<0) f=0; printf "%.2f", f }')

osd "$FRAC" "$PCT%"
# Persist raw value for login restore (see sway config backlight-restore).
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}" 2>/dev/null
printf '%s\n' "$CUR" > "${XDG_STATE_HOME:-$HOME/.local/state}/backlight" 2>/dev/null || true
