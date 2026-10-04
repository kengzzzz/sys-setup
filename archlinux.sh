#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrap Arch Linux installer..."

# The live ISO's default 256M overlay is too small for a full upgrade plus Docker.
mount -o remount,size=20G /run/archiso/cowspace || echo "warning: could not resize archiso cowspace" >&2

# Upgrading the live kernel deletes the running kernel's modules, which Docker needs.
pacman -Syu --noconfirm --needed --ignore linux git curl arch-install-scripts gptfdisk dosfstools btrfs-progs xfsprogs parted docker docker-compose

INSTALLER_REPO="https://github.com/kengzzzz/sys-setup.git"
BRANCH="main"
INSTALLER_DIR="/tmp/sys-setup-install"

rm -rf "$INSTALLER_DIR"

git clone --depth 1 --branch "$BRANCH" "$INSTALLER_REPO" "$INSTALLER_DIR"

echo "Running Arch installer..."
exec "$INSTALLER_DIR/archlinux/install.sh" "$@"
