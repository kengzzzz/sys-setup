#!/usr/bin/env bash

CHROOT_STEP="Installing the system (chroot)"
# Typing - clears these.
OPTIONAL_SETTINGS=(EXTRA_LOCALES TAILSCALE_UP_ARGS)

setting_label() {
    case $1 in
        TARGET_DISK) echo "Disk to ERASE" ;;
        INSTALL_USER) echo "User" ;;
        HOSTNAME) echo "Hostname" ;;
        TIMEZONE) echo "Timezone" ;;
        LOCALE) echo "Locale" ;;
        EXTRA_LOCALES) echo "Extra locales" ;;
        KEYMAP) echo "Console keymap" ;;
        ROOT_FS) echo "Root filesystem" ;;
        EFI_SIZE) echo "EFI partition size" ;;
        PRIMARY_KERNEL) echo "Primary kernel" ;;
        FALLBACK_KERNEL) echo "Fallback kernel" ;;
        FALLBACK_NVIDIA_PACKAGE) echo "Fallback NVIDIA package" ;;
        BOOT_ENTRY) echo "Primary boot entry" ;;
        NETWORK_INTERFACE) echo "Network interface" ;;
        NETWORK_ADDRESS) echo "Static address" ;;
        NETWORK_GATEWAY) echo "Gateway" ;;
        NETWORK_DNS) echo "DNS" ;;
        YUBIKEY_SYSTEM_AUTH) echo "YubiKey sudo/login" ;;
        ENABLE_DOTFILES) echo "Dotfiles" ;;
        DOTFILES_REPO) echo "Dotfiles repo" ;;
        DOTFILES_BRANCH) echo "Dotfiles branch" ;;
        RESTORE_LACT_CONFIG) echo "Restore LACT config" ;;
        ENABLE_WORKLOAD_PACKAGES) echo "GPU/ARM64 container tools" ;;
        TAILSCALE_FIRST_LOGIN) echo "Tailscale on first login" ;;
        TAILSCALE_UP_ARGS) echo "tailscale up options" ;;
        AUTO_REBOOT) echo "Reboot when finished" ;;
        *) echo "$1" ;;
    esac
}

setting_display() {
    local name=$1
    if is_boolean_setting "$name"; then
        on_off "${!name}"
    elif [[ $name == TARGET_DISK && -n $TARGET_DISK && -b $TARGET_DISK ]]; then
        describe_disk "$(readlink -f -- "$TARGET_DISK")"
    else
        printf '%s' "${!name:-(none)}"
    fi
}

is_optional_setting() {
    local name=$1 optional
    for optional in "${OPTIONAL_SETTINGS[@]}"; do
        [[ $optional != "$name" ]] || return 0
    done
    return 1
}

show_plan() {
    local i name message
    section "Installation plan"
    for i in "${!SETTINGS_VARS[@]}"; do
        name=${SETTINGS_VARS[i]}
        printf '  %2d) %-26s %s\n' $((i + 1)) "$(setting_label "$name")" "$(setting_display "$name")"
        while IFS= read -r message; do
            [[ -z $message ]] || printf '        ! %s\n' "$message"
        done < <(setting_error "$name")
        while IFS= read -r message; do
            [[ -z $message ]] || printf '        ~ %s\n' "$message"
        done < <(setting_warning "$name")
        if [[ $name == TARGET_DISK && -n $TARGET_DISK && -b $TARGET_DISK ]]; then
            show_disk_contents "$(readlink -f -- "$TARGET_DISK")" '          '
        fi
    done
    printf '\n  YubiKeys:\n'
    if (($(enrolled_key_count) > 0)); then
        list_enrolled_keys | sed 's/^/  /'
    else
        printf '    (none)\n'
    fi
    if [[ $ENABLE_DOTFILES == 1 ]]; then
        printf '  Dotfiles: %s\n' "$(dotfiles_clone_needed && printf 'not cloned' || printf 'cloned from %s' "$(dotfiles_source)")"
    fi
}

plan_problems() {
    config_errors
    { credential_problems; dotfiles_problems; } | sed -n 's/^error: //p'
}

