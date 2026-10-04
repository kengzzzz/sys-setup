#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"
# shellcheck source=lib/config.sh
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/disk.sh
source "$SCRIPT_DIR/lib/disk.sh"
# shellcheck source=lib/packages.sh
source "$SCRIPT_DIR/lib/packages.sh"
# shellcheck source=lib/boot.sh
source "$SCRIPT_DIR/lib/boot.sh"
# shellcheck source=lib/network.sh
source "$SCRIPT_DIR/lib/network.sh"
# shellcheck source=lib/snapshots.sh
source "$SCRIPT_DIR/lib/snapshots.sh"

DRY_RUN=0
CONFIG_FILE=
HOSTNAME=arch-pc

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Options:
  --dry-run         Print the selected plan and skip installation.
  --config FILE     Source installer variables from FILE before prompts.
  --kernel-packages-dir DIR
                    Install existing custom kernel packages from DIR.
  --no-dotfiles     Install the OS but skip private dotfiles setup.
  --no-workloads    Skip GPU-container and ARM64-container host packages.
  --restore-lact-config
                    Restore the GPU-specific LACT snapshot after a hardware check.
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
            --no-workloads)
                ENABLE_WORKLOAD_PACKAGES=0
                ;;
            --restore-lact-config)
                RESTORE_LACT_CONFIG=1
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
    mkdir -p "$target_dir/archlinux"
    cp -a "$SCRIPT_DIR/." "$target_dir/archlinux/"
    cp -a "$SCRIPT_DIR/../lib" "$target_dir/lib"
    write_chroot_env "$target_dir/archlinux/install.env"
    chmod +x "$target_dir/archlinux/install.sh" "$target_dir/archlinux/chroot.sh"
}

run_chroot_install() {
    section "Running chroot install"
    run arch-chroot /mnt /root/sys-setup-install/archlinux/chroot.sh
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
    # Reparse after loading config so CLI options win.
    parse_args "$@"

    if (: </dev/tty) 2>/dev/null; then
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

    prepare_live_environment
    enable_multilib
    setup_cachyos_repo
    sync_pacman
    build_custom_kernel_packages
    validate_custom_kernel_packages
    validate_package_selection
    confirm_destructive_install
    setup_mount_cleanup
    partition_disk
    format_partitions
    mount_target
    pacstrap_base
    generate_fstab
    ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PARTITION")
    copy_installer_to_target
    copy_custom_kernel_packages_to_target
    run_chroot_install
    configure_resolver_link
    create_initial_snapshot
    final_unmount
    section "Installation complete"
    log "reboot into the installed system when ready"
    if confirm_yes_no "Reboot now?" "N"; then
        run reboot
    fi
}

main "$@"
