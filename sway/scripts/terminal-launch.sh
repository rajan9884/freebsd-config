#!/usr/bin/env bash
# Open a new foot terminal in the working directory of the currently
# focused window (uses swaymsg).
# Fast path: one swaymsg + one jq + one ps snapshot, zero forks per process.
# Foot starts instantly (native C), so no single-instance daemon is needed:
# every launch is a cold `foot -D`.
# Portable cwd resolution: Linux reads /proc/<pid>/cwd via readlink -f;
# FreeBSD has realpath(1) and no /proc by default — procstat(1) is the
# native fallback (needs procfs-free `procstat -f <pid>` file table scan).
set -u
# Resolve a process cwd portably: realpath > readlink -f > procstat > empty.
resolve_cwd() { # resolve_cwd <pid> -> prints dir or nothing
    local _pid="$1" _cwd=""
    if [ -d "/proc/$_pid/cwd" ] || [ -L "/proc/$_pid/cwd" ]; then
        if command -v realpath >/dev/null 2>&1; then
            _cwd=$(realpath "/proc/$_pid/cwd" 2>/dev/null || true)
        else
            _cwd=$(readlink -f "/proc/$_pid/cwd" 2>/dev/null || true)
        fi
    elif command -v procstat >/dev/null 2>&1; then
        # procstat -f lists open files; the cwd entry is flagged "cwd".
        _cwd=$(procstat -f "$_pid" 2>/dev/null | awk '$0 ~ / cwd / || $NF == "cwd" {print $NF; exit}' || true)
        # procstat prints the path in the last column for cwd rows on
        # FreeBSD 14/15; validate before trusting it.
        case "$_cwd" in /*) ;; *) _cwd="" ;; esac
    fi
    [ -n "$_cwd" ] && [ -d "$_cwd" ] && printf '%s' "$_cwd"
}
dir="$HOME"
pid="$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | objects | select(.focused == true) | .pid // empty' 2>/dev/null | head -n 1 || true)"
if [[ -n "${pid:-}" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
    # Build parent->children map + comm table from a single ps snapshot.
    declare -A kids=() comms=()
    while read -r p pp c; do
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        comms[$p]="$c"
        kids[$pp]="${kids[$pp]:-} $p"
    done < <(ps -eo pid=,ppid=,comm= 2>/dev/null || true)
    # BFS from the focused pid; newest shell descendant wins (outermost loop
    # order), falling back to the focused pid's own cwd.
    declare -A seen=()
    queue=("$pid")
    while ((${#queue[@]})); do
        cur=${queue[0]}
        queue=("${queue[@]:1}")
        [[ -n "${seen[$cur]:-}" ]] && continue
        seen[$cur]=1
        # shellcheck disable=SC2086
        for c in ${kids[$cur]:-}; do
            queue+=("$c")
            case "${comms[$c]:-}" in
                zsh|bash|fish|sh)
                    cwd=$(resolve_cwd "$c" || true)
                    [[ -n "$cwd" && -d "$cwd" ]] && dir="$cwd"
                    ;;
            esac
        done
    done
    if [[ "$dir" == "$HOME" ]]; then
        cwd=$(resolve_cwd "$pid" || true)
        [[ -n "$cwd" && -d "$cwd" ]] && dir="$cwd"
    fi
fi
# Prefer footclient when a `foot --server` is running (shares fonts/glyph
# cache); fall back to a plain cold launch otherwise. The plain launch
# re-reads ~/.config/foot/colors.ini, so matugen re-themes always apply to
# new windows (server clients inherit the server's startup palette until it
# restarts — plain foot is therefore the default path).
FOOT_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/foot-$WAYLAND_DISPLAY.sock"
if [[ -S "$FOOT_SOCK" ]] && command -v footclient >/dev/null 2>&1 \
    && footclient -D "$dir" >/dev/null 2>&1; then
    exit 0
fi
exec foot -D "$dir"
