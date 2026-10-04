#!/bin/sh
# Gated single-instance waybar launcher (FreeBSD 15.1 port).
# Used by sway's autostart AND sway-wall.sh's fallback — both used to fire
# at boot within a second of each other, stacking two bars.
# 1. Gate: wait for a real PipeWire default sink (launching earlier leaves
#    the pulseaudio module permanently hidden). Skipped entirely on OSS-only
#    systems where neither pactl nor wpctl exists (no PipeWire to wait for).
# 2. Mutex: atomic mkdir serializes concurrent callers (FreeBSD base has no
#    flock(1); lockf(1) cannot guard a detached setsid child, so the mkdir
#    lockdir pattern from sway-wall.sh is used). Non-blocking on purpose:
#    the loser just exits instead of hanging. Stale locks (>2 min, e.g.
#    killed mid-start) are reaped so the bar can never wedge missing.
if command -v pactl >/dev/null 2>&1 || command -v wpctl >/dev/null 2>&1; then
    for i in $(seq 1 30); do
        if command -v pactl >/dev/null 2>&1; then
            s=$(pactl get-default-sink 2>/dev/null) || s=""
        else
            s=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null) || s=""
        fi
        case "$s" in
            ""|*auto_null*) sleep 0.5;;
            *) break;;
        esac
    done
fi
LOCKDIR="${XDG_RUNTIME_DIR:-/tmp}/waybar-launch.lockdir"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    if [ -n "$(find "$LOCKDIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
        rm -rf "$LOCKDIR" 2>/dev/null || true
        mkdir "$LOCKDIR" 2>/dev/null || exit 0
    else
        exit 0
    fi
fi
# Re-check inside the lock so only one bar ever starts.
pgrep -x waybar >/dev/null 2>&1 || pgrep -x .waybar-wrapped >/dev/null 2>&1 \
    || setsid waybar -c ~/.config/waybar/config.jsonc -s ~/.config/waybar/style.css >/dev/null 2>&1 < /dev/null &
# Keep the mutex until the new bar registers, so a second caller firing in
# the same second still serializes instead of stacking a duplicate.
for i in $(seq 1 20); do
    pgrep -x waybar >/dev/null 2>&1 || pgrep -x .waybar-wrapped >/dev/null 2>&1 && break
    sleep 0.5
done
rmdir "$LOCKDIR" 2>/dev/null || true
