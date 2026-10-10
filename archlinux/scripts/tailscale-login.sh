#!/usr/bin/env bash
# Run by a user unit at each login until Tailscale connects. Needs a terminal for the sudo PIN.
set -uo pipefail

marker=${XDG_STATE_HOME:-$HOME/.local/state}/sys-setup/tailscale-login.done
config=${TAILSCALE_LOGIN_CONF:-/etc/sys-setup/tailscale-login.conf}
TAILSCALE_UP_ARGS=()
# shellcheck source=/dev/null
[[ ! -r $config ]] || source "$config"

connected() {
    [[ $(tailscale status --json 2>/dev/null | jq -r .BackendState 2>/dev/null) == Running ]]
}

mark_done() {
    mkdir -p "${marker%/*}" && : >"$marker"
}

open_login_url() {
    local line opened=0
    while IFS= read -r line; do
        printf '%s\n' "$line"
        if ((!opened)) && [[ $line =~ (https://login\.tailscale\.com/[^[:space:]]+) ]]; then
            xdg-open "${BASH_REMATCH[1]}" >/dev/null 2>&1 &
            opened=1
        fi
    done
}

if [[ ${1:-} != --terminal ]]; then
    if connected; then
        mark_done
        exit 0
    fi
    exec kitty --title 'Tailscale login' "$0" --terminal
fi

while true; do
    printf 'Connecting Tailscale: sudo tailscale up %s\n' "${TAILSCALE_UP_ARGS[*]}"
    printf 'Approve sudo with your YubiKey; the login page opens in the browser.\n\n'
    sudo tailscale up "${TAILSCALE_UP_ARGS[@]}" 2>&1 | open_login_url
    if connected; then
        mark_done
        printf '\nTailscale is connected. This window closes in a few seconds.\n'
        sleep "${TAILSCALE_LOGIN_CLOSE_DELAY:-5}"
        exit 0
    fi
    printf '\nTailscale is not connected yet. Press Enter to try again, or close this\n'
    printf 'window to try at the next login.\n'
    read -r _ || exit 1
done
