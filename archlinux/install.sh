#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/disk.sh
source "$SCRIPT_DIR/lib/disk.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"

DRY_RUN=0
CONFIG_FILE=

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --dry-run         Print the selected plan and skip installation.
  --config FILE     Source installer variables from FILE before prompts.
  --kernel-packages-dir DIR
                    Install existing custom kernel packages from DIR.
  --no-dotfiles     Install the OS but skip private dotfiles setup.
  -h, --help        Show this help.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                ;;
            --config)
                shift
                CONFIG_FILE=${1:-}
                [[ -n $CONFIG_FILE ]] || die "--config requires a file"
                ;;
            --kernel-packages-dir)
                shift
                CUSTOM_KERNEL_PACKAGES_DIR=${1:-}
                CUSTOM_KERNEL_BUILD=0
                [[ -n $CUSTOM_KERNEL_PACKAGES_DIR ]] || die "--kernel-packages-dir requires a directory"
                ;;
            --no-dotfiles)
                ENABLE_DOTFILES=0
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "unknown argument: $1"
                ;;
        esac
        shift
    done
}

copy_installer_to_target() {
    section "Copying installer into target"
    local target_dir=/mnt/root/sys-setup-install
    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    cp -a "$SCRIPT_DIR/." "$target_dir/"
    write_chroot_env "$target_dir/install.env"
    chmod +x "$target_dir/install.sh" "$target_dir/chroot.sh"
}

run_chroot_install() {
    section "Running chroot install"
    retry arch-chroot /mnt /root/sys-setup-install/chroot.sh
}

main() {
    parse_args "$@"
    init_logging
    require_root
    set_default_config
    if [[ -n $CONFIG_FILE ]]; then
        load_config_file "$CONFIG_FILE"
        set_default_config
    fi

    if [[ -r /dev/tty ]]; then
        exec </dev/tty
    fi

    prompt_install_config
    validate_config
    derive_partitions
    show_install_plan

    if [[ $DRY_RUN == 1 ]]; then
        log "dry run complete"
        exit 0
    fi

    build_custom_kernel_packages
    validate_custom_kernel_packages
    confirm_destructive_install
    setup_mount_cleanup
    prepare_live_environment
    partition_disk
    format_partitions
    mount_target
    setup_cachyos_repo
    sync_pacman
    pacstrap_base
    generate_fstab
    ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PARTITION")
    copy_installer_to_target
    copy_custom_kernel_packages_to_target
    run_chroot_install
    final_unmount
    section "Installation complete"
    log "reboot into the installed system when ready"
    if confirm_yes_no "Reboot now?" "N"; then
        run reboot
    fi
}

main "$@"
