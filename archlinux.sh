#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrap Arch Linux installer..."

pacman -Sy --noconfirm --needed git curl arch-install-scripts gptfdisk dosfstools xfsprogs parted docker docker-compose

INSTALLER_REPO="https://github.com/kengzzzz/sys-setup.git"
BRANCH="main"
INSTALLER_DIR="/tmp/sys-setup-install"

rm -rf "$INSTALLER_DIR"

git clone --depth 1 --branch "$BRANCH" "$INSTALLER_REPO" "$INSTALLER_DIR"

echo "Running Arch installer..."
exec "$INSTALLER_DIR/archlinux/install.sh" "$@"
