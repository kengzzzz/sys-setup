#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrap Arch Linux installer..."

# The live ISO's default 256M overlay is too small for a full upgrade plus Docker.
mount -o remount,size=20G /run/archiso/cowspace || echo "warning: could not resize archiso cowspace" >&2

# Upgrading the live kernel deletes the running kernel's modules, which Docker needs.
pacman -Syu --noconfirm --needed --ignore linux git

INSTALLER_REPO="https://github.com/kengzzzz/sys-setup.git"
BRANCH="main"
INSTALLER_DIR="/tmp/sys-setup-install"

if [[ -n $(git -C "$INSTALLER_DIR" status --porcelain 2>/dev/null) ]]; then
    patch=/root/sys-setup-local-changes-$(date +%Y%m%d-%H%M%S).patch
    git -C "$INSTALLER_DIR" diff HEAD >"$patch"
    echo "Saved local installer changes to $patch" >&2
fi
rm -rf "$INSTALLER_DIR"

git clone --depth 1 --branch "$BRANCH" "$INSTALLER_REPO" "$INSTALLER_DIR"

echo "Running Arch installer..."
exec "$INSTALLER_DIR/archlinux/install.sh" "$@"
