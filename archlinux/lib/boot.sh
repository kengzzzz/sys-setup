#!/usr/bin/env bash

secure_boot_enabled() {
    local efivar_dir=${1:-/sys/firmware/efi/efivars}
    local secure_boot_var value

    for secure_boot_var in "$efivar_dir"/SecureBoot-*; do
        [[ -r $secure_boot_var ]] || continue
        value=$(od -An -t u1 -j 4 -N 1 "$secure_boot_var" | tr -d '[:space:]')
        [[ $value == 1 ]] && return 0
    done
    return 1
}

render_loader_config() {
    local default_entry=$1

    cat <<EOF
default $default_entry
timeout 3
console-mode max
editor no
EOF
}

render_boot_entry() {
    local title=$1
    local kernel=$2
    local root_partuuid=$3

    cat <<EOF
title Arch Linux ($title)
linux /vmlinuz-$kernel
initrd /initramfs-$kernel.img
options root=PARTUUID=$root_partuuid rw nvidia-drm.modeset=1 nvidia-drm.fbdev=1
EOF
}

write_boot_entry() {
    local title=$1
    local kernel=$2
    local output=$3

    render_boot_entry "$title" "$kernel" "$ROOT_PARTUUID" >"$output"
}
