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
    sed -i 's/^MODULES=()$/MODULES=(nvidia? nvidia_modeset? nvidia_uvm? nvidia_drm?)/' /etc/mkinitcpio.conf
    grep -q '^MODULES=(nvidia' /etc/mkinitcpio.conf || echo 'MODULES=(nvidia? nvidia_modeset? nvidia_uvm? nvidia_drm?)' >>/etc/mkinitcpio.conf
}

configure_sudoers() {
    section "Configuring sudoers"
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
}

install_bootloader() {
    section "Installing Limine"
    # Kernels go under /boot/<machine-id>, so the ID must exist before the hook runs.
    [[ -s /etc/machine-id ]] || systemd-machine-id-setup
    render_limine_defaults "$ROOT_PARTUUID" >/etc/default/limine
    local packages=(limine limine-mkinitcpio-hook)
    [[ $ROOT_FS != btrfs ]] || packages+=(limine-snapper-sync inotify-tools)
    retry pacman -S --noconfirm --needed "${packages[@]}"
    if [[ $ROOT_FS == btrfs ]]; then
        # The hook comes with limine-mkinitcpio-hook, so it can only be added now.
        grep -q '^HOOKS=.* sd-btrfs-overlayfs' /etc/mkinitcpio.conf \
            || sed -i '/^HOOKS=/s/ filesystems / filesystems sd-btrfs-overlayfs /' /etc/mkinitcpio.conf
        grep -q '^HOOKS=.* filesystems sd-btrfs-overlayfs' /etc/mkinitcpio.conf \
            || die "could not add sd-btrfs-overlayfs to HOOKS in /etc/mkinitcpio.conf"
    fi
    limine-update
    # Left by the kernel installs that ran before the Limine hook existed.
    rm -f /boot/vmlinuz-* /boot/initramfs-*.img
    # Limine sets LoaderFeatures, which makes systemd write a seed Limine never reads into /boot/loader.
    systemctl mask systemd-boot-random-seed.service
    [[ -s /boot/EFI/limine/limine_x64.efi ]] || die "Limine is missing from the ESP"
    local kernel
    for kernel in "$PRIMARY_KERNEL" "$FALLBACK_KERNEL"; do
        grep -q "^[[:space:]]*//$kernel\$" /boot/limine.conf || die "no Limine entry for $kernel"
    done
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
