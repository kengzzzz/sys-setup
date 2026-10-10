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
    local sort_key=${4:-}
    local root_flags=''
    if [[ ${ROOT_FS:-btrfs} == btrfs ]]; then
        root_flags=' rootflags=subvol=@,compress=zstd:3,discard=async'
    fi

    printf 'title Arch Linux (%s)\n' "$title"
    [[ -z $sort_key ]] || printf 'sort-key %s\n' "$sort_key"
    cat <<EOF
linux /vmlinuz-$kernel
initrd /initramfs-$kernel.img
options root=PARTUUID=$root_partuuid rw$root_flags nvidia-drm.modeset=1 nvidia-drm.fbdev=1
EOF
}

firmware_boot_entry() {
    local efi_partuuid=$1
    efibootmgr -v 2>/dev/null | awk -v uuid="${efi_partuuid,,}" '
        /^Boot[0-9A-Fa-f]{4}/ && index(tolower($0), uuid) && index(tolower($0), "systemd-bootx64.efi") {
            print substr($1, 5, 4)
            exit
        }'
}

boot_order_with_first() {
    local first=$1 order=$2 entry result=$1
    local -a entries
    IFS=, read -ra entries <<<"$order"
    for entry in "${entries[@]}"; do
        [[ ${entry^^} == "${first^^}" ]] || result+=,$entry
    done
    printf '%s\n' "$result"
}

# Firmware may keep booting the disk the installer came from, and its fallback
# entries are all named "UEFI OS". Put systemd-boot first and force the next boot.
prefer_installed_system() {
    section "Setting the firmware boot order"
    local efi_partuuid entry order
    efi_partuuid=$(blkid -s PARTUUID -o value "$EFI_PARTITION")
    entry=$(firmware_boot_entry "$efi_partuuid")
    if [[ -z $entry ]]; then
        efibootmgr --create --disk "$TARGET_DEVICE" --part 1 --label 'Linux Boot Manager' \
            --loader '\EFI\systemd\systemd-bootx64.efi' >/dev/null || true
        entry=$(firmware_boot_entry "$efi_partuuid")
    fi
    if [[ -z $entry ]]; then
        warn "no firmware boot entry for the new system; pick it in the firmware boot menu"
        return 0
    fi
    order=$(efibootmgr | sed -n 's/^BootOrder: //p')
    efibootmgr --bootorder "$(boot_order_with_first "$entry" "$order")" >/dev/null \
        || warn "could not change the firmware boot order"
    efibootmgr --bootnext "$entry" >/dev/null || warn "could not set the next boot entry"
    log "firmware boots Boot$entry (Linux Boot Manager) first"
}

write_boot_entry() {
    local title=$1
    local kernel=$2
    local output=$3
    local sort_key=${4:-}

    render_boot_entry "$title" "$kernel" "$ROOT_PARTUUID" "$sort_key" >"$output"
}
