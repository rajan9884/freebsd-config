#!/usr/bin/env bash
# Shows the active power profile for the waybar module; click opens the switcher.
# FreeBSD backend: power-profiles(1) reads powerd(8) state (see bin/power-profiles).

case "$(power-profiles get 2>/dev/null)" in
    performance) echo "󰓅 perf" ;;
    power-saver) echo "󰾆 save" ;;
    *) echo "󰾅 bal" ;;
esac
