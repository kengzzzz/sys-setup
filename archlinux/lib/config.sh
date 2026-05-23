#!/usr/bin/env bash

set_default_config() {
    TARGET_DISK=${TARGET_DISK:-}
    INSTALL_USER=${INSTALL_USER:-keng}
    HOSTNAME=${HOSTNAME:-arch-pc}
    TIMEZONE=${TIMEZONE:-Asia/Bangkok}
    LOCALE=${LOCALE:-en_US.UTF-8}
    EXTRA_LOCALES=${EXTRA_LOCALES:-th_TH.UTF-8}
    KEYMAP=${KEYMAP:-us}
    EFI_SIZE=${EFI_SIZE:-5G}
    ROOT_FS=${ROOT_FS:-xfs}
    PRIMARY_KERNEL=${PRIMARY_KERNEL:-linux-eevdf-flto-pgo}
    FALLBACK_KERNEL=${FALLBACK_KERNEL:-linux-cachyos-lts}
    FALLBACK_KERNEL_HEADERS=${FALLBACK_KERNEL_HEADERS:-linux-cachyos-lts-headers}
    FALLBACK_NVIDIA_PACKAGE=${FALLBACK_NVIDIA_PACKAGE:-linux-cachyos-lts-nvidia-open}
    CUSTOM_KERNEL_BUILD=${CUSTOM_KERNEL_BUILD:-1}
    CUSTOM_KERNEL_DIR=${CUSTOM_KERNEL_DIR:-kernel/eevdf-flto-pgo}
    CUSTOM_KERNEL_PACKAGES_DIR=${CUSTOM_KERNEL_PACKAGES_DIR:-}
    NETWORK_INTERFACE=${NETWORK_INTERFACE:-enp14s0}
    NETWORK_ADDRESS=${NETWORK_ADDRESS:-192.168.0.10/24}
    NETWORK_GATEWAY=${NETWORK_GATEWAY:-192.168.0.1}
    NETWORK_DNS=${NETWORK_DNS:-192.168.0.3}
    YUBIKEY_SYSTEM_AUTH=${YUBIKEY_SYSTEM_AUTH:-1}
    DOTFILES_REPO=${DOTFILES_REPO:-git@github.com:kengzzzz/dotfiles.git}
    DOTFILES_BRANCH=${DOTFILES_BRANCH:-main}
    DOTFILES_DIR=${DOTFILES_DIR:-/home/${INSTALL_USER}/dotfiles}
    BOOT_ENTRY=${BOOT_ENTRY:-arch.conf}
    ENABLE_DOTFILES=${ENABLE_DOTFILES:-1}
    RETRY_ATTEMPTS=${RETRY_ATTEMPTS:-3}
    RETRY_DELAY=${RETRY_DELAY:-5}
}

load_config_file() {
    local config_file=$1
    [[ -f $config_file ]] || die "config file not found: $config_file"
    # shellcheck disable=SC1090
    source "$config_file"
}

prompt_install_config() {
    section "Install configuration"
    lsblk -d -p -n -l -o NAME,SIZE,MODEL
    prompt_default TARGET_DISK "Target disk" "${TARGET_DISK:-/dev/nvme0n1}"
    prompt_default INSTALL_USER "User" "$INSTALL_USER"
    prompt_default HOSTNAME "Hostname" "$HOSTNAME"
    prompt_default TIMEZONE "Timezone" "$TIMEZONE"
    prompt_default LOCALE "Primary locale" "$LOCALE"
    prompt_default EXTRA_LOCALES "Extra locales, space separated" "$EXTRA_LOCALES"
    prompt_default KEYMAP "Console keymap" "$KEYMAP"
    prompt_default EFI_SIZE "EFI partition size" "$EFI_SIZE"
    prompt_default ROOT_FS "Root filesystem" "$ROOT_FS"
    prompt_default PRIMARY_KERNEL "Primary kernel" "$PRIMARY_KERNEL"
    prompt_default FALLBACK_KERNEL "Fallback kernel" "$FALLBACK_KERNEL"
    prompt_default FALLBACK_KERNEL_HEADERS "Fallback kernel headers" "$FALLBACK_KERNEL_HEADERS"
    prompt_default FALLBACK_NVIDIA_PACKAGE "Fallback Nvidia package" "$FALLBACK_NVIDIA_PACKAGE"
    prompt_default NETWORK_INTERFACE "Network interface" "$NETWORK_INTERFACE"
    prompt_default NETWORK_ADDRESS "Static address" "$NETWORK_ADDRESS"
    prompt_default NETWORK_GATEWAY "Gateway" "$NETWORK_GATEWAY"
    prompt_default NETWORK_DNS "DNS" "$NETWORK_DNS"

    if [[ ${ENABLE_DOTFILES:-1} == 1 ]]; then
        prompt_default DOTFILES_REPO "Dotfiles repo" "$DOTFILES_REPO"
        prompt_default DOTFILES_BRANCH "Dotfiles branch" "$DOTFILES_BRANCH"
    fi

    DOTFILES_DIR="/home/${INSTALL_USER}/dotfiles"
}

