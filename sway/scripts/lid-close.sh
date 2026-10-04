#!/usr/bin/env bash
# Lock the screen when the laptop lid closes (also wired via bindswitch).
# (Automatic suspend-on-lid is a powerd(8)/hw.acpi.lid_switch_state policy —
# see README. This hook only locks; it never suspends by itself.)
set -euo pipefail
{ pgrep -x swaylock >/dev/null 2>&1 || pidof swaylock >/dev/null 2>&1; } || exec "$(dirname "$0")/lock.sh"
