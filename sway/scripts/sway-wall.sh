#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Dynamic Theme Switcher (awww + matugen) — FreeBSD 15.1 port 
#   Usage: sway-wall.sh /path/to/wallpaper.jpg
#   awww is a cargo install here (no FreeBSD port): when the daemon is
#   absent the script uses swaybg/one-shot swaymsg instead — same theme
#   pipeline, simpler transition.
# ──────────────────────────────────────────────
set -euo pipefail

# Keybind-launched runs may have no session bus (greetd session without
# dbus-run-session): recover it from the snapshot file so notify-send,
# makoctl and the swayosd restart below all reach the bus instead
# of hanging/failing silently.
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

WALLPAPER="${1:-}"
[ -z "$WALLPAPER" ] && { echo "Usage: sway-wall.sh /path/to/wallpaper.jpg" >&2; exit 1; }
[ -f "$WALLPAPER" ] || { echo "Not found: $WALLPAPER" >&2; exit 1; }

# One switch at a time: rapid Super+R presses used to queue up full
# decode+transition+matugen+reload cycles, each slower than the last.
# mkdir is atomic and (unlike flock fds) can't leak into child processes.
LOCKDIR=/tmp/sway-wall.lockdir
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    # Stale lock (e.g. killed mid-run)? Reap after 2 minutes.
    if [ -n "$(find "$LOCKDIR" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
        rm -rf "$LOCKDIR" && mkdir "$LOCKDIR" 2>/dev/null || \
            { echo "wallpaper switch already in progress, skipping" >&2; exit 0; }
    else
        echo "wallpaper switch already in progress, skipping" >&2; exit 0
    fi
fi
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

# 1. Set wallpaper. Prefer awww-daemon when it is up (it paints over the
#    sway background, so the swaymsg fallback MUST only run when the
#    daemon is down — otherwise the output reconfigure aborts awww's
#    grow animation mid-flight and you see "no transition".
#    On FreeBSD awww may be entirely absent (cargo-only): then swaymsg is
#    the primary path, not a fallback.
if command -v awww >/dev/null 2>&1 && awww query >/dev/null 2>&1; then
    awww img "$WALLPAPER" --transition-type grow --transition-pos center --transition-duration 1.5 --transition-fps 30 || \
        { notify-send "Wallpaper Error" "awww failed to set $(basename "$WALLPAPER")" -u critical; exit 1; }
elif command -v awww-daemon >/dev/null 2>&1; then
    setsid awww-daemon >/dev/null 2>&1 < /dev/null &
    sleep 0.5
    if awww query >/dev/null 2>&1; then
        awww img "$WALLPAPER" --transition-type grow --transition-pos center --transition-duration 1.5 --transition-fps 30 || \
            { notify-send "Wallpaper Error" "awww failed to set $(basename "$WALLPAPER")" -u critical; exit 1; }
    else
        swaymsg output "*" bg "$WALLPAPER" fill || \
            { notify-send "Wallpaper Error" "Could not set $(basename "$WALLPAPER")" -u critical; exit 1; }
    fi
else
    swaymsg output "*" bg "$WALLPAPER" fill || \
        { notify-send "Wallpaper Error" "Could not set $(basename "$WALLPAPER")" -u critical; exit 1; }
fi

# 1.5 Record current wallpaper + stage lock-screen background (synchronous so
#    Super+R immediately followed by Super+Ctrl+L already shows the new image).
printf '%s' "$WALLPAPER" > "$HOME/.cache/current-wallpaper"
magick "$WALLPAPER" "$HOME/.cache/swaylock-bg.jpg" 2>/dev/null || cp -p "$WALLPAPER" "$HOME/.cache/swaylock-bg.jpg" 2>/dev/null || true

# 2. Extract colors with matugen (updates waybar, rofi, foot, sway, mako, …).
# matugen is cargo-installed on FreeBSD: without it the wallpaper still
# changes but the palette stays put (previous theme kept, no failure).
if command -v matugen >/dev/null 2>&1; then
    matugen image "$WALLPAPER" --type scheme-content -c ~/.config/matugen/config.toml --source-color-index 0
else
    notify-send -u low "Wallpaper set" "matugen missing — palette unchanged (cargo install matugen)"
fi

# 2.1 Restart swayosd-server so it picks up the new style.css (reads CSS
# only at startup). No-op when SwayOSD is not installed.
if command -v swayosd-server >/dev/null 2>&1; then
    pkill -x swayosd-server >/dev/null 2>&1 || true
    setsid swayosd-server >/dev/null 2>&1 < /dev/null &
fi

# 2.5 Bump unpacked Chromium theme version so the next launch picks up colors
THEME_MANIFEST="$HOME/.config/helium-theme/manifest.json"
if [ -f "$THEME_MANIFEST" ]; then
    CUR_VER=$(grep -o '"version": "[^"]*"' "$THEME_MANIFEST" | head -1 | cut -d'"' -f4)
    CUR_MAJ=$(echo "$CUR_VER" | cut -sd. -f1); [ -z "$CUR_MAJ" ] && CUR_MAJ=1
    CUR_MIN=$(echo "$CUR_VER" | cut -sd. -f2); [ -z "$CUR_MIN" ] && CUR_MIN=0
    CUR_PAT=$(echo "$CUR_VER" | cut -sd. -f3)
    case "$CUR_PAT" in ''|*[!0-9]*) CUR_PAT=0 ;; esac
    if [ "$CUR_PAT" -ge 65535 ] 2>/dev/null; then
        CUR_MIN=$((CUR_MIN + 1)); CUR_PAT=0
        [ "$CUR_MIN" -ge 65535 ] && { CUR_MAJ=$((CUR_MAJ + 1)); CUR_MIN=0; }
    fi
    NEW_VERSION="$CUR_MAJ.$CUR_MIN.$((CUR_PAT + 1))"
    # Portable in-place edit: BSD sed requires the '' backup argument.
    case "$(uname -s)" in
        FreeBSD|Darwin|*BSD) sed -i '' -E "s/\"version\": \"[^\"]+\"/\"version\": \"$NEW_VERSION\"/" "$THEME_MANIFEST" ;;
        *) sed -i -E "s/\"version\": \"[^\"]+\"/\"version\": \"$NEW_VERSION\"/" "$THEME_MANIFEST" ;;
    esac
    rm -f "$HOME/.config/helium-theme/Cached Theme.pak"
