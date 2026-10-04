#!/usr/bin/env bash
#
# freebsd-config installer — reproduce this Sway desktop on FreeBSD 15.1.
#
# Usage:
#   git clone https://github.com/rajan9884/freebsd-config.git ~/freebsd-config
#   cd ~/freebsd-config
#   ./install.sh [options]
#
# Options:
#   --packages-only   install pkg packages and enable services, skip dotfile links
#   --links-only      only (re)create ~/.config ~/ ~/.local/bin symlinks
#   --no-fonts        skip the Nerd Font download step
#   --no-wallpapers   skip the wallpaper collection download step
#   -h, --help        show this help and exit
#
# FreeBSD conventions followed: pkg(8) for packages, sysrc(8)/service(8) for
# services, pw(8) for groups, pf(4) for the firewall, /usr/local prefix for
# ports, rc.conf-style service names, devfs.rules(5) for device access.
#
# The script is idempotent: re-running it repairs missing links/packages.
# Existing files that would be replaced are backed up to
# ~/.config-backup-freebsd-<timestamp>/ first.
#

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$REPO_DIR/packages.txt"
BACKUP_DIR="$HOME/.config-backup-freebsd-$(date +%Y%m%d-%H%M%S)"

DO_PACKAGES=1
DO_LINKS=1
DO_FONTS=1
DO_WALLPAPERS=1

for arg in "$@"; do
    case "$arg" in
        --packages-only) DO_LINKS=0 ;;
        --links-only) DO_PACKAGES=0; DO_FONTS=0; DO_WALLPAPERS=0 ;;
        --no-fonts) DO_FONTS=0 ;;
        --no-wallpapers) DO_WALLPAPERS=0 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 1 ;;
    esac
done

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install] WARNING: %s\n' "$*" >&2; }

# ---------------------------------------------------------------- guards ---
if [ "$(uname -s 2>/dev/null)" != "FreeBSD" ]; then
    echo "This installer targets FreeBSD (uname -s did not report FreeBSD)." >&2
    exit 1
fi
if command -v freebsd-version >/dev/null 2>&1; then
    _ver="$(freebsd-version 2>/dev/null || true)"
    case "$_ver" in
        15.1*) log "Detected $_ver (supported)" ;;
        *) warn "Detected $_ver — this port targets 15.1-RELEASE; continuing best-effort" ;;
    esac
    unset _ver
fi

if [ "$(id -u)" -eq 0 ]; then
    echo "Run as your normal user (with sudo/doas rights), not as root." >&2
    exit 1
fi

if [ "$DO_PACKAGES" -eq 1 ]; then
    if command -v sudo >/dev/null 2>&1; then
        PRIV="sudo"
    elif command -v doas >/dev/null 2>&1; then
        PRIV="doas"
    else
        echo "Neither sudo nor doas found; install one first (e.g. pkg install doas) and retry." >&2
        exit 1
    fi
    log "Privilege escalation: $PRIV (credentials will be requested once)"
    if [ "$PRIV" = "doas" ]; then
        # doas(1) has no sudo-style -v "validate credentials" flag;
        # `doas true` prompts once up front and caches (with `permit persist`).
        doas true
    elif ! sudo -n true 2>/dev/null; then
        if [ -n "${SUDO_ASKPASS:-}" ]; then
            sudo -A -v
        else
            sudo -v
        fi
    fi
fi

