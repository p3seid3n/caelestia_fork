#!/usr/bin/env bash
# One-time setup for the power menu's "restart into Windows" button:
#   sudo ~/caelestia_fork/scripts/install-reboot-windows.sh
# Installs the script and lets your user run exactly that one script as root without a password
# (only it: it can do nothing but pick Windows for the next boot and restart).
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
user="${SUDO_USER:-}"
[ -n "$user" ] && [ "$user" != root ] || { echo "Run with sudo from your own account." >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
command -v efibootmgr >/dev/null || pacman -S --needed --noconfirm efibootmgr

install -Dm755 "$here/kairos-reboot-windows" /usr/local/bin/kairos-reboot-windows

rule=/etc/sudoers.d/kairos-reboot-windows
tmp=$(mktemp)
echo "$user ALL=(root) NOPASSWD: /usr/local/bin/kairos-reboot-windows" > "$tmp"
visudo -cf "$tmp" >/dev/null
install -m440 "$tmp" "$rule"
rm -f "$tmp"

if efibootmgr | grep -qi "Windows Boot Manager"; then
    echo ":: Ready. The power menu's Windows button now restarts straight into Windows."
else
    echo ":: Installed, but no 'Windows Boot Manager' entry was found in the firmware:"
    efibootmgr
fi