fi

# 3. Apply the theme WITHOUT swaymsg reload / output-bg commands: both
#    reconfigure outputs and flash the whole screen ~2s after the switch
#    (the "awkward animation") — and any `output * bg <image>` spawns a
#    swaybg that covers awww after the next reload (frozen-wallpaper bug:
#    colors change, picture looks stuck). Instead, resolve matugen's $vars
#    and push client.* colors live, and reload waybar in place (SIGUSR2 =
#    no bar blank). Reboots re-apply the image from
#    ~/.cache/current-wallpaper via init-wallpaper.sh at login.
rm -f ~/.config/sway/wallpaper
declare -A MC=()
while read -r _ name value; do
    [ -n "${name:-}" ] && [ -n "${value:-}" ] && MC["$name"]="$value"
done < <(grep '^set \$m_' ~/.config/sway/colors || true)
while read -r line; do
    if ((${#MC[@]})); then
        for k in "${!MC[@]}"; do line="${line//$k/${MC[$k]}}"; done
    fi
    case "$line" in *'$'*) continue;; esac
    swaymsg "$line" >/dev/null 2>&1 || true
done < <(grep '^client' ~/.config/sway/colors || true)
if pgrep -x waybar >/dev/null 2>&1; then
    pkill -USR2 -x waybar 2>/dev/null || true
elif pgrep -x .waybar-wrapped >/dev/null 2>&1; then
    pkill -USR2 -x .waybar-wrapped 2>/dev/null || true
else
    # Single-instance gated launch (shared with sway's autostart): waits
    # for the default sink and skips if a bar is already up, so this can
    # never stack a duplicate or a module-less bar at boot.
    ~/.config/sway/scripts/waybar-launch.sh >/dev/null 2>&1 < /dev/null &
fi

# 4. Live-recolor running terminals: foot has no config-reload signal
# (SIGUSR1/2 only flip dark/light themes loaded at startup), so push the
# fresh matugen palette to every open pty via OSC sequences. New foot
# windows still read ~/.config/foot/colors.ini automatically.
"$HOME/.config/sway/scripts/terminal-recolor.sh" >/dev/null 2>&1 || true

# 5. Reload mako with new colors (matugen writes ~/.config/mako/colors)
makoctl reload 2>/dev/null || { pkill -x mako 2>/dev/null; setsid mako >/dev/null 2>&1 < /dev/null & }

# 6. GTK apps read css at launch — restart nautilus only if a window is open
if swaymsg -t get_tree 2>/dev/null | grep -Fq '"app_id": "org.gnome.Nautilus"'; then
    pkill -x nautilus 2>/dev/null || true
    (nautilus --new-window >/dev/null 2>&1 &) || true
fi

# 7. Nudges for apps that need a restart
pgrep -x nvim >/dev/null 2>&1 && notify-send "Neovim Theme Updated" "Restart nvim to apply new colors" || true
if command -v pywalfox >/dev/null 2>&1; then
    timeout 10 pywalfox update 2>/dev/null || true
fi
if pgrep -x chromium >/dev/null 2>&1 || pgrep -x chromium-browser >/dev/null 2>&1 || pgrep -x brave >/dev/null 2>&1 || pgrep -x firefox >/dev/null 2>&1; then
    notify-send "Browser Theme Updated" "Fully quit the browser (all windows) and reopen to apply new colors" -i "$WALLPAPER"
fi

# 8. Done (no "Theme Updated" popup: notifications stay silent on switch;
# nvim/browser restart nudges above still fire when those apps run).
true
