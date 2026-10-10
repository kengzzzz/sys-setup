#!/usr/bin/env bash

# Plan screen order; also saved for re-runs.
SETTINGS_VARS=(
    TARGET_DISK
    INSTALL_USER
    HOSTNAME
    TIMEZONE
    LOCALE
    EXTRA_LOCALES
    KEYMAP
    ROOT_FS
    EFI_SIZE
    PRIMARY_KERNEL
    FALLBACK_KERNEL
    FALLBACK_NVIDIA_PACKAGE
    BOOT_ENTRY
    NETWORK_INTERFACE
    NETWORK_ADDRESS
    NETWORK_GATEWAY
    NETWORK_DNS
    YUBIKEY_SYSTEM_AUTH
    ENABLE_DOTFILES
    DOTFILES_REPO
    DOTFILES_BRANCH
    RESTORE_LACT_CONFIG
    ENABLE_WORKLOAD_PACKAGES
    TAILSCALE_FIRST_LOGIN
    TAILSCALE_UP_ARGS
    AUTO_REBOOT
)

BOOLEAN_SETTINGS=(
    YUBIKEY_SYSTEM_AUTH ENABLE_DOTFILES RESTORE_LACT_CONFIG ENABLE_WORKLOAD_PACKAGES
    TAILSCALE_FIRST_LOGIN AUTO_REBOOT
)

set_default_config() {
    # No default disk: NVMe numbering can change between boots.
    TARGET_DISK=${TARGET_DISK:-}
    INSTALL_USER=${INSTALL_USER:-keng}
    HOSTNAME=${HOSTNAME:-arch-pc}
    TIMEZONE=${TIMEZONE:-Asia/Bangkok}
    LOCALE=${LOCALE:-en_US.UTF-8}
    EXTRA_LOCALES=${EXTRA_LOCALES-th_TH.UTF-8}
    KEYMAP=${KEYMAP:-us}
    EFI_SIZE=${EFI_SIZE:-5G}
    ROOT_FS=${ROOT_FS:-btrfs}
    PRIMARY_KERNEL=${PRIMARY_KERNEL:-linux-bore-flto-pgo}
    FALLBACK_KERNEL=${FALLBACK_KERNEL:-linux-cachyos-lts}
    FALLBACK_NVIDIA_PACKAGE=${FALLBACK_NVIDIA_PACKAGE:-linux-cachyos-lts-nvidia-open}
    CUSTOM_KERNEL_BUILD=${CUSTOM_KERNEL_BUILD:-1}
    CUSTOM_KERNEL_DIR=${CUSTOM_KERNEL_DIR:-kernel/desktop}
    CUSTOM_KERNEL_PACKAGES_DIR=${CUSTOM_KERNEL_PACKAGES_DIR:-}
    NETWORK_INTERFACE=${NETWORK_INTERFACE:-enp14s0}
    NETWORK_ADDRESS=${NETWORK_ADDRESS:-192.168.0.10/24}
    NETWORK_GATEWAY=${NETWORK_GATEWAY:-192.168.0.1}
    NETWORK_DNS=${NETWORK_DNS:-192.168.0.3}
    YUBIKEY_SYSTEM_AUTH=${YUBIKEY_SYSTEM_AUTH:-1}
    DOTFILES_REPO=${DOTFILES_REPO:-git@github.com:kengzzzz/dotfiles.git}
    DOTFILES_BRANCH=${DOTFILES_BRANCH:-main}
    BOOT_ENTRY=${BOOT_ENTRY:-default.conf}
    ENABLE_DOTFILES=${ENABLE_DOTFILES:-1}
    ENABLE_WORKLOAD_PACKAGES=${ENABLE_WORKLOAD_PACKAGES:-1}
    RESTORE_LACT_CONFIG=${RESTORE_LACT_CONFIG:-0}
    TAILSCALE_FIRST_LOGIN=${TAILSCALE_FIRST_LOGIN:-1}
    TAILSCALE_UP_ARGS=${TAILSCALE_UP_ARGS-"--accept-dns=false --accept-routes"}
    AUTO_REBOOT=${AUTO_REBOOT:-1}
    RETRY_ATTEMPTS=${RETRY_ATTEMPTS:-3}
    RETRY_DELAY=${RETRY_DELAY:-5}
    derive_config
}

derive_config() {
    DOTFILES_DIR="/home/${INSTALL_USER}/dotfiles"
}

