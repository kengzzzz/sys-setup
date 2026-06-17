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

prompt_default() {
    local var_name=$1
    local label=$2
    local default_value=$3
    local value

    read -r -p "${label} [${default_value}]: " value
    printf -v "$var_name" '%s' "${value:-$default_value}"
}

confirm_exact() {
    local expected=$1
    local prompt=$2
    local answer

    read -r -p "${prompt} " answer
    [[ $answer == "$expected" ]]
}

confirm_yes_no() {
    local prompt=$1
    local default=${2:-N}
    local suffix='[y/N]'
    local answer

    if [[ $default == Y || $default == y ]]; then
        suffix='[Y/n]'
    fi

    read -r -p "${prompt} ${suffix} " answer
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
    : >"$INSTALL_LOG"
    exec > >(tee -a "$INSTALL_LOG") 2>&1
    log "logging to $INSTALL_LOG"
}

copy_install_log_to_target() {
    [[ -n ${INSTALL_LOG:-} && -f ${INSTALL_LOG:-} && -d /mnt/var/log ]] || return 0
    cp "$INSTALL_LOG" /mnt/var/log/sys-setup-install.log || true
}
