#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=../provision.sh
source "$ROOT_DIR/provision.sh"

for package in fzf command-not-found; do
    if ! printf '%s\n' "${WSL_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should be installed in WSL\n' "$package" >&2
        exit 1
    fi
done

for package in btop codex fastfetch muse ssh zshrc; do
    if ! printf '%s\n' "${WSL_STOW_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should be in the WSL Stow allowlist\n' "$package" >&2
        exit 1
    fi
done

for package in docs etc usr swayidle xsettingsd hypr quickshell uwsm; do
    if printf '%s\n' "${WSL_STOW_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should not be in the WSL Stow allowlist\n' "$package" >&2
        exit 1
    fi
done

if declare -f install_shell_framework | grep -q 'fast-syntax-highlighting'; then
    printf 'FAIL: WSL still installs the unused fast-syntax-highlighting plugin\n' >&2
    exit 1
fi

printf 'WSL provisioner tests passed\n'
