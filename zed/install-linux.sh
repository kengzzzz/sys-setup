#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR=${DOTFILES_DIR:-$HOME/dotfiles}
EXPECTED_CONFIG_HOME="$HOME/.config"

if [[ "${XDG_CONFIG_HOME:-$EXPECTED_CONFIG_HOME}" != "$EXPECTED_CONFIG_HOME" ]]; then
    printf 'This package targets %s, but XDG_CONFIG_HOME is %s.\n' \
        "$EXPECTED_CONFIG_HOME" "$XDG_CONFIG_HOME" >&2
    exit 1
fi

if [[ ! -f "$DOTFILES_DIR/zed/.config/zed/settings.json" ]]; then
    printf 'Zed dotfiles package not found under %s.\n' "$DOTFILES_DIR" >&2
    exit 1
fi

if ! command -v stow >/dev/null 2>&1; then
    printf 'GNU Stow is required.\n' >&2
    exit 1
fi

mkdir -p "$EXPECTED_CONFIG_HOME/zed"

case "${1:-}" in
    "")
        stow --dir "$DOTFILES_DIR" --target "$HOME" --no-folding zed
        ;;
    --adopt)
        stow --dir "$DOTFILES_DIR" --target "$HOME" --no-folding --adopt zed
        printf 'Adopted the live Zed config. Review any changes with:\n  git -C %q diff -- zed\n' \
            "$DOTFILES_DIR"
        ;;
    *)
        printf 'Usage: %s [--adopt]\n' "$0" >&2
        exit 2
        ;;
esac
