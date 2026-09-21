#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR=${DOTFILES_DIR:-$HOME/dotfiles}
SOURCE_DIR="$DOTFILES_DIR/zed/.config/zed"

if [[ ! -f "$SOURCE_DIR/settings.json" ]]; then
    printf 'Zed dotfiles package not found under %s.\n' "$DOTFILES_DIR" >&2
    exit 1
fi

if ! command -v wslpath >/dev/null 2>&1 || ! command -v powershell.exe >/dev/null 2>&1; then
    printf 'This script must run inside WSL with Windows interop enabled.\n' >&2
    exit 1
fi

POWERSHELL_SCRIPT="$(wslpath -w "$SCRIPT_DIR/install-windows.ps1")"
WINDOWS_SOURCE_DIR="$(wslpath -w "$SOURCE_DIR")"

# Keep the authoritative checkout in WSL, but copy config into Windows so Zed
# does not depend on a \\wsl.localhost path being available at startup.
powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$POWERSHELL_SCRIPT" -SourceDir "$WINDOWS_SOURCE_DIR" -Copy