# --------------------------------------------------------------- packages ---
if [ "$DO_PACKAGES" -eq 1 ]; then
    if [ ! -f "$PACKAGES_FILE" ]; then
        echo "Package list missing: $PACKAGES_FILE" >&2
        exit 1
    fi
    # Bootstrap pkg(8) non-interactively, then install best-effort:
    # try one bulk install first (fast path); any package that does not
    # exist on this branch (e.g. swayosd, tuigreet on quarterly) is retried
    # individually so one bad name can never fail the whole desktop.
    log "Bootstrapping pkg and installing packages (this takes a while)"
    "$PRIV" pkg update -f || warn "pkg update reported an error; continuing anyway"
    _pkgs="$(grep -v '^[[:space:]]*#' "$PACKAGES_FILE" | grep -v '^[[:space:]]*$' | awk '{print $1}')"
    # shellcheck disable=SC2086
    if ! "$PRIV" pkg install -y $_pkgs; then
        warn "bulk install failed; retrying per-package (missing optionals will be skipped)"
        for _p in $_pkgs; do
            if ! "$PRIV" pkg install -y "$_p"; then
                warn "skipping unavailable package: $_p"
            fi
        done
    fi
    unset _pkgs _p

    # Cargo fallbacks: matugen (theming engine) and awww (wallpaper daemon)
    # have no FreeBSD ports. swaybg (pkg above) is the built-in fallback, so
    # these are best-effort only.
    if ! command -v matugen >/dev/null 2>&1; then
        if command -v cargo >/dev/null 2>&1; then
            log "Installing matugen via cargo (no FreeBSD port)"
            cargo install matugen 2>/dev/null || warn "cargo install matugen failed; theming will be limited"
        else
            warn "matugen not found and cargo missing (install lang/rust); run sway-wall.sh after installing matugen"
        fi
    fi
    if ! command -v awww >/dev/null 2>&1; then
        if command -v cargo >/dev/null 2>&1; then
            log "Installing awww via cargo (no FreeBSD port; swaybg stays as fallback)"
            cargo install awww 2>/dev/null || warn "cargo install awww failed; swaybg fallback will be used"
        else
            warn "awww not found; swaybg fallback will be used"
        fi
    fi
    # Python helpers with no (stable) port names.
    if ! command -v autotiling >/dev/null 2>&1; then
        if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
            log "Installing autotiling via pip (best effort)"
            (pip install --user autotiling 2>/dev/null || pip3 install --user autotiling 2>/dev/null) \
                || warn "autotiling install failed; tiling stays manual (Super+J toggles split)"
        fi
    fi
    if ! command -v rofimoji >/dev/null 2>&1; then
        if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then
            (pip install --user rofimoji 2>/dev/null || pip3 install --user rofimoji 2>/dev/null) \
                || warn "rofimoji install failed; emoji picker will be unavailable"
        fi
    fi

    log "Enabling services (sysrc + service)"
    # NOTE: no elogind/runit here. seatd provides seat management on
    # FreeBSD; dbus is the session/system bus; powerd handles CPU/power;
    # ntpd keeps time; cron runs user jobs; pf is the firewall.
    for _svc in dbus seatd powerd ntpd cron pf; do
        case "$_svc" in
            dbus)    _var="dbus_enable" ;;
            seatd)   _var="seatd_enable" ;;
            powerd)  _var="powerd_enable" ;;
            ntpd)    _var="ntpd_enable" ;;
            cron)    _var="cron_enable" ;;
            pf)      _var="pf_enable" ;;
        esac
        if "$PRIV" sysrc -n "$_var" >/dev/null 2>&1; then
            "$PRIV" sysrc "$_var=YES" >/dev/null || warn "sysrc $_var failed"
            log "  enabled $_svc ($_var=YES)"
        else
            warn "sysrc unavailable for $_var; skipping"
        fi
    done
    unset _svc _var
    # Sensible powerd tunables for a laptop/desktop (AC hiadaptive,
    # battery adaptive). Overwritten only when powerd_flags is unset.
    if "$PRIV" sysrc -n powerd_flags >/dev/null 2>&1; then
        if [ -z "$("$PRIV" sysrc -n powerd_flags 2>/dev/null)" ]; then
            "$PRIV" sysrc 'powerd_flags=-a hiadaptive -b adaptive' >/dev/null || true
        fi
    fi
    # ntpd: sync clock at boot before starting the daemon.
    "$PRIV" sysrc ntpd_sync_on_start=YES >/dev/null 2>&1 || true
    # Bluetooth: base stack, started on demand by the menu scripts.
    # (BlueZ bluetoothctl/blueman do not exist on FreeBSD; the waybar
    # bluetooth module degrades gracefully when the stack is down.)
    "$PRIV" sysrc bluetooth_enable=YES >/dev/null 2>&1 || true
    # greetd login manager (only when the port is installed).
    if [ -x /usr/local/bin/greetd ] || command -v greetd >/dev/null 2>&1; then
        "$PRIV" sysrc greetd_enable=YES >/dev/null 2>&1 || true
        log "  enabled greetd"
    else
        warn "greetd not installed; skipping greetd_enable (TTY login + start-sway still works)"
    fi
    # Start what we can now (idempotent; already-running services are OK).
    for _svc in dbus seatd powerd ntpd cron; do
        "$PRIV" service "$_svc" status >/dev/null 2>&1 || "$PRIV" service "$_svc" start >/dev/null 2>&1 \
            || warn "could not start $_svc now; it will start at boot"
    done
    unset _svc

    log "Configuring firewall (pf)"
    if [ -f "$REPO_DIR/system/pf.conf" ]; then
        if [ ! -f /etc/pf.conf ] || ! grep -q "freebsd-config" /etc/pf.conf 2>/dev/null; then
            if [ -f /etc/pf.conf ]; then
                "$PRIV" cp /etc/pf.conf "/etc/pf.conf.freebsd-config-backup-$(date +%Y%m%d-%H%M%S)" || true
                log "  backed up existing /etc/pf.conf"
            fi
            "$PRIV" cp "$REPO_DIR/system/pf.conf" /etc/pf.conf
            log "  installed desktop pf.conf (loopback + established + outbound)"
        else
            log "  /etc/pf.conf already managed by freebsd-config"
        fi
        # Validate before (re)loading so a typo can never lock the machine out.
        if "$PRIV" pfctl -n -f /etc/pf.conf 2>/dev/null; then
            "$PRIV" service pf status >/dev/null 2>&1 || "$PRIV" service pf start >/dev/null 2>&1 || true
            "$PRIV" pfctl -f /etc/pf.conf 2>/dev/null || warn "pfctl reload failed; rules apply at next boot"
        else
            warn "/etc/pf.conf failed validation; leaving pf untouched"
        fi
    fi

    log "Configuring devfs (video/input/audio device access)"
    # sway needs rw access to drm (/dev/dri), evdev (/dev/input) and sound
    # (/dev/dsp, /dev/mixer). FreeBSD has no input/_seatd groups; access is
    # granted to the video group via a dedicated devfs ruleset.
    if [ -f "$REPO_DIR/system/devfs.rules" ]; then
        if ! grep -q "freebsd_config" /etc/devfs.rules 2>/dev/null; then
            "$PRIV" sh -c 'cat "$1" >> /etc/devfs.rules' sh "$REPO_DIR/system/devfs.rules" \
                || warn "could not append devfs rules"
            log "  appended freebsd-config ruleset to /etc/devfs.rules"
        else
            log "  /etc/devfs.rules already contains freebsd-config ruleset"
        fi
        "$PRIV" sysrc devfs_system_ruleset=freebsd_config >/dev/null 2>&1 || true
        "$PRIV" service devfs restart >/dev/null 2>&1 || warn "devfs restart failed; rules apply at next boot"
    fi

    log "Configuring greetd + wheel sudo/doas"
    if command -v tuigreet >/dev/null 2>&1 || [ -x /usr/local/bin/tuigreet ]; then
        "$PRIV" mkdir -p /etc/greetd /usr/local/etc/greetd
        # Ports install sessions under /usr/local/share/wayland-sessions;
        # greetd itself reads /etc/greetd/config.toml upstream.
        "$PRIV" tee /etc/greetd/config.toml >/dev/null <<'EOF'
