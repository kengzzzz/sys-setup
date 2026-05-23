#!/usr/bin/env bash

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