plan_warnings() {
    { dotfiles_problems; } | sed -n 's/^warning: //p'
}

edit_setting() {
    local index=$1 name old value error hint=''
    if ! [[ $index =~ ^[0-9]+$ ]] || ((index < 1 || index > ${#SETTINGS_VARS[@]})); then
        warn "there is no setting $index"
        return 0
    fi
    name=${SETTINGS_VARS[index - 1]}
    if is_boolean_setting "$name"; then
        printf -v "$name" '%s' $((1 - ${!name}))
        return 0
    fi
    case $name in
        TARGET_DISK)
            choose_target_disk
            return 0
            ;;
        ROOT_FS)
            [[ $ROOT_FS == btrfs ]] && ROOT_FS=xfs || ROOT_FS=btrfs
            return 0
            ;;
    esac
    old=${!name}
    ! is_optional_setting "$name" || hint=', - clears it'
    while true; do
        ask value "$(setting_label "$name") [${old}] (Enter keeps it${hint}):"
        [[ -n $value ]] || return 0
        [[ $value != - ]] || ! is_optional_setting "$name" || value=''
        printf -v "$name" '%s' "$value"
        error=$(setting_error "$name")
        if [[ -z $error ]]; then
            derive_config
            return 0
        fi
        warn "$error"
        printf -v "$name" '%s' "$old"
    done
}

manage_yubikeys() {
    local answer
    while true; do
        section "YubiKeys"
        if (($(enrolled_key_count) > 0)); then
            list_enrolled_keys
        else
            printf '  (none)\n'
        fi
        ask answer "a = add keys, r = remove one, Enter = back:"
        case ${answer,,} in
            a) enroll_yubikeys ;;
            r) remove_enrolled_key ;;
            '') return 0 ;;
            *) warn "unknown choice: $answer" ;;
        esac
    done
}

resolve_plan_problems() {
    if [[ $YUBIKEY_SYSTEM_AUTH == 1 ]] && ! u2f_credentials "$(yubikeys_dir)" >/dev/null 2>&1; then
        enroll_yubikeys
    fi
    if [[ $YUBIKEY_SYSTEM_AUTH != 1 && ! -s $STATE_DIR/user-password.hash ]]; then
        ask_user_password
    fi
    if dotfiles_clone_needed; then
        ensure_dotfiles_clone || true
    fi
}

print_list() {
    local title=$1 line
    printf '\n%s\n' "$title"
    while IFS= read -r line; do
        printf '  - %s\n' "$line"
    done <<<"$2"
}

plan_screen() {
    local answer problems warnings device
    while true; do
        show_plan
        problems=$(plan_problems)
        warnings=$(plan_warnings)
        [[ -z $warnings ]] || print_list "Warnings:" "$warnings"
        [[ -z $problems ]] || print_list "Must fix before installing:" "$problems"
        device='(no disk chosen)'
        [[ -z $TARGET_DISK ]] || device=$(readlink -f -- "$TARGET_DISK")
        printf '\nType a number to change it, k for YubiKeys, d to clone dotfiles again, q to quit.\n'
        ask answer "Type y to ERASE ${device} and install:"
        case ${answer,,} in
            y | yes)
                resolve_plan_problems
                problems=$(plan_problems)
                if [[ -z $problems ]]; then
                    save_settings
                    return 0
                fi
                warn "fix the problems listed under the plan first"
                ;;
            k) manage_yubikeys ;;
            d)
                rm -f "$STATE_DIR/dotfiles.source"
                ensure_dotfiles_clone || true
                ;;
            q | quit)
                save_settings
                log "settings saved; run the installer again to continue"
                exit 0
                ;;
            '') ;;
            *) edit_setting "$answer" ;;
        esac
        save_settings
    done
}

failed_chroot_step() {
    local file=$TARGET_INSTALL_DIR/state/failed-step
    [[ $1 == "$CHROOT_STEP" && -s $file ]] && cat "$file"
    return 0
}

open_rescue_shell() {
    printf '\nShell in the live environment. The new system is mounted at /mnt;\n'
    printf 'enter it with: arch-chroot /mnt\nLog: %s\nType exit to return to the menu.\n\n' "$INSTALL_LOG"
    "${SHELL:-/bin/bash}" -i </dev/tty >/dev/tty 2>&1 || true
}

