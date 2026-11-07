#!/usr/bin/env bash
# Installs the KairosOS greeter (login screen) and makes it the one that starts at boot,
# replacing whatever ran before (Noctalia's greeter, SDDM, GDM, ...).
#
#   sudo ~/caelestia_fork/greeter/install.sh          install / update
#   sudo ~/caelestia_fork/greeter/install.sh --revert  go back to the previous login screen
#
# Nothing is deleted: the old greetd config is kept as config.toml.kairos-backup and the old
# display manager is only disabled (the revert turns it back on).
# Changes take effect at the next boot (or: sudo systemctl restart greetd, which logs you out).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
share=/usr/share/kairos-greeter
session=/usr/local/bin/kairos-greeter-session
conf=/etc/kairos/greeter.json
greetd_conf=/etc/greetd/config.toml
state=/etc/kairos/previous-display-manager
others=(sddm gdm lightdm ly plasmalogin lxdm)

say() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo."
user="${SUDO_USER:-}"
[ -n "$user" ] && [ "$user" != root ] || die "Run with sudo from your own account (not as root directly)."

if [ "${1:-}" = "--revert" ]; then
    prev="$(cat "$state" 2>/dev/null || true)"
    if [ -f "$greetd_conf.kairos-backup" ]; then
        cp "$greetd_conf.kairos-backup" "$greetd_conf"
        say "Restored the previous greetd config."
    fi
    if [ -n "$prev" ] && [ "$prev" != greetd ]; then
        systemctl disable greetd.service
        systemctl enable -f "$prev.service"
        say "Login screen set back to $prev."
    else
        say "greetd stays the login screen, with its previous config."
    fi
    say "Takes effect at the next boot."
    exit 0
fi

# 1. Packages: greetd (the login daemon) and cage (shows one app full-screen).
need=()
command -v greetd >/dev/null || need+=(greetd)
command -v cage >/dev/null || need+=(cage)
if [ ${#need[@]} -gt 0 ]; then
    say "Installing ${need[*]}"
    pacman -S --needed --noconfirm "${need[@]}"
fi
command -v qs >/dev/null || die "Quickshell (qs) is not installed."
id greeter >/dev/null 2>&1 || die "The 'greeter' user is missing (it comes with the greetd package)."

# 2. The greeter itself, where the greeter user can read it.
say "Copying the greeter to $share"
rm -rf "$share"
mkdir -p "$share"
cp "$here"/*.qml "$share"/
chmod -R a+rX "$share"
install -Dm755 "$here/kairos-greeter-session" "$session"

# 3. Settings (only made once; Settings → Lock screen → "Use on the login screen" updates it).
mkdir -p /etc/kairos
if [ ! -f "$conf" ]; then
    launch='["/usr/bin/start-hyprland"]'
    [ -x /usr/bin/start-hyprland ] || launch='["Hyprland"]'
    sed -e "s/\"user\": *\"[^\"]*\"/\"user\": \"$user\"/" \
        -e "s#\"command\": *\[[^]]*\]#\"command\": $launch#" \
        "$here/greeter.example.json" > "$conf"
    say "Wrote $conf (user: $user)"
fi
chmod 644 "$conf"

# 4. greetd runs the Kairos greeter (the old config is kept once, never overwritten).
mkdir -p /etc/greetd
if [ -f "$greetd_conf" ] && [ ! -f "$greetd_conf.kairos-backup" ]; then
    cp "$greetd_conf" "$greetd_conf.kairos-backup"
fi
cat > "$greetd_conf" <<EOF
[terminal]
vt = 1

[default_session]
command = "$session"
user = "greeter"
EOF
say "greetd now starts the Kairos greeter."

# 5. Only greetd starts at boot.
if [ ! -f "$state" ]; then
    prev="$(systemctl show -p Id --value display-manager.service 2>/dev/null | sed 's/\.service$//')"
    echo "${prev:-greetd}" > "$state"
fi
for dm in "${others[@]}"; do
    if systemctl is-enabled "$dm.service" >/dev/null 2>&1; then
        systemctl disable "$dm.service"
        say "Disabled $dm"
    fi
done
systemctl enable -f greetd.service

say "Done. Reboot to see it."
say "If the login screen ever stays black: Ctrl+Alt+F3, log in, then: sudo $here/install.sh --revert"
