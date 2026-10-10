#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALL_STATE=$(cd -- "$SCRIPT_DIR/../state" && pwd)

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/steps.sh
source "$SCRIPT_DIR/lib/steps.sh"
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
# shellcheck source=lib/services.sh
source "$SCRIPT_DIR/lib/services.sh"
# shellcheck source=lib/snapshots.sh
source "$SCRIPT_DIR/lib/snapshots.sh"
# shellcheck source=/dev/null
source "$INSTALL_STATE/install.env"

STEP_DONE_DIR=$INSTALL_STATE/done
STEP_FAILURE_HANDLER=record_failed_step

record_failed_step() {
    printf '%s\n' "$1" >"$INSTALL_STATE/failed-step"
    return 1
}

configure_pacman() {
    section "Configuring pacman"
    enable_multilib
    pacman-key --populate archlinux cachyos
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

install_bootloader() {
    section "Installing systemd-boot"
    mkinitcpio -P
    local kernel
    for kernel in "$PRIMARY_KERNEL" "$FALLBACK_KERNEL"; do
        [[ -s /boot/vmlinuz-$kernel && -s /boot/initramfs-$kernel.img ]] \
            || die "boot artifacts missing for $kernel"
    done
    bootctl install
    mkdir -p /boot/loader/entries
    render_loader_config "$BOOT_ENTRY" >/boot/loader/loader.conf
    # Without sort keys systemd-boot lists the fallback first (file names, descending).
    write_boot_entry "$PRIMARY_KERNEL" "$PRIMARY_KERNEL" "/boot/loader/entries/$BOOT_ENTRY" arch-1
    write_boot_entry "$FALLBACK_KERNEL" "$FALLBACK_KERNEL" "/boot/loader/entries/${FALLBACK_KERNEL}.conf" arch-2
}

main() {
    trap remove_install_sudoers EXIT
    run_step pacman configure_pacman
    run_step locale configure_locale_time
    run_step network configure_static_network
    run_step mkinitcpio configure_mkinitcpio
    run_step official-packages install_official_packages
    run_step custom-kernel install_custom_kernel_packages
    run_step container-runtime configure_container_runtime
    run_step sudoers configure_sudoers
    run_step services enable_system_services
    run_step accounts configure_accounts
    run_step bootloader install_bootloader
    run_step aur-packages install_aur_packages_as_user
    run_step ssh-keys install_user_ssh_keys
    run_dotfiles_install
    run_step yubikey-auth configure_yubikey_system_auth
    run_step tailscale-login configure_tailscale_first_login
    run_step snapshots configure_btrfs_snapshots
}

main "$@"