rescue_prompt() {
    local step=$1 chroot_step=$2 repo_root=$3
    cat <<EOF
Help me fix a failed Arch Linux installation. You are root on the Arch live ISO.
The installer stopped at the step "$step"${chroot_step:+ (inside the chroot, at "$chroot_step")}.
- Installer source: $repo_root (archlinux/install.sh, archlinux/chroot.sh, archlinux/lib/). Edits there are reloaded and copied into the new system when I choose retry.
- Full log: $INSTALL_LOG; read its end first.
- New system: mounted at /mnt; run commands in it with arch-chroot /mnt. Finished chroot steps are marked in /mnt/root/sys-setup-install/state/done.
- Saved settings, YubiKey enrollments and kernel packages: $STATE_DIR.
Find the cause and fix it in the installer code or the system, then tell me to retry. Do not partition, format or wipe disks, do not reboot, and keep $STATE_DIR.
EOF
}

start_rescue_agent() {
    local step=$1 chroot_step=$2 answer package command repo_root
    repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
    ask answer "c = Claude Code, x = Codex [c]:"
    case ${answer,,} in
        '' | c) package=claude-code command=claude ;;
        x) package=openai-codex command=codex ;;
        *)
            warn "unknown agent: $answer"
            return 0
            ;;
    esac
    if ! command -v "$command" >/dev/null 2>&1; then
        log "installing $package in the live environment"
        pacman -S --noconfirm --needed "$package" || {
            warn "could not install $package; use the shell (s) instead"
            return 0
        }
    fi
    printf '\nStarting %s. If it asks you to log in, open the link on your phone.\n' "$command"
    printf 'Leave it to return to this menu.\n\n'
    (cd "$repo_root" && "$command" "$(rescue_prompt "$step" "$chroot_step" "$repo_root")") \
        </dev/tty >/dev/tty 2>&1 || true
}

step_failure_menu() {
    local step=$1 status=$2 chroot_step answer
    chroot_step=$(failed_chroot_step "$step")
    section "FAILED: $step${chroot_step:+ (at $chroot_step)}, exit status $status"
    printf 'Log: %s\n' "$INSTALL_LOG"
    printf 'Nothing is lost. Fix the cause, then retry; finished steps are not repeated.\n'
    while true; do
        printf '\n  r  retry the step\n'
        printf '  s  open a shell (new system mounted at /mnt)\n'
        printf '  a  start an AI agent (Claude Code or Codex) with the error details\n'
        printf '  k  skip %s (only when you are sure it is not needed)\n' "${chroot_step:-this step}"
        printf '  q  quit (settings, YubiKeys and kernel packages are kept for the next run)\n'
        ask answer "Choice:"
        case ${answer,,} in
            r)
                source_installer_libs
                return 0
                ;;
            s) open_rescue_shell ;;
            a) start_rescue_agent "$step" "$chroot_step" ;;
            k)
                confirm_yes_no "Skip ${chroot_step:-$step}?" N || continue
                [[ -n $chroot_step ]] || return 2
                # The chroot run then continues past it.
                mkdir -p "$TARGET_INSTALL_DIR/state/done"
                : >"$TARGET_INSTALL_DIR/state/done/$chroot_step"
                source_installer_libs
                return 0
                ;;
            q)
                confirm_yes_no "Quit the installer?" N || continue
                printf 'Run %s again to continue; saved answers are offered for reuse.\n' "$SCRIPT_DIR/install.sh"
                return 1
                ;;
            '') ;;
            *) warn "unknown choice: $answer" ;;
        esac
    done
}

finish_installation() {
    section "Installation complete"
    if [[ $AUTO_REBOOT == 1 ]]; then
        drain_input
        printf 'Rebooting in 15 seconds. Press any key to stay in the live environment.\n'
        if read -rsn1 -t 15 _; then
            log "reboot cancelled; type reboot when ready"
            return 0
        fi
        reboot
    elif confirm_yes_no "Reboot now?" N; then
        reboot
    fi
}