[terminal]
vt = 8
[default_session]
command = "tuigreet --time --asterisks --remember --remember-user-session --sessions /usr/local/share/wayland-sessions:/usr/share/wayland-sessions --theme border=blue;text=white;prompt=green;time=gray;action=cyan;button=yellow;container=black;input=red"
user = "_greeter"
EOF
        if [ -d /usr/local/etc/greetd ]; then
            "$PRIV" cp /etc/greetd/config.toml /usr/local/etc/greetd/config.toml || true
        fi
        log "  wrote greetd config (tuigreet on VT8, FreeBSD  sessions)"
        # greetd runs the session Exec= line verbatim (no shell, no bus):
        # wrap sway so every graphical login gets a session bus from the
        # start (absolute /usr/local paths: greetd's PATH is minimal).
        for _desk in /usr/local/share/wayland-sessions/sway.desktop /usr/share/wayland-sessions/sway.desktop; do
            if [ -f "$_desk" ]; then
                # Portable in-place edit (BSD sed needs the '' backup arg).
                "$PRIV" sed -i '' 's|^Exec=.*|Exec=/usr/local/bin/dbus-run-session -- /usr/local/bin/sway|' "$_desk" \
                    || warn "could not patch $_desk"
                log "  sway.desktop runs under dbus-run-session"
                break
            fi
        done
        unset _desk
    else
        warn "tuigreet not installed; skipping greetd config (install x11/tuigreet or log in on TTY)"
    fi
    # PipeWire on FreeBSD runs as a per-user service launched from sway's
    # autostart (see sway/config) — no system-wide /etc/pipewire drop-ins
    # are used, so nothing is written here by design.
    # sudo (ports path) + doas wheel access.
    if [ ! -f /usr/local/etc/sudoers.d/wheel ]; then
        "$PRIV" mkdir -p /usr/local/etc/sudoers.d
        echo '%wheel ALL=(ALL:ALL) ALL' | "$PRIV" tee /usr/local/etc/sudoers.d/wheel >/dev/null
        "$PRIV" chmod 440 /usr/local/etc/sudoers.d/wheel
    fi
    "$PRIV" visudo -c >/dev/null 2>&1 || warn "visudo check failed; inspect /usr/local/etc/sudoers.d/wheel"
    if [ ! -f /usr/local/etc/doas.conf ]; then
        echo 'permit persist :wheel' | "$PRIV" tee /usr/local/etc/doas.conf >/dev/null
        "$PRIV" chmod 440 /usr/local/etc/doas.conf
        log "  wrote doas.conf (permit persist :wheel)"
    fi
    for grp in wheel video operator; do
        if getent group "$grp" >/dev/null 2>&1; then
            if ! id -nG "$USER" | tr ' ' '\n' | grep -qx "$grp"; then
                "$PRIV" pw groupmod "$grp" -m "$USER" \
                    && log "  added $USER to $grp (takes effect on next login)" \
                    || warn "could not add $USER to $grp"
            fi
        fi
    done
    unset grp

    command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update || true
    cat <<'EOF'
