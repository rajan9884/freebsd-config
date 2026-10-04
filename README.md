# freebsd-config (FreeBSD 15.1 Sway desktop)

Sway-based Wayland desktop for **FreeBSD 15.1**, ported from
[void-config](https://github.com/rajan9884/void-config): same keybinds, same
matugen wallpaper theming, same rofi/waybar/foot/mako stack, with native
FreeBSD services underneath (pkg, rc.conf/sysrc, seatd, powerd, pf,
wpa_supplicant, OSS audio with optional PipeWire).

## Requirements

- FreeBSD 15.1-RELEASE, base install with network access
- A non-root user with sudo/doas rights (pw groupmod wheel -m <user>)
- Graphics: drm-kmod for your GPU + loader entry (Wayland needs modesetting)
- Git: pkg install git (the installer covers everything else)

Graphics driver (one-time, per machine):

    sudo pkg install drm-kmod
    sudo sysrc kld_list+="i915kms"   # Intel; amdgpu for AMD, nvidia-modeset for NVIDIA

Wireless (one-time, per machine):

    sudo kldload if_iwm
    sudo sysrc wlans_iwm0="wlan0"
    sudo sysrc ifconfig_wlan0="WPA SYNCDHCP"
    sudo vi /etc/wpa_supplicant.conf
    sudo service netif restart && sudo service routing restart

## Quick start

    git clone https://github.com/rajan9884/freebsd-config.git ~/freebsd-config
    cd ~/freebsd-config
    ./install.sh

Partial runs:

    ./install.sh --packages-only   # pkg packages + services only
    ./install.sh --links-only      # (re)create symlinks only
    ./install.sh --no-fonts        # skip the Nerd Font download
    ./install.sh --no-wallpapers   # skip the wallpaper collection download

Reboot after the first run so group membership (video, operator) and the
greetd login manager take effect.

## What the installer does

1. Packages: pkg update + install of packages.txt (bulk, per-package retry
   so branch-missing optionals never fail the run), then cargo fallbacks
   (matugen, awww) and pip helpers (autotiling, rofimoji).
2. Services: sysrc + service for dbus, seatd, powerd (+flags), ntpd, cron,
   pf, bluetooth, and greetd when installed.
3. Firewall: system/pf.conf to /etc/pf.conf (backup + pfctl -n validate).
4. Device access: system/devfs.rules freebsd_config ruleset activation.
5. Login manager: /etc/greetd/config.toml (tuigreet on VT8, ports paths)
   + sway.desktop dbus-run-session patch.
6. Privilege: wheel sudoers drop-in, doas.conf, pw groupmod wheel/video/operator.
7. Dotfiles: symlinks into ~/.config, ~/, ~/.local/bin (with arch-compat
   shims); backups to ~/.config-backup-freebsd-<timestamp>/.
8. Shell: zsh as login shell; sway autostart on ttyv0/ttyv1.
9. Fonts: JetBrainsMono Nerd Font download (best effort).
10. Wallpapers: wallpapers collection flatten + theme seeding.

Idempotent: re-running repairs anything missing.

## Repository layout

| Path | Deploys to | Purpose |
| ---- | ---------- | ------- |
| sway/ | ~/.config/sway | Compositor config, idle/lock, helper scripts |
| btop/ | ~/.config/btop | System monitor (matugen theme) |
| fastfetch/ | ~/.config/fastfetch | System info (explicit freebsd logo) |
| mimeapps.list | ~/.config/mimeapps.list | Default apps (imv, Text Editor, chromium) |
| waybar/ | ~/.config/waybar | Status bar, themes, module scripts |
| rofi/ | ~/.config/rofi | Launcher and menus |
| foot/ | ~/.config/foot | Terminal (matugen-themed) |
| nvim/ | ~/.config/nvim | Neovim configuration |
| mako/ | ~/.config/mako | Notification daemon |
| matugen/ | ~/.config/matugen | Color templates (source of truth) |
| xdg-desktop-portal/ | ~/.config/xdg-desktop-portal | Portal preferences |
| gtk-3.0/, gtk-4.0/ | ~/.config/... | GTK theming (matugen-regenerated) |
| shell/ | ~/.bashrc, ~/.zshrc, ... | BSD/GNU portable startup files |
| zsh/ | ~/.config/zsh | Dual-GitHub identity helpers |
| bin/ | ~/.local/bin/ | Screenshot/clipboard/wallpaper/power helpers |
| system/ | /etc/... via installer | pf.conf, devfs.rules, rc.conf.sample |
| packages.txt | - | pkg set for install.sh |
| install.sh | - | Reproducible setup script |

Generated files (sway/colors, waybar/colors.css, starship.toml, wallpaper
pointer) are git-ignored; matugen/templates/ are the versioned source.

## Theming pipeline

sway/scripts/sway-wall.sh <image> records the wallpaper, stages the lock
background, and runs matugen, recoloring Waybar, Rofi, Foot, Sway, mako,
SwayOSD, GTK, and Starship. Helpers: freebsd-wallpaper-picker,
random-wall.sh, init-wallpaper.sh.

## Post-install steps (not scripted)

- Wallpaper: seeded by installer; switch later with sway-wall.sh <image>.
- Browser: helium has no FreeBSD port; chromium is default (wrapper falls
  back automatically). Or pkg install firefox.
- GitHub: gh auth login, then git-work / git-personal per repo.
- SSH keys: github-work / github-personal host aliases in ~/.ssh/config.
- Passwordless menus: add to /usr/local/etc/doas.conf:
  permit nopass :wheel cmd shutdown  (+ cmd zzz).
- Backlight node: brightnessctl -l, then set BRIGHTNESSCTL_DEVICE or the
  waybar device (default intel_backlight).

## Shell notes

- Guarded inits: missing tools skipped silently; shell starts clean mid-install.
- ls uses -G/CLICOLOR on FreeBSD, --color=auto on Linux.
- zsh plugins: /usr/local/share/zsh/... with /usr/share fallback; fzf via
  fzf --zsh/--bash when available.
- svc aliased to sudo service (no runit vsv on FreeBSD).
- y (yazi), z (zoxide), ff (fzf), Atuin Ctrl-R in both shells.
- Login shells show fastfetch once (FreeBSD logo); subshells skip it.

## FreeBSD 15.1 porting map

| Void Linux | FreeBSD 15.1 here |
| ---------- | ----------------- |
| xbps-install | pkg install |
| runit (/etc/sv, vsv) | rc.conf + sysrc + service |
| elogind, input/_seatd groups | seatd, video group + devfs.rules |
| NetworkManager/nmcli/nmtui | native wlan + wpa_supplicant |
| power-profiles-daemon | base powerd (same CLI kept) |
| loginctl power verbs | bin/freebsd-power (shutdown, zzz; no S4) |
| ufw/nftables | base pf (system/pf.conf) |
| chrony/cronie | base ntpd/cron |
| ALSA + ~/.asoundrc | OSS (mixer) + optional PipeWire |
| udevadm, /sys, flock, grep -P, shuf, stat -c, readlink -f, sed -i, mktemp -t, sha256sum, pidof | devd/sysctl, mkdir locks, grep -E, awk+sort, stat -f, realpath, sed -i '', portable mktemp, sha256, pgrep |
| greetd VT7, /usr/sbin paths | tuigreet VT8, /usr/local paths |
| TTY /dev/tty1, XDG_VTNR | /dev/ttyv0/ttyv1 (Linux names matched too) |
| Void logo (waybar) | FreeBSD logo (waybar, fastfetch) |
| arch-* helper names | freebsd-* (+ compat shims) |
| helium-browser | chromium port (wrapper fallback) |
| awww/matugen via xbps | cargo install (swaybg fallback) |
| autotiling/rofimoji via xbps | pip install --user |
| SwayOSD, bluetoothctl, voxtype | optional; callers degrade gracefully |
| snd-perms runit service | deleted (no udev/ALSA coldplug) |

## Troubleshooting

- No graphical login: service greetd status; check /etc/greetd/config.toml.
  Without greetd, log in on TTY and start-sway runs automatically.
- Sway cannot start: groups (id -nG, need video), kldstat (GPU drm),
  XDG_RUNTIME_DIR (start-sway creates it when missing).
- No audio: mixer vol / cat /dev/sndstat for OSS; ps -x | grep pipewire
  and wpctl status for PipeWire.
- No Wi-Fi: kldstat (driver), ifconfig wlan0 up list scan, rc.conf wlans_*.
- Theme not applied: install matugen (cargo install matugen), then run
  sway-wall.sh <image> manually.
- Installer overwrote a file: see ~/.config-backup-freebsd-<timestamp>/.
