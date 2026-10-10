#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Re-sourced on retry to pick up fixes.
source_installer_libs() {
    # shellcheck source=../lib/common.sh
    source "$SCRIPT_DIR/../lib/common.sh"
    # shellcheck source=lib/config.sh
    source "$SCRIPT_DIR/lib/config.sh"
    # shellcheck source=lib/steps.sh
    source "$SCRIPT_DIR/lib/steps.sh"
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
    # shellcheck source=lib/auth.sh
    source "$SCRIPT_DIR/lib/auth.sh"
    # shellcheck source=lib/dotfiles.sh
    source "$SCRIPT_DIR/lib/dotfiles.sh"
    # shellcheck source=lib/state.sh
    source "$SCRIPT_DIR/lib/state.sh"
    # shellcheck source=lib/enroll.sh
    source "$SCRIPT_DIR/lib/enroll.sh"
    # shellcheck source=lib/ui.sh
    source "$SCRIPT_DIR/lib/ui.sh"
}

DRY_RUN=0
CONFIG_FILE=
STATE_DIR_FROM_ENV=${STATE_DIR:-}
# Bash presets HOSTNAME to the live ISO's own name.
HOSTNAME=arch-pc
source_installer_libs

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Asks everything first (disk, YubiKeys, plan), then installs unattended.

Options:
  --dry-run         Go through the questions, including YubiKey enrollment,
                    then print the plan without changing anything.
  --config FILE     Source installer variables from FILE before prompts.
  --kernel-packages-dir DIR
                    Install existing custom kernel packages from DIR.
  --no-dotfiles     Install the OS but skip private dotfiles setup.
  --no-workloads    Skip GPU-container and ARM64-container host packages.
  --restore-lact-config
                    Restore the GPU-specific LACT snapshot after a hardware check.
  -h, --help        Show this help.

Saved answers, YubiKey enrollments and built kernel packages are kept in
STATE_DIR (default /root/sys-setup-state) and offered again on the next run.
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

install_base_system() {
    pacstrap_base
    generate_fstab
}

run_chroot_install() {
    section "Running chroot install"
    resolve_target_disk
    validate_custom_kernel_packages
    stage_install_files
    rm -f "$TARGET_INSTALL_DIR/state/failed-step"
    arch-chroot /mnt bash /root/sys-setup-install/archlinux/chroot.sh
}

finish_target() {
    remove_install_sudoers /mnt
    configure_resolver_link
    remove_staged_copies
    save_live_fixes
    create_initial_snapshot
}

ask_questions() {
    [[ -n $TARGET_DISK && -z $(target_disk_error) ]] || choose_target_disk
    collect_credentials
    plan_screen
    show_install_plan
}

main() {
    parse_args "$@"
    init_logging
    require_root
    if [[ -n $CONFIG_FILE ]]; then
        load_config_file "$CONFIG_FILE"
    fi
    if (: </dev/tty) 2>/dev/null; then
        exec </dev/tty
    fi
    if [[ $DRY_RUN == 1 && -z $STATE_DIR_FROM_ENV ]]; then
        STATE_DIR=$(mktemp -d /tmp/sys-setup-dry-run.XXXXXX)
    fi
    offer_saved_state
    # Reparse so CLI options win over the config file and saved answers.
    parse_args "$@"
    set_default_config
    STEP_FAILURE_HANDLER=step_failure_menu

    if [[ $DRY_RUN != 1 ]]; then
        run_step "Preparing the live environment" prepare_live_environment
    fi
    ask_questions
    if [[ $DRY_RUN == 1 ]]; then
        log "dry run complete; nothing was installed (enrollment data: $STATE_DIR)"
        exit 0
    fi

    section "All questions are answered; the rest runs unattended"
    run_step "Setting up package repositories" prepare_live_repos
    if [[ -z $CUSTOM_KERNEL_PACKAGES_DIR ]]; then
        CUSTOM_KERNEL_PACKAGES_DIR=$STATE_DIR/kernel
        run_step "Building the custom kernel" prepare_custom_kernel_packages "$CUSTOM_KERNEL_PACKAGES_DIR"
    fi
    run_step "Checking packages before erasing the disk" validate_package_selection
    setup_mount_cleanup
    run_step "Partitioning and formatting the disk" prepare_target_disk
    run_step "Installing the base system" install_base_system
    run_step "$CHROOT_STEP" run_chroot_install
    run_step "Finishing the new system" finish_target
    final_unmount
    finish_installation
}

main "$@"