[install] Wireless is hardware-specific on FreeBSD — configure once per machine:
[install]   1. kldload if_iwm (or your driver; add to /boot/loader.conf)
[install]   2. sysrc wlans_iwm0="wlan0" && sysrc ifconfig_wlan0="WPA SYNCDHCP"
[install]   3. edit /etc/wpa_supplicant.conf, then: service netif restart && service routing restart
[install] See README.md ("FreeBSD 15.1 notes") for the full snippet.
EOF
fi

# ------------------------------------------------------------------ links ---
link() { # link <source-in-repo> <destination>
    local src="$1" dest="$2"
    # Already pointing at the right source: nothing to do.
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        return 0
    fi
    # Never write through a parent directory that itself links into the repo
    # (e.g. ~/.config/zsh -> freebsd-config/zsh): the file is already deployed
    # via the directory link, and touching it would mutate the repo.
    # Portable canonicalization: realpath -m is GNU-only, plain realpath
    # needs an existing path — gate on -d and fall back to the raw dirname
    # (a nonexistent parent cannot be a symlink into the repo anyway).
    local parent_dir parent_real
    parent_dir="$(dirname "$dest")"
    if [ -d "$parent_dir" ]; then
        parent_real="$(realpath "$parent_dir" 2>/dev/null || printf '%s' "$parent_dir")"
    else
        parent_real="$parent_dir"
    fi
    case "$parent_real/" in
        "$REPO_DIR/"*)
            log "  already covered by directory link, skipping: $dest"
            return 0
            ;;
    esac
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        mkdir -p "$BACKUP_DIR"
        mv "$dest" "$BACKUP_DIR/$(echo "$dest" | tr '/' '_' | sed 's/^_//')"
        log "  backed up $dest"
    fi
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest"
}

