#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrap Arch Linux installer..."

pacman -Sy --noconfirm --needed git openssh libfido2

mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
chmod 644 ~/.ssh/known_hosts

eval "$(ssh-agent -s)" >/dev/null
ORIG_DIR="$(pwd)"
cd ~/.ssh
ssh-keygen -K
cd "$ORIG_DIR"

find ~/.ssh -name '*_sk*' 2>/dev/null | while read -r key; do
    rm -f "${key}.pub"
    ssh-add "$key" 2>/dev/null || true
done

PRIVATE_REPO="git@github.com:kengzzzz/dotfiles.git"
BRANCH="main"

rm -rf /tmp/dotfiles-temp

git clone --depth 1 --filter=blob:none --no-checkout --branch "$BRANCH" "$PRIVATE_REPO" /tmp/dotfiles-temp

cd /tmp/dotfiles-temp

git sparse-checkout init --no-cone
git sparse-checkout set "utils/scripts/install.sh"
git checkout

mv utils/scripts/install.sh ~/
rm -rf /tmp/dotfiles-temp

cd ~/
chmod +x install.sh
echo "Running install.sh..."
exec ./install.sh