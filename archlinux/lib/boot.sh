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

kernel_cmdline() {
    local root_partuuid=$1
    local root_flags=''
    if [[ ${ROOT_FS:-btrfs} == btrfs ]]; then
        root_flags=' rootflags=subvol=@,compress=zstd:3,discard=async'
    fi
    printf 'root=PARTUUID=%s rw%s nvidia-drm.modeset=1 nvidia-drm.fbdev=1 quiet loglevel=3 systemd.show_status=false video=DP-3:3440x1440@240 fbcon=nodefer libahci.ignore_sss=1 usbcore.quirks=048d:5711:i\n' \
        "$root_partuuid" "$root_flags"
}

# limine-entry-tool and limine-snapper-sync both read this file. The command
# line is explicit because the tool would otherwise copy /proc/cmdline, which
# is the live ISO's during installation.
render_limine_defaults() {
    local root_partuuid=$1

    cat <<EOF
ESP_PATH="/boot"
UEFI_BOOT_ORDER=first
ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=no
KERNEL_CMDLINE[default]=$(kernel_cmdline "$root_partuuid")
BOOT_ORDER="$PRIMARY_KERNEL, *, *fallback, Snapshots"
EOF
    [[ ${ROOT_FS:-btrfs} == btrfs ]] || return 0
    cat <<'EOF'

SNAPPER_CONFIG_NAME="root"
ROOT_SUBVOLUME_PATH="/@"
ROOT_SNAPSHOTS_PATH="/@snapshots"
EXCLUDE_SNAPSHOT_TYPES="post"
EOF
}

firmware_boot_entry() {
    local efi_partuuid=$1
    efibootmgr -v 2>/dev/null | awk -v uuid="${efi_partuuid,,}" '
        /^Boot[0-9A-Fa-f]{4}/ && index(tolower($0), uuid) && index(tolower($0), "limine_x64.efi") {
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
# entries are all named "UEFI OS". Put Limine first and force the next boot.
prefer_installed_system() {
    section "Setting the firmware boot order"
    local efi_partuuid entry order
    efi_partuuid=$(blkid -s PARTUUID -o value "$EFI_PARTITION")
    entry=$(firmware_boot_entry "$efi_partuuid")
    if [[ -z $entry ]]; then
        efibootmgr --create --disk "$TARGET_DEVICE" --part 1 --label Limine \
            --loader '\EFI\limine\limine_x64.efi' >/dev/null || true
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
    log "firmware boots Boot$entry (Limine) first"
}
