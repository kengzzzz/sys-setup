#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"
# shellcheck source=lib/dotfiles.sh
source "$SCRIPT_DIR/lib/dotfiles.sh"
# shellcheck source=lib/network.sh
source "$SCRIPT_DIR/lib/network.sh"
# shellcheck source=lib/auth.sh
source "$SCRIPT_DIR/lib/auth.sh"
# shellcheck source=lib/boot.sh
source "$SCRIPT_DIR/lib/boot.sh"
# shellcheck source=install.env
source "$SCRIPT_DIR/install.env"

configure_pacman() {
    section "Configuring pacman"
    sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//;}' /etc/pacman.conf
    setup_cachyos_repo
    sync_pacman
}

configure_locale_time() {
    section "Configuring timezone and locale"
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    hwclock --systohc
    : >/etc/locale.gen
    printf '%s UTF-8\n' "$LOCALE" >>/etc/locale.gen
    for extra_locale in $EXTRA_LOCALES; do
        printf '%s UTF-8\n' "$extra_locale" >>/etc/locale.gen
    done
    locale-gen
    printf 'LANG=%s\n' "$LOCALE" >/etc/locale.conf
    printf 'KEYMAP=%s\n' "$KEYMAP" >/etc/vconsole.conf
    printf '%s\n' "$HOSTNAME" >/etc/hostname
}

configure_mkinitcpio() {
    section "Configuring mkinitcpio"
    sed -i 's/#COMPRESSION="zstd"/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
    sed -i 's/#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(--ultra -22 -T0)/' /etc/mkinitcpio.conf
    grep -q '^COMPRESSION="zstd"' /etc/mkinitcpio.conf || echo 'COMPRESSION="zstd"' >>/etc/mkinitcpio.conf
    grep -q '^COMPRESSION_OPTIONS=' /etc/mkinitcpio.conf || echo 'COMPRESSION_OPTIONS=(--ultra -22 -T0)' >>/etc/mkinitcpio.conf
}

configure_sudoers() {
    section "Configuring sudoers"
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
}

enable_services() {
    section "Enabling services"
    systemctl enable systemd-networkd systemd-resolved greetd pcscd bluetooth tailscaled docker.socket fstrim.timer xfs_scrub_all.timer accounts-daemon
}

create_user() {
    section "Creating user"
    if id "$INSTALL_USER" >/dev/null 2>&1; then
        warn "user already exists: $INSTALL_USER"
    else
        useradd -m -G wheel -s /bin/zsh "$INSTALL_USER"
    fi
}

install_bootloader() {
    section "Installing systemd-boot"
    bootctl --no-variables install
    mkdir -p /boot/loader/entries
    cat >/boot/loader/loader.conf <<EOF
default ${PRIMARY_KERNEL}.conf
timeout 3
console-mode max
editor no
EOF
    write_boot_entry "$PRIMARY_KERNEL" "$PRIMARY_KERNEL" "/boot/loader/entries/${PRIMARY_KERNEL}.conf"
    write_boot_entry "$FALLBACK_KERNEL" "$FALLBACK_KERNEL" "/boot/loader/entries/${FALLBACK_KERNEL}.conf"
}

set_passwords() {
    section "Set passwords"
    printf 'Set root password:\n'
    passwd
    printf 'Set password for %s:\n' "$INSTALL_USER"
    passwd "$INSTALL_USER"
}

main() {
    configure_pacman
    configure_locale_time
    configure_static_network
    configure_mkinitcpio
    install_official_packages
    install_custom_kernel_packages
    configure_sudoers
    enable_services
    create_user
    install_bootloader
    set_passwords
    run_dotfiles_install
    configure_yubikey_system_auth
}

main "$@"