load_config_file() {
    local config_file=$1
    [[ -f $config_file ]] || die "config file not found: $config_file"
    # shellcheck disable=SC1090
    source "$config_file"
}

is_boolean_setting() {
    local name=$1 flag
    for flag in "${BOOLEAN_SETTINGS[@]}"; do
        [[ $flag != "$name" ]] || return 0
    done
    return 1
}

valid_ipv4() {
    local octet
    local -a octets
    [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -ra octets <<<"$1"
    for octet in "${octets[@]}"; do
        ((10#$octet <= 255)) || return 1
    done
}

valid_ipv4_cidr() {
    local address=${1%/*} prefix=${1##*/}
    [[ $1 == */* && $prefix =~ ^[0-9]{1,2}$ ]] && ((10#$prefix <= 32)) && valid_ipv4 "$address"
}

valid_dns_list() {
    local server
    local -a servers
    [[ -n $1 ]] || return 1
    IFS=';' read -ra servers <<<"$1"
    for server in "${servers[@]}"; do
        valid_ipv4 "$server" || return 1
    done
}

locale_supported() {
    local supported=/usr/share/i18n/SUPPORTED
    [[ -f $supported ]] || return 0
    grep -qxF "$1 UTF-8" "$supported"
}

keymap_exists() {
    [[ -d /usr/share/kbd/keymaps ]] || return 0
    [[ -n $(find /usr/share/kbd/keymaps -name "$1.map*" -print -quit) ]]
}

setting_error() {
    local name=$1 value=${!1-} locale
    case $name in
        TARGET_DISK) target_disk_error ;;
        INSTALL_USER)
            [[ $value =~ ^[a-z_][a-z0-9_-]{0,31}$ && $value != root ]] \
                || echo "use lowercase letters, digits, - or _; not root"
            ;;
        HOSTNAME)
            [[ $value =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]] || echo "use letters, digits, . and -, up to 63 characters"
            ;;
        TIMEZONE)
            [[ -n $value && $value != /* && $value != *..* && -f /usr/share/zoneinfo/$value ]] \
                || echo "unknown timezone; for example Asia/Bangkok"
            ;;
        LOCALE)
            locale_supported "$value" || echo "unknown locale; for example en_US.UTF-8"
            ;;
        EXTRA_LOCALES)
            for locale in $value; do
                locale_supported "$locale" || echo "unknown locale: $locale"
            done
            ;;
        KEYMAP)
            [[ $value =~ ^[A-Za-z0-9_.-]+$ ]] && keymap_exists "$value" || echo "unknown console keymap"
            ;;
        ROOT_FS)
            [[ $value == btrfs || $value == xfs ]] || echo "must be btrfs or xfs"
            ;;
        EFI_SIZE)
            [[ $value =~ ^[1-9][0-9]*[KkMmGgTt]$ ]] || echo "include a unit, for example 5G"
            ;;
        PRIMARY_KERNEL | FALLBACK_KERNEL | FALLBACK_NVIDIA_PACKAGE)
            [[ $value =~ ^[a-z0-9][a-z0-9._+-]*$ ]] || echo "invalid package name"
            [[ $name != FALLBACK_KERNEL || $value != "$PRIMARY_KERNEL" ]] || echo "must differ from the primary kernel"
            ;;
        BOOT_ENTRY)
            [[ $value =~ ^[A-Za-z0-9._+-]+\.conf$ ]] || echo "must be a simple .conf filename"
            [[ $value != "${FALLBACK_KERNEL}.conf" ]] || echo "the fallback kernel already uses this filename"
            ;;
        NETWORK_INTERFACE)
            [[ $value =~ ^[A-Za-z0-9_.-]+$ ]] || echo "invalid interface name"
            ;;
        NETWORK_ADDRESS)
            valid_ipv4_cidr "$value" || echo "use address/prefix, for example 192.168.0.10/24"
            ;;
        NETWORK_GATEWAY)
            valid_ipv4 "$value" || echo "use an IPv4 address"
            ;;
        NETWORK_DNS)
            valid_dns_list "$value" || echo "use IPv4 addresses separated by ;"
            ;;
        DOTFILES_REPO)
            [[ $ENABLE_DOTFILES != 1 || -n $value ]] || echo "required while dotfiles are enabled"
            ;;
        DOTFILES_BRANCH)
            [[ $ENABLE_DOTFILES != 1 || $value =~ ^[A-Za-z0-9._/-]+$ ]] || echo "invalid branch name"
            ;;
        RESTORE_LACT_CONFIG)
            [[ $value != 1 || $ENABLE_DOTFILES == 1 ]] || echo "needs dotfiles"
            ;;
        TAILSCALE_UP_ARGS)
            [[ $value != *[\'\"\\\`\$]* ]] || echo "quotes, backslashes and \$ are not supported"
            ;;
    esac
    if is_boolean_setting "$name"; then
        [[ $value == 0 || $value == 1 ]] || echo "must be 0 or 1"
    fi
}

setting_warning() {
    local interface
    local -a interfaces=()
    case $1 in
        NETWORK_INTERFACE)
            [[ ! -e /sys/class/net/$NETWORK_INTERFACE ]] || return 0
            for interface in /sys/class/net/*; do
                [[ ${interface##*/} == lo ]] || interfaces+=("${interface##*/}")
            done
            echo "not present on this machine (found: ${interfaces[*]:-none})"
            ;;
    esac
}

system_errors() {
    [[ -d /sys/firmware/efi ]] || echo "UEFI firmware is required for systemd-boot; boot the ISO in UEFI mode"
    if secure_boot_enabled; then
        echo "Secure Boot must be disabled; this installer does not enroll or sign Secure Boot keys"
    fi
}

config_errors() {
    local name message
    system_errors
    for name in "${SETTINGS_VARS[@]}"; do
        while IFS= read -r message; do
            [[ -z $message ]] || printf '%s: %s\n' "$name" "$message"
        done < <(setting_error "$name")
    done
}

validate_config() {
    local errors
    errors=$(config_errors)
    [[ -z $errors ]] || die "invalid configuration:"$'\n'"$errors"
}

show_install_plan() {
    section "Plan"
    printf 'Disk:              %s (%s)\n' "$TARGET_DISK" "$(readlink -f -- "$TARGET_DISK")"
    printf 'EFI size:          %s\n' "$EFI_SIZE"
    printf 'Root filesystem:   %s\n' "$ROOT_FS"
    printf 'User:              %s\n' "$INSTALL_USER"
    printf 'Hostname:          %s\n' "$HOSTNAME"
    printf 'Timezone:          %s\n' "$TIMEZONE"
    printf 'Locale:            %s %s\n' "$LOCALE" "$EXTRA_LOCALES"
    printf 'Kernels:           %s, fallback %s\n' "$PRIMARY_KERNEL" "$FALLBACK_KERNEL"
    printf 'Network:           %s %s gw %s dns %s\n' "$NETWORK_INTERFACE" "$NETWORK_ADDRESS" "$NETWORK_GATEWAY" "$NETWORK_DNS"
    printf 'YubiKey auth:      %s\n' "$(on_off "$YUBIKEY_SYSTEM_AUTH")"
    printf 'Dotfiles:          %s\n' "$([[ $ENABLE_DOTFILES == 1 ]] && printf '%s (%s)' "$DOTFILES_REPO" "$DOTFILES_BRANCH" || printf 'off')"
    printf 'Repo workloads:    %s\n' "$(on_off "$ENABLE_WORKLOAD_PACKAGES")"
    printf 'Restore LACT:      %s\n' "$(on_off "$RESTORE_LACT_CONFIG")"
    printf 'Tailscale login:   %s\n' "$([[ $TAILSCALE_FIRST_LOGIN == 1 ]] && printf 'tailscale up %s' "$TAILSCALE_UP_ARGS" || printf 'off')"
}

on_off() {
    [[ $1 == 1 ]] && printf 'on' || printf 'off'
}

write_settings() {
    local file=$1 name
    : >"$file"
    for name in "${SETTINGS_VARS[@]}"; do
        write_kv "$file" "$name" "${!name}"
    done
}

write_chroot_env() {
    local env_file=$1
    write_settings "$env_file"
    write_kv "$env_file" ROOT_PARTUUID "$ROOT_PARTUUID"
    write_kv "$env_file" DOTFILES_DIR "$DOTFILES_DIR"
    write_kv "$env_file" RETRY_ATTEMPTS "$RETRY_ATTEMPTS"
    write_kv "$env_file" RETRY_DELAY "$RETRY_DELAY"
}
