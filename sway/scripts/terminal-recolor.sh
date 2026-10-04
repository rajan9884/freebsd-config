#!/usr/bin/env bash
# ──────────────────────────────────────────────
#   Live-recolor running foot windows after a matugen switch.
#   foot has no config-reload signal (SIGUSR1/2 only flip between the
#   dark/light themes loaded at startup), so existing windows keep the
#   old palette until restarted. Fix: push the fresh matugen palette
#   to every open terminal via OSC escape sequences —
#     OSC 10 = foreground, OSC 11 = background, OSC 12 = cursor,
#     OSC 4  = 16-color ANSI palette (what TUIs like htop/btop/fzf use).
#   The sequences are consumed by the terminal emulator itself, so they
#   are safe to send even when a fullscreen TUI is running (redraw with
#   Ctrl-L if anything looks stale). tmux/screen panes do NOT forward
#   OSC 4 outward — those need a tmux restart.
# ──────────────────────────────────────────────
set -euo pipefail

COLORS_FILE="$HOME/.config/foot/colors.ini"
[ -f "$COLORS_FILE" ] || exit 0

declare -A C=()
while IFS='=' read -r key value; do
    # Trim whitespace; skip sections/comments/blanks.
    key="${key//[[:space:]]/}"
    value="${value//[[:space:]]/}"
    [[ "$key" =~ ^(foreground|background|regular[0-7]|bright[0-7])$ ]] || continue
    [[ "$value" =~ ^[0-9a-fA-F]{6}$ ]] || continue
    C["$key"]="$value"
done < <(grep -E '^(foreground|background|regular[0-7]|bright[0-7])=' "$COLORS_FILE" || true)

[ -n "${C[foreground]:-}" ] && [ -n "${C[background]:-}" ] || exit 0

ESC=$'\e'
BEL=$'\a'
SEQ=""

# Foreground / background / cursor (first cursor field; foot's
# `cursor=<fg> <bg>` is a two-value key, grep above skips it on purpose).
SEQ+="${ESC}]10;#${C[foreground]}${BEL}"
SEQ+="${ESC}]11;#${C[background]}${BEL}"
CURSOR_RAW="$(grep -E '^cursor=' "$COLORS_FILE" | head -1 | cut -d= -f2 | awk '{print $1}' || true)"
if [[ "$CURSOR_RAW" =~ ^[0-9a-fA-F]{6}$ ]]; then
    SEQ+="${ESC}]12;#${CURSOR_RAW}${BEL}"
fi

# 16-color palette: regularN -> 0-7, brightN -> 8-15 (only complete pairs).
for i in 0 1 2 3 4 5 6 7; do
    [ -n "${C[regular$i]:-}" ] && SEQ+="${ESC}]4;$i;#${C[regular$i]}${BEL}"
done
for i in 0 1 2 3 4 5 6 7; do
    [ -n "${C[bright$i]:-}" ] && SEQ+="${ESC}]4;$((i + 8));#${C[bright$i]}${BEL}"
done

# Broadcast to every writable pty (payload has no newlines, so ONLCR
# translation can't garble it; emulators swallow unknown OSC safely).
count=0
for pts in /dev/pts/[0-9]*; do
    [ -w "$pts" ] || continue
    printf '%s' "$SEQ" > "$pts" 2>/dev/null && count=$((count + 1)) || true
done

echo "terminal-recolor: pushed palette to $count pty(ies)" >> "$HOME/.cache/sway-wall.log"
exit 0