if [ "$DO_LINKS" -eq 1 ]; then
    log "Linking ~/.config directories (backups go to $BACKUP_DIR)"
    for d in btop foot gtk-3.0 gtk-4.0 mako matugen nvim rofi sway \
             waybar xdg-desktop-portal zsh fastfetch; do
        [ -e "$REPO_DIR/$d" ] && link "$REPO_DIR/$d" "$HOME/.config/$d"
    done
    # swayosd has no versioned directory (its style.css is matugen-generated);
    # nothing to link by design.
    [ -f "$REPO_DIR/starship.toml" ] && link "$REPO_DIR/starship.toml" "$HOME/.config/starship.toml"
    [ -f "$REPO_DIR/mimeapps.list" ] && link "$REPO_DIR/mimeapps.list" "$HOME/.config/mimeapps.list"

    log "Linking shell startup files"
    link "$REPO_DIR/shell/bash_profile" "$HOME/.bash_profile"
    link "$REPO_DIR/shell/bashrc"       "$HOME/.bashrc"
    link "$REPO_DIR/shell/zprofile"     "$HOME/.zprofile"
    link "$REPO_DIR/shell/zshrc"        "$HOME/.zshrc"
    # NOTE: no ~/.asoundrc on FreeBSD — audio is OSS (mixer(8)/sysctl
    # hw.snd) with optional PipeWire; ALSA shims do not apply.

    log "Linking helper scripts into ~/.local/bin"
    mkdir -p "$HOME/.local/bin"
    for script in "$REPO_DIR"/bin/*; do
        [ -f "$script" ] || continue
        case "$script" in *.md) continue ;; esac
        chmod +x "$script"
        link "$script" "$HOME/.local/bin/$(basename "$script")"
    done
    # FreeBSD naming: arch-* became freebsd-*; keep tiny compat shims so old
    # keybinds/aliases keep working across the rename.
    for _old in arch-wallpaper-picker arch-menu-images; do
        _new="${_old#arch-}"
        if [ -e "$HOME/.local/bin/freebsd-$_new" ] && [ ! -e "$HOME/.local/bin/$_old" ]; then
            ln -sfn "$HOME/.local/bin/freebsd-$_new" "$HOME/.local/bin/$_old"
            log "  compat shim: $_old -> freebsd-$_new"
        fi
    done
    unset _old _new

    if [ -d "$REPO_DIR/applications" ]; then
        log "Linking desktop overrides into ~/.local/share/applications"
        mkdir -p "$HOME/.local/share/applications"
        for desktop in "$REPO_DIR"/applications/*.desktop; do
            [ -f "$desktop" ] || continue
            link "$desktop" "$HOME/.local/share/applications/$(basename "$desktop")"
        done
    fi

    log "Creating data directories"
    mkdir -p "$HOME/.local/share/wallpapers" "$HOME/.cache"

    if ! command -v zsh >/dev/null 2>&1; then
        warn "zsh not installed; chsh skipped"
    elif [ "$SHELL" != "$(command -v zsh)" ]; then
        log "Setting zsh as login shell (password prompt expected)"
        # FreeBSD chsh takes '-s shell [user]'.
        chsh -s "$(command -v zsh)" "$USER" || warn "chsh failed; run 'chsh -s \$(which zsh)' manually"
    fi
fi

# ------------------------------------------------------------------ fonts ---
if [ "$DO_FONTS" -eq 1 ]; then
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
        log "JetBrainsMono Nerd Font already present"
    else
        log "Downloading JetBrainsMono Nerd Font + Symbols (best effort)"
        mkdir -p "$HOME/.local/share/fonts"
        tmp="$(mktemp -d)"
        if curl -fsSL -o "$tmp/JetBrainsMono.tar.xz" \
                "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
           && curl -fsSL -o "$tmp/Symbols.tar.xz" \
                "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz"; then
            tar -xf "$tmp/JetBrainsMono.tar.xz" -C "$HOME/.local/share/fonts"
            tar -xf "$tmp/Symbols.tar.xz" -C "$HOME/.local/share/fonts"
            fc-cache -f "$HOME/.local/share/fonts" >/dev/null
            log "  fonts installed"
        else
            warn "font download failed; copy .ttf files to ~/.local/share/fonts manually"
        fi
        rm -rf "$tmp"
    fi
fi

# ------------------------------------------------------------- wallpapers ---
if [ "$DO_WALLPAPERS" -eq 1 ]; then
    WALL_DIR="$HOME/.local/share/wallpapers"
    mkdir -p "$WALL_DIR"
    if [ "$(find "$WALL_DIR" -type f | head -1)" ]; then
        log "Wallpapers already present in $WALL_DIR ($(find "$WALL_DIR" -type f | wc -l) files), skipping download"
    else
        log "Fetching wallpaper collection (best effort)"
        tmp="$(mktemp -d)"
        if git clone --depth 1 https://github.com/rajan9884/wallpapers "$tmp/wallpapers" >/dev/null 2>&1; then
            # Flatten: copy every image out of the nested repo layout,
            # -n keeps any user-added file with the same name.
            find "$tmp/wallpapers" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \
                -o -iname "*.png" -o -iname "*.webp" \) \
                -exec cp -n {} "$WALL_DIR/" \;
            log "  $(find "$WALL_DIR" -type f | wc -l) wallpapers in $WALL_DIR"
        else
            warn "wallpaper clone failed; copy images to $WALL_DIR manually"
        fi
        rm -rf "$tmp"
    fi
    # sway/config points at a static fallback background; guarantee it exists
    # so a fresh clone without that exact filename never errors at startup.
    if [ ! -f "$WALL_DIR/fallback-wallpaper.jpg" ]; then
        _fb="$(find "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \
            -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n 1 || true)"
        if [ -n "${_fb:-}" ]; then
            cp -n "$_fb" "$WALL_DIR/fallback-wallpaper.jpg"
            log "  seeded fallback wallpaper from $(basename "$_fb")"
        fi
    fi
fi

# ------------------------------------------------------------------- done ---
log "Done."
if [ ! -s "$HOME/.cache/current-wallpaper" ]; then
    if pgrep -x sway >/dev/null 2>&1 && [ "$(find "$HOME/.local/share/wallpapers" -type f | head -1)" ]; then
        log "Seeding theme from a random wallpaper"
        "$HOME/.config/sway/scripts/random-wall.sh" >/dev/null 2>&1 \
            || warn "theme seeding failed; run ~/.config/sway/scripts/sway-wall.sh <image> manually"
    else
        warn "No wallpaper selected yet: log into Sway, then run"
        warn "  ~/.config/sway/scripts/sway-wall.sh ~/path/to/wallpaper.jpg"
        warn "to generate the matugen theme (waybar/rofi/foot/starship follow it)."
    fi
fi
cat <<'EOF'
[install] Not covered by this script (see README.md):
[install]   - Chromium/Extensions : pkg installs chromium; no Helium port exists
[install]   - Intel/AMD GPU firmware + DRM kernel modules (drm-kmod port, loader.conf)
[install]   - Wi-Fi driver + wpa_supplicant (per-machine; see README FreeBSD notes)
[install]   - gh auth login + per-repo git-work / git-personal identity
EOF
