#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   lock — lock the screen with the matugen-rendered swaylock config.
#   Falls back to swaylock defaults when no theme has been generated yet
#   (fresh install before the first sway-wall.sh run).
# ──────────────────────────────────────────────
set -u
CONFIG="$HOME/.config/sway/swaylock-config"
# pgrep is base on FreeBSD (pidof needs psmisc); accept either.
{ pgrep -x swaylock >/dev/null 2>&1 || pidof swaylock >/dev/null 2>&1; } && exit 0
if [ -s "$CONFIG" ]; then
    exec swaylock -C "$CONFIG" -f
else
    exec swaylock -f
fi
