#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Waybar network status (custom/wifi) — FreeBSD 15.1 
#   Native stack: ifconfig(8) wlan + route(8). No NetworkManager.
#   Shows the connection actually carrying traffic:
#   Wi-Fi signal / wired ethernet / nothing.
# ──────────────────────────────────────────────
set -euo pipefail

I_SIG4=$'\U000F0928'     # md-wifi_strength_4
I_SIG3=$'\U000F0925'     # md-wifi_strength_3
I_SIG2=$'\U000F0922'     # md-wifi_strength_2
I_SIG1=$'\U000F091F'     # md-wifi_strength_1
I_SIG0=$'\U000F092D'     # md-wifi_strength_off
I_WIFIOFF=$'\U000F05AA'  # md-wifi_off
I_WIFIOUT=$'\U000F092F'  # md-wifi_strength_outline
I_ETHER=$'\U000F0200'    # md-ethernet
I_TETHER=$'\U000F0121'   # md-cellphone_link

signal_icon() {
    local s="$1"
    if (( s >= 80 )); then printf '%s' "$I_SIG4"
    elif (( s >= 60 )); then printf '%s' "$I_SIG3"
    elif (( s >= 40 )); then printf '%s' "$I_SIG2"
    elif (( s >= 20 )); then printf '%s' "$I_SIG1"
    else printf '%s' "$I_SIG0"; fi
}

wifi_ifaces() {
    ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^wlan[0-9]+$' || true
}

iface_ssid() {
    ifconfig "$1" 2>/dev/null | sed -n 's/.*ssid "\([^"]*\)".*/\1/p' | head -n 1
}

# RSSI (dBm, negative) of the associated AP -> 0..100%.
# `ifconfig wlan0 list sta` prints one line per station with an RSSI column.
iface_signal() {
    local rssi
    rssi=$(ifconfig "$1" list sta 2>/dev/null | awk 'NR>1 && $0 ~ /-?[0-9]+/ {
        for (i=1;i<=NF;i++) if ($i ~ /^-?[0-9]+$/ && $i+0<0 && $i+0>-120) { print $i+0; exit }
    }' | head -n 1)
    if [[ "$rssi" =~ ^-?[0-9]+$ ]]; then
        local pct=$(( (rssi + 100) * 2 ))
        (( pct < 0 )) && pct=0
        (( pct > 100 )) && pct=100
        printf '%s' "$pct"
    fi
}

is_usb_net() { # ue* / cdce* USB gadgets back tethering on FreeBSD
    case "$1" in ue*|cdce*|urndis*) return 0 ;; *) return 1 ;; esac
}

default_dev="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"

# Find the associated wlan (if any) and its signal.
wlan=""; ssid=""; signal="0"
for _w in $(wifi_ifaces); do
    _s=$(iface_ssid "$_w" || true)
    if [[ -n $_s ]]; then
        wlan=$_w; ssid=$_s
        _sig=$(iface_signal "$_w" || true)
        [[ -n ${_sig:-} ]] && signal=$_sig
        break
    fi
done

# Wi-Fi associated and carrying (or able to carry) traffic.
if [[ -n "${ssid:-}" ]] && { [[ "$default_dev" == wlan* ]] || [[ -z "$default_dev" ]]; }; then
    icon="$(signal_icon "${signal:-0}")"
    jq -cn --arg icon "$icon" --arg ssid "$ssid" --arg signal "${signal:-0}" \
        '{text:$icon, tooltip:("Wi-Fi: "+$ssid+" ("+$signal+"%)"), class:"wifi-on"}'
    exit 0
fi

# A wired/tethered link carries the traffic.
if [[ -n "$default_dev" ]]; then
    if is_usb_net "$default_dev"; then
        jq -cn --arg i "$I_TETHER" --arg dev "$default_dev" --arg ssid "${ssid:-}" \
            '{text:$i, tooltip:("USB tethering ("+$dev+")"+(if $ssid=="" then "" else " — Wi-Fi ("+$ssid+") also up" end)), class:"wifi-tether"}'
        exit 0
    fi
    case "$default_dev" in
        em*|igb*|ix*|re*|bge*|alc*|vtnet*|xn*|hn*)
            if [[ -n "${ssid:-}" ]]; then
                jq -cn --arg i "$I_ETHER" --arg dev "$default_dev" --arg ssid "$ssid" \
                    '{text:$i, tooltip:("Ethernet ("+$dev+") — Wi-Fi ("+$ssid+") also up"), class:"wifi-wired"}'
            else
                jq -cn --arg i "$I_WIFIOUT" --arg dev "$default_dev" \
                    '{text:$i, tooltip:("Wi-Fi disconnected — on Ethernet ("+$dev+") (click for menu)"), class:"wifi-disconnected"}'
            fi
            exit 0
            ;;
    esac
fi

# Wi-Fi up but another interface (tun/wg VPN, ppp, …) is the default route.
if [[ -n "${ssid:-}" ]]; then
    icon="$(signal_icon "${signal:-0}")"
    jq -cn --arg icon "$icon" --arg ssid "$ssid" --arg signal "${signal:-0}" \
        '{text:$icon, tooltip:("Wi-Fi: "+$ssid+" ("+$signal+"%)"), class:"wifi-on"}'
    exit 0
fi

jq -cn --arg i "$I_WIFIOUT" '{text:$i, tooltip:"Wi-Fi disconnected (click for menu)", class:"wifi-disconnected"}'
