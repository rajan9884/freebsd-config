#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   VPN status for Waybar (custom/vpn) — FreeBSD 15.1 
#   Shows an active tunnel (tun*/wg*) carrying an address, if any.
#   Covers wg(4)/WireGuard, OpenVPN (tun) and gif/gre tunnels alike:
#   any tunnel interface with an inet address counts as "VPN up".
# ──────────────────────────────────────────────
set -euo pipefail

active=""
for _if in $(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -E '^(tun|wg|tap)[0-9]+$' || true); do
    if ifconfig "$_if" 2>/dev/null | grep -qE 'inet (10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|[1-9])'; then
        active="$_if"
        break
    fi
done

if [ -n "${active:-}" ]; then
    jq -cn --arg name "$active" '{text: ("󰖂 " + $name), tooltip: ("VPN connected: " + $name), class: "vpn-on"}'
else
    jq -cn '{text: "󰖂", tooltip: "No VPN active", class: "vpn-off"}'
fi
