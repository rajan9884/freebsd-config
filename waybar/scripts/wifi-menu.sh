#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Wi-Fi / Network Menu for Waybar (FreeBSD 15.1 )
#   Native stack: ifconfig(8) + wpa_supplicant.conf. No NetworkManager.
#
#   Honest scope: FreeBSD joins networks via /etc/wpa_supplicant.conf
#   (root-owned) + netif, so this menu manages what an unprivileged user
#   can do — status, rescan, interface up/down, netif restart, QR share,
#   details — and opens the config in an editor for (re)configuration.
#   Anything needing root escalates with sudo/doas and reports failures
#   via notification instead of hanging.
# ──────────────────────────────────────────────

THEME="$HOME/.config/rofi/wifi-menu.rasi"

I_SIG4=$'\U000F0928'     # md-wifi_strength_4
I_SIG3=$'\U000F0925'     # md-wifi_strength_3
I_SIG2=$'\U000F0922'     # md-wifi_strength_2
I_SIG1=$'\U000F091F'     # md-wifi_strength_1
I_SIG0=$'\U000F092D'     # md-wifi_strength_off
I_WIFIOUT=$'\U000F092F'  # md-wifi_strength_outline
I_LOCK=$'\U000F033E'     # md-lock
I_HIDDEN=$'\U000F0209'   # md-eye_off
I_DETAILS=$'\U000F02FD'  # md-information_outline
I_EDIT=$'\U000F062E'     # md-tune
I_LINKOFF=$'\U000F0338'  # md-link_off
I_NET=$'\U000F1616'      # md-connection
I_CHEVRON=$'\U000F0142'  # md-chevron_right
I_CHECK=$'\U000F012C'    # md-check
I_QR=$'\U000F0432'       # md-qrcode
I_SCAN=$'\U000F0437'     # md-radar

FOOTER=""

notify() {
    local dur=4000
    if [[ "$1" == "-t" ]]; then dur="$2"; shift 2; fi
    notify-send -a "Network" -i network-wireless -t "$dur" "$1" "$2"
}

run_priv() {
    if [ "$(id -u)" -eq 0 ]; then "$@" && return 0; return 1; fi
    if command -v sudo >/dev/null 2>&1 && sudo -n "$@" 2>/dev/null; then return 0; fi
    if command -v doas >/dev/null 2>&1 && doas -n "$@" 2>/dev/null; then return 0; fi
    if [ -t 0 ]; then
        if command -v sudo >/dev/null 2>&1; then sudo "$@" && return 0; fi
        if command -v doas >/dev/null 2>&1; then doas "$@" && return 0; fi
    fi
    return 1
}

wifi_iface() {
    # First associated wlan, else first wlan.
    local _w _s
    for _w in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^wlan[0-9]+$'); do
        _s=$(ifconfig "$_w" 2>/dev/null | sed -n 's/.*ssid "\([^"]*\)".*/\1/p' | head -n 1)
        if [[ -n $_s ]]; then printf '%s' "$_w"; return 0; fi
    done
    ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^wlan[0-9]+$' | head -n 1
}

iface_ssid() {
    ifconfig "$1" 2>/dev/null | sed -n 's/.*ssid "\([^"]*\)".*/\1/p' | head -n 1
}

signal_icon() {
    local s="$1"
    if (( s >= 80 )); then printf '%s' "$I_SIG4"
    elif (( s >= 60 )); then printf '%s' "$I_SIG3"
    elif (( s >= 40 )); then printf '%s' "$I_SIG2"
    elif (( s >= 20 )); then printf '%s' "$I_SIG1"
    else printf '%s' "$I_SIG0"; fi
}