validate_config() {
    [[ -n ${TARGET_DISK:-} ]] || die "target disk is required"
    [[ -b $TARGET_DISK ]] || die "target disk is not a block device: $TARGET_DISK"
    [[ $ROOT_FS == xfs ]] || die "only xfs root filesystem is currently implemented"
    [[ -d /sys/firmware/efi ]] || die "UEFI firmware is required for systemd-boot"
    [[ -n $PRIMARY_KERNEL && -n $FALLBACK_KERNEL ]] || die "primary and fallback kernels are required"
    [[ -n $NETWORK_INTERFACE && -n $NETWORK_ADDRESS && -n $NETWORK_GATEWAY && -n $NETWORK_DNS ]] || die "static network values are required"
}

show_install_plan() {
    section "Plan"
    printf 'Disk:              %s\n' "$TARGET_DISK"
    printf 'EFI size:          %s\n' "$EFI_SIZE"
    printf 'Root filesystem:   %s\n' "$ROOT_FS"
    printf 'User:              %s\n' "$INSTALL_USER"
    printf 'Hostname:          %s\n' "$HOSTNAME"
    printf 'Timezone:          %s\n' "$TIMEZONE"
    printf 'Locale:            %s\n' "$LOCALE"
    printf 'Extra locales:     %s\n' "$EXTRA_LOCALES"
    printf 'Primary kernel:    %s\n' "$PRIMARY_KERNEL"
    printf 'Fallback kernel:   %s\n' "$FALLBACK_KERNEL"
    printf 'Network:           %s %s gw %s dns %s\n' "$NETWORK_INTERFACE" "$NETWORK_ADDRESS" "$NETWORK_GATEWAY" "$NETWORK_DNS"
    printf 'YubiKey auth:      %s\n' "$([[ ${YUBIKEY_SYSTEM_AUTH:-1} == 1 ]] && printf 'system-auth' || printf 'disabled')"
    printf 'Dotfiles:          %s\n' "$([[ ${ENABLE_DOTFILES:-1} == 1 ]] && printf '%s (%s)' "$DOTFILES_REPO" "$DOTFILES_BRANCH" || printf 'disabled')"
}

write_chroot_env() {
    local env_file=$1

    : >"$env_file"
    write_kv "$env_file" INSTALL_USER "$INSTALL_USER"
    write_kv "$env_file" HOSTNAME "$HOSTNAME"
    write_kv "$env_file" TIMEZONE "$TIMEZONE"
    write_kv "$env_file" LOCALE "$LOCALE"
    write_kv "$env_file" EXTRA_LOCALES "$EXTRA_LOCALES"
    write_kv "$env_file" KEYMAP "$KEYMAP"
    write_kv "$env_file" PRIMARY_KERNEL "$PRIMARY_KERNEL"
    write_kv "$env_file" FALLBACK_KERNEL "$FALLBACK_KERNEL"
    write_kv "$env_file" FALLBACK_KERNEL_HEADERS "$FALLBACK_KERNEL_HEADERS"
    write_kv "$env_file" FALLBACK_NVIDIA_PACKAGE "$FALLBACK_NVIDIA_PACKAGE"
    write_kv "$env_file" NETWORK_INTERFACE "$NETWORK_INTERFACE"
    write_kv "$env_file" NETWORK_ADDRESS "$NETWORK_ADDRESS"
    write_kv "$env_file" NETWORK_GATEWAY "$NETWORK_GATEWAY"
    write_kv "$env_file" NETWORK_DNS "$NETWORK_DNS"
    write_kv "$env_file" YUBIKEY_SYSTEM_AUTH "$YUBIKEY_SYSTEM_AUTH"
    write_kv "$env_file" ROOT_PARTUUID "$ROOT_PARTUUID"
    write_kv "$env_file" DOTFILES_REPO "$DOTFILES_REPO"
    write_kv "$env_file" DOTFILES_BRANCH "$DOTFILES_BRANCH"
    write_kv "$env_file" DOTFILES_DIR "$DOTFILES_DIR"
    write_kv "$env_file" ENABLE_DOTFILES "$ENABLE_DOTFILES"
    write_kv "$env_file" BOOT_ENTRY "$BOOT_ENTRY"
    write_kv "$env_file" RETRY_ATTEMPTS "$RETRY_ATTEMPTS"
    write_kv "$env_file" RETRY_DELAY "$RETRY_DELAY"
}
