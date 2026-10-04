#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Control Center (FreeBSD 15.1 port )
#   Native sources: ifconfig(8) wlan, mixer/wpctl, freebsd-backlight.
# ──────────────────────────────────────────────

THEME="$HOME/.config/rofi/control-center.rasi"
[ -f "$THEME" ] || THEME="$HOME/.config/rofi/active-scripts.rasi"
[ -f "$THEME" ] || THEME=""

# --- Functions to get stats ---
get_wifi() {
    local ssid=""
    for _w in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^wlan[0-9]+$'); do
        ssid=$(ifconfig "$_w" 2>/dev/null | sed -n 's/.*ssid "\([^"]*\)".*/\1/p' | head -n 1)
        [[ -n $ssid ]] && break
    done
    [ -z "$ssid" ] && echo "Off" || echo "$ssid"
}

get_bt() {
    # BlueZ bluetoothctl does not exist on FreeBSD; the base stack is
    # managed via rc.d/bluetooth + hccontrol. Report the service state.
    if command -v bluetoothctl >/dev/null 2>&1; then
        bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && echo "On" || echo "Off"
    elif service bluetooth status >/dev/null 2>&1; then
        echo "On"
    else
        echo "Off"
    fi
}

get_vol_bar() {
    local vol=""
    if command -v wpctl >/dev/null 2>&1; then
        vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
        if [[ -n $vol ]]; then
            vol=$(awk -v f="$vol" 'BEGIN{ printf "%d", f*100 }')
        fi
    fi
    if [[ -z ${vol:-} ]] && command -v mixer >/dev/null 2>&1; then
        vol=$(mixer vol 2>/dev/null | grep -oE '[0-9]+' | head -1)
    fi
    [[ "$vol" =~ ^[0-9]+$ ]] || vol=0
    local filled=$((vol / 10))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="󰝤"; done
    for ((i=filled; i<10; i++)); do bar+=" "; done
    echo "$bar $vol%"
}

get_bright_bar() {
    local percent=0
    percent=$(~/.local/bin/freebsd-backlight get 2>/dev/null || echo 0)
    [[ "$percent" =~ ^[0-9]+$ ]] || percent=0
    local filled=$((percent / 10))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="󰝤"; done
    for ((i=filled; i<10; i++)); do bar+=" "; done
    echo "$bar $percent%"
}

DND_STATE="$("$HOME/.config/sway/scripts/mako-dnd.sh" state 2>/dev/null || echo Off)"

# --- Prepare Menu Items ---
WIFI_SSID=$(get_wifi)
BT_STATE=$(get_bt)
VOL_BAR=$(get_vol_bar)
BRIGHT_BAR=$(get_bright_bar)

# One line per tile: rofi returns the clicked row verbatim, so a two-line
# tile (label row + value row) breaks matching when the value row is
# clicked. Status is appended inline instead.
MENU="󰖩  Wi-Fi — $WIFI_SSID\n"
MENU+="󰂯  Bluetooth — $BT_STATE\n"
MENU+="󰃠  Brightness — $BRIGHT_BAR\n"
MENU+="󰕾  Sound — $VOL_BAR\n"
MENU+="󰔉  Focus — $DND_STATE\n"
MENU+="󰹑  Mirroring — None\n"
MENU+="󰝚  Music — Not Playing\n"
MENU+="⏻  Power — System"

CHOICE=$(echo -e "$MENU" | rofi -dmenu -p "FreeBSD " -theme "$THEME" -i)

case "$CHOICE" in
    *"Wi-Fi"*)
        ~/.config/waybar/scripts/wifi-menu.sh ;;
    *"Bluetooth"*)
        ~/.config/waybar/scripts/bluetooth-menu.sh ;;
    *"Brightness"*)
        ~/.local/bin/freebsd-backlight up 10 ;;
    *"Sound"*)
        if command -v pavucontrol >/dev/null 2>&1; then
            pavucontrol
        else
            foot -e sh -c 'mixer; echo; echo "Press Enter to close..."; read -r'
        fi ;;
    *"Focus"*)
        "$HOME/.config/sway/scripts/mako-dnd.sh" toggle ;;
    *"Power"*)
        ~/.config/waybar/scripts/power-menu.sh ;;
esac