# Scan via ifconfig(8). SSIDs may contain spaces, so the BSSID (MAC) anchors
# the parse: everything before it is the SSID, RSSI is numeric after it.
# Tab-separated output (BSD awk has no \x-hex escapes, \t is universal).
scan_networks() { # scan_networks <iface> -> "signal<TAB>ssid<TAB>secure" lines
    ifconfig "$1" up list scan 2>/dev/null | awk '
    function ismac(f) { return (f ~ /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/) }
    {
        mac_idx = 0
        for (i = 1; i <= NF; i++) if (ismac($i)) { mac_idx = i; break }
        if (!mac_idx) next
        ssid = ""
        for (i = 1; i < mac_idx; i++) ssid = (ssid == "" ? $i : ssid " " $i)
        gsub(/^ +| +$/, "", ssid)
        if (ssid == "") next
        sig = 0
        for (i = mac_idx + 1; i <= NF; i++) {
            if ($i ~ /^-?[0-9]+$/ && $i + 0 < 0 && $i + 0 > -120) { sig = $i + 0; break }
        }
        pct = int((sig + 100) * 2)
        if (pct < 0) pct = 0
        if (pct > 100) pct = 100
        secure = ($0 ~ /WPA|RSN|WEP|PRIVACY|privacy/) ? "secure" : "open"
        print pct "\t" ssid "\t" secure
    }' | sort -t "$(printf '\t')" -k1,1nr | awk -F '\t' '!seen[$2]++'
}

row() {
    local icon="$1" label="$2" acc="${3:-}"
    printf '%s  %-24s%s\n' "$icon" "$label" "$acc"
}

pango_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    printf '%s' "$s"
}

build_menu() {
    local iface ssid
    iface="$(wifi_iface)"
    if [[ -z "$iface" ]]; then
        FOOTER="No wlan interface — add wlans_<driver>=\"wlan0\" to /etc/rc.conf"
        row "$I_WIFIOUT" "No Wi-Fi interface"
        row "$I_EDIT" "Edit rc.conf…" "$I_CHEVRON"
        return
    fi

    ssid="$(iface_ssid "$iface")"
    if [[ -n "$ssid" ]]; then
        FOOTER="$I_CHECK Connected: $ssid on $iface — click a network for actions"
    else
        FOOTER="Not connected on $iface — join via wpa_supplicant (see Edit)"
    fi

    {
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            IFS="$(printf '\t')" read -r sig net sec <<< "$line"
            [[ -z "$net" || "$net" == "$ssid" ]] && continue
            local acc=""
            [[ "$sec" == "secure" ]] && acc="$I_LOCK"
            row "$(signal_icon "$sig")" "$net" "$acc"
        done
    } < <(scan_networks "$iface")

    if [[ -n "$ssid" ]]; then
        row "$I_LINKOFF" "Disconnect ($ssid)"
    fi
    row "$I_SCAN" "Rescan"
    row "$I_QR" "Share current via QR…" "$I_CHEVRON"
    row "$I_DETAILS" "Connection Details…" "$I_CHEVRON"
    row "$I_EDIT" "Edit wpa_supplicant…" "$I_CHEVRON"
    row "$I_NET" "Restart networking ($iface)"
}

connection_details() {
    local iface="$1" details
    details="$(ifconfig "$iface" 2>/dev/null | head -n 12)"
    if [[ -z "$details" ]]; then
        notify "No connection" "No Wi-Fi interface to inspect"
        return
    fi
    notify -t 8000 "$iface" "$details"
}

