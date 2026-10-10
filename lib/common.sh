#!/usr/bin/env bash

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

section() {
    printf '\n==> %s\n' "$*"
}

require_root() {
    [[ ${EUID} -eq 0 ]] || die "run this installer as root"
}

run() {
    if [[ ${DRY_RUN:-0} == 1 ]]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

retry() {
    local attempts=${RETRY_ATTEMPTS:-3}
    local delay=${RETRY_DELAY:-5}
    local n=1

    while true; do
        if run "$@"; then
            return 0
        fi

        if ((n >= attempts)); then
            printf 'command failed after %d attempts:' "$attempts" >&2
            printf ' %q' "$@" >&2
            printf '\n' >&2
            return 1
        fi

        warn "command failed, retrying in ${delay}s (${n}/${attempts})"
        sleep "$delay"
        n=$((n + 1))
    done
}

# Drop typed-ahead keys, e.g. an extra Enter.
drain_input() {
    [[ -t 0 ]] || return 0
    while read -r -t 0.05 -n 4096 _; do :; done
    return 0
}

# No locals: they would shadow the caller's variable.
ask() {
    drain_input
    read -r -p "$2 " "$1" || die "input closed while waiting for an answer"
}

confirm_yes_no() {
    local prompt=$1
    local default=${2:-N}
    local suffix='[y/N]'
    local answer

    if [[ $default == Y || $default == y ]]; then
        suffix='[Y/n]'
    fi

    ask answer "${prompt} ${suffix}"
    answer=${answer:-$default}
    [[ $answer == Y || $answer == y || $answer == yes || $answer == YES ]]
}

write_kv() {
    local file=$1
    local key=$2
    local value=$3

    printf '%s=%q\n' "$key" "$value" >>"$file"
}

init_logging() {
    INSTALL_LOG=${INSTALL_LOG:-/tmp/sys-setup-arch-install.log}
    [[ ! -s $INSTALL_LOG ]] || mv -f "$INSTALL_LOG" "$INSTALL_LOG.previous"
    : >"$INSTALL_LOG"
    exec > >(tee -a "$INSTALL_LOG") 2>&1
    log "logging to $INSTALL_LOG"
}

copy_install_log_to_target() {
    [[ -n ${INSTALL_LOG:-} && -f ${INSTALL_LOG:-} && -d /mnt/var/log ]] || return 0
    cp "$INSTALL_LOG" /mnt/var/log/sys-setup-install.log || true
}
