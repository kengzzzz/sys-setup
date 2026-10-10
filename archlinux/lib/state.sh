#!/usr/bin/env bash

# Outside the checkout, so a re-run can reuse answers, keys, dotfiles and kernel.
STATE_DIR=${STATE_DIR:-/root/sys-setup-state}
TARGET_INSTALL_DIR=/mnt/root/sys-setup-install
# Path inside the chroot.
INSTALL_STATE=${INSTALL_STATE:-/root/sys-setup-install/state}

save_settings() {
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    write_settings "$STATE_DIR/settings.env.new"
    mv "$STATE_DIR/settings.env.new" "$STATE_DIR/settings.env"
}

offer_saved_state() {
    local answer kernel='none'
    [[ -f $STATE_DIR/settings.env ]] || return 0
    [[ ! -f $STATE_DIR/kernel/inputs ]] || kernel='built packages'

    section "Saved progress from an earlier attempt"
    printf 'Settings:  saved %s\n' "$(date -r "$STATE_DIR/settings.env" '+%Y-%m-%d %H:%M')"
    printf 'YubiKeys:  %s enrolled\n' "$(enrolled_key_count)"
    list_enrolled_keys
    printf 'Dotfiles:  %s\n' "$([[ -d $STATE_DIR/dotfiles/.git ]] && printf 'cloned' || printf 'not cloned')"
    printf 'Kernel:    %s\n' "$kernel"
    ask answer "Press Enter to reuse all of it, or type new to start over:"
    if [[ ${answer,,} == new ]]; then
        # Keep the kernel; it is reused only if its sources match.
        find "$STATE_DIR" -mindepth 1 -maxdepth 1 ! -name kernel -exec rm -rf {} +
        return 0
    fi
    load_config_file "$STATE_DIR/settings.env"
}

# Runs on every attempt so a retry picks up fixes.
stage_install_files() {
    local target=$TARGET_INSTALL_DIR repo_root
    repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
    install -d -m700 "$target" "$target/state"
    rsync -a --delete "$SCRIPT_DIR/" "$target/archlinux/"
    rsync -a --delete "$repo_root/lib/" "$target/lib/"

    ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PARTITION")
    [[ -n $ROOT_PARTUUID ]] || die "cannot read the PARTUUID of $ROOT_PARTITION"
    write_chroot_env "$target/state/install.env"
    install -d "$target/state/custom-kernel"
    rsync -a --delete "${CUSTOM_KERNEL_PACKAGES[@]}" "$target/state/custom-kernel/"
    if [[ -d $STATE_DIR/yubikeys ]]; then
        rsync -a --delete --exclude '.new.*' "$STATE_DIR/yubikeys/" "$target/state/yubikeys/"
    fi
    if [[ -f $STATE_DIR/known_hosts ]]; then
        install -m644 "$STATE_DIR/known_hosts" "$target/state/known_hosts"
    fi
    if [[ -s $STATE_DIR/user-password.hash ]]; then
        install -m600 "$STATE_DIR/user-password.hash" "$target/state/user-password.hash"
    fi
    if [[ $ENABLE_DOTFILES == 1 ]]; then
        rsync -a --delete "$STATE_DIR/dotfiles/" "$target/state/dotfiles/"
    fi
}

remove_staged_copies() {
    rm -rf "$TARGET_INSTALL_DIR/state/dotfiles" "$TARGET_INSTALL_DIR/state/user-password.hash"
}

save_live_fixes() {
    local repo_root diff
    repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
    diff=$(git -C "$repo_root" diff HEAD 2>/dev/null) || return 0
    [[ -n $diff ]] || return 0
    printf '%s\n' "$diff" >"$TARGET_INSTALL_DIR/live-fixes.patch"
    warn "the installer was changed during this run; see /root/sys-setup-install/live-fixes.patch on the new system"
}