handle_selection() {
    local choice="$1" iface="$2"
    choice="${choice%"${choice##*[![:space:]]}"}"

    case "$choice" in
        "$I_SCAN  Rescan")
            ifconfig "$iface" up scan 2>/dev/null || ifconfig "$iface" up list scan >/dev/null 2>&1
            notify "Scanning…" "Rescan kicked on $iface"
            sleep 2
            main ;;

        "$I_QR  Share current via QR…"*)
            if command -v wifi-share-prompt >/dev/null 2>&1; then
                wifi-share-prompt "$iface" &
            elif command -v wifi-share >/dev/null 2>&1; then
                foot --app-id=wifi-share -e bash -c "wifi-share $iface; echo; echo 'Press Enter to close...'; read -r" &
            else
                notify "Missing helper" "wifi-share not on PATH"
            fi ;;

        "$I_DETAILS  Connection Details…"*)
            connection_details "$iface" ;;

        "$I_EDIT  Edit wpa_supplicant…"*)
            # Joining a network = adding a network{} block, then netif restart.
            # Needs root: open in a terminal editor with escalation.
            if command -v sudo >/dev/null 2>&1; then
                foot -e sh -c "sudo ${EDITOR:-vi} /etc/wpa_supplicant.conf; echo 'Saved. Restart networking from this menu to apply.'" &
            elif command -v doas >/dev/null 2>&1; then
                foot -e sh -c "doas ${EDITOR:-vi} /etc/wpa_supplicant.conf; echo 'Saved. Restart networking from this menu to apply.'" &
            else
                notify "No escalation" "Install sudo/doas, then edit /etc/wpa_supplicant.conf"
            fi ;;

        "$I_NET  Restart networking"*)
            if run_priv service netif restart "$iface" 2>/dev/null \
                || run_priv service netif restart 2>/dev/null; then
                notify "Networking restarted" "$iface reassociating…"
            else
                notify "Restart failed" "Need privilege (sudo/doas) for service netif"
            fi
            sleep 1
            main ;;

        "$I_LINKOFF  Disconnect"*)
            # Disassociate without powering the radio down.
            if run_priv ifconfig "$iface" ssid '""' 2>/dev/null; then
                notify "Disconnected" "Disassociated on $iface"
            elif run_priv ifconfig "$iface" down 2>/dev/null; then
                run_priv ifconfig "$iface" up 2>/dev/null || true
                notify "Disconnected" "Cycled $iface down/up"
            else
                notify "Disconnect failed" "Need privilege (sudo/doas)"
            fi
            sleep 1
            main ;;

        "$I_SIG4"*|"$I_SIG3"*|"$I_SIG2"*|"$I_SIG1"*|"$I_SIG0"*|"$I_WIFIOUT"*)
            # A scanned network row: joining needs a wpa_supplicant block.
            # Collect the PSK here, then append the block privileged.
            local net
            net="$(python3 - "$choice" <<'PY'
import sys, re
s = sys.argv[1]
toks = [t for t in re.split(r"\s{2,}", s) if t]
print(toks[1] if len(toks) >= 2 else "")
PY
)"
            [[ -z "$net" ]] && return
            local pw rc
            pw="$(rofi -dmenu -password -p "PSK for $net (empty = open)" -theme "$HOME/.config/rofi/wifi-input.rasi")"
            rc=$?
            # Escape cancels (nonzero) — an empty PSK with OK means open.
            [[ $rc -ne 0 ]] && return 0
            local block
            if [[ -z "$pw" ]]; then
                block=$(printf 'network={\n\tssid="%s"\n\tkey_mgmt=NONE\n}\n' "$net")
            else
                # Escape backslash/quote for the supplicant string syntax.
                local esc
                esc=$(printf '%s' "$pw" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
                block=$(printf 'network={\n\tssid="%s"\n\tpsk="%s"\n}\n' "$net" "$esc")
            fi
            if printf '%s\n' "$block" | run_priv tee -a /etc/wpa_supplicant.conf >/dev/null \
                && run_priv service netif restart "$iface" >/dev/null 2>&1; then
                notify "Connecting…" "Added $net, reassociating on $iface"
            else
                notify "Join failed" "Need privilege to write /etc/wpa_supplicant.conf"
            fi
            sleep 1
            main ;;

        *)
            notify "Nothing selected" "Pick a network or an action"
            ;;
    esac
}

main() {
    local choice tmp iface
    tmp="$(mktemp "${TMPDIR:-/tmp}/wifi-menu-XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    FOOTER=""
    iface="$(wifi_iface)"
    build_menu > "$tmp"
    choice="$(rofi -dmenu -i \
        -selected-row 0 \
        -hover-select \
        -me-select-entry '' \
        -me-accept-entry MousePrimary \
        -p "$I_SIG4  Wi-Fi" \
        -mesg "$(pango_escape "$FOOTER")" \
        -theme "$THEME" < "$tmp")"
    [[ -z "$choice" ]] && exit 0
    handle_selection "$choice" "$iface"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
