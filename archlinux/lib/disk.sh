#!/usr/bin/env bash

partition_suffix() {
    local disk=$1

    if [[ $disk =~ [0-9]$ ]]; then
        printf 'p'
    fi
}

# TARGET_DISK is a by-id path because NVMe names can change between boots.
resolve_target_disk() {
    TARGET_DEVICE=$(readlink -f -- "$TARGET_DISK")
    derive_partitions
}

derive_partitions() {
    local suffix
    suffix=$(partition_suffix "$TARGET_DEVICE")
    EFI_PARTITION="${TARGET_DEVICE}${suffix}1"
    ROOT_PARTITION="${TARGET_DEVICE}${suffix}2"
}

stable_disk_path() {
    local device=$1
    local by_id=${2:-/dev/disk/by-id}
    local link

    for link in "$by_id"/*; do
        # Prefer model_serial links.
        case ${link##*/} in
            *-part[0-9]* | nvme-eui.* | nvme-nvme.* | wwn-* | *_[0-9]) continue ;;
        esac
        if [[ $(readlink -f -- "$link") == "$device" ]]; then
            printf '%s\n' "$link"
            return 0
        fi
    done
    printf '%s\n' "$device"
}

live_boot_disk() {
    local source parent
    source=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null) || return 0
    source=$(readlink -f -- "$source")
    parent=$(lsblk -no PKNAME "$source" 2>/dev/null | head -n1)
    printf '%s\n' "${parent:-${source##*/}}"
}

# Still detects the boot USB after copytoram unmounted it.
is_arch_install_medium() {
    [[ $(lsblk -dno FSTYPE "$1" 2>/dev/null) == iso9660 && $(lsblk -dno LABEL "$1" 2>/dev/null) == ARCH_* ]]
}

disk_candidates() {
    local boot name type
    boot=$(live_boot_disk)
    while read -r name type; do
        [[ $type == disk && $name != zram* && $name != "$boot" ]] || continue
        ! is_arch_install_medium "/dev/$name" || continue
        printf '/dev/%s\n' "$name"
    done < <(lsblk -dn -o NAME,TYPE)
}

disk_property() {
    lsblk -dn -o "$1" "$2" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

describe_disk() {
    local device=$1 model serial
    model=$(disk_property MODEL "$device")
    serial=$(disk_property SERIAL "$device")
    printf '%s  %s  %s%s' "$device" "$(disk_property SIZE "$device")" "${model:-unknown model}" \
        "${serial:+  (serial $serial)}"
}

show_disk_contents() {
    local device=$1 indent=${2:-       } contents line
    contents=$(lsblk -n -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINTS "$device" 2>/dev/null | tail -n +2)
    if [[ -n $contents ]]; then
        while IFS= read -r line; do
            printf '%s%s\n' "$indent" "$line"
        done <<<"$contents"
    else
        printf '%s(no partitions)\n' "$indent"
    fi
}

disk_in_use() {
    lsblk -nr -o MOUNTPOINTS "$1" | grep -q '[^[:space:]]'
}

target_disk_error() {
    local device type
    [[ -n ${TARGET_DISK:-} ]] || {
        echo "choose the disk to erase"
        return 0
    }
    device=$(readlink -f -- "$TARGET_DISK")
    [[ -b $device ]] || {
        echo "not found: $TARGET_DISK"
        return 0
    }
    type=$(lsblk -dn -o TYPE "$device")
    [[ $type == disk || $type == loop ]] || {
        echo "must be a whole disk, not a $type"
        return 0
    }
    if [[ ${device##*/} == "$(live_boot_disk)" ]] || is_arch_install_medium "$device"; then
        echo "this is the drive the installer booted from"
        return 0
    fi
    if [[ ${DRY_RUN:-0} != 1 ]] && disk_in_use "$device"; then
        echo "a partition on $device is mounted or used as swap"
        return 0
    fi
    sgdisk --pretend --clear -n "1:0:+${EFI_SIZE}" -t 1:ef00 \
        -n 2:0:0 -t 2:8304 "$device" >/dev/null 2>&1 \
        || echo "too small for a ${EFI_SIZE} EFI partition plus root"
}

choose_target_disk() {
    local -a disks
    local i answer default='' current error
    mapfile -t disks < <(disk_candidates)
    ((${#disks[@]} > 0)) || die "no installable disks found"
    current=$(readlink -f -- "${TARGET_DISK:-/nonexistent}")

    section "Choose the disk to ERASE and install Arch Linux on"
    for i in "${!disks[@]}"; do
        printf '\n  %d) %s\n' $((i + 1)) "$(describe_disk "${disks[i]}")"
        show_disk_contents "${disks[i]}"
        [[ ${disks[i]} != "$current" ]] || default=$((i + 1))
    done
    printf '\n'
    while true; do
        ask answer "Disk number${default:+ [$default]}:"
        answer=${answer:-$default}
        if [[ $answer =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#disks[@]})); then
            TARGET_DISK=$(stable_disk_path "${disks[answer - 1]}")
            error=$(target_disk_error)
            [[ -z $error ]] && return 0
            warn "$error"
        elif [[ -n $answer ]]; then
            warn "type a number from the list"
        fi
    done
}

release_target_mounts() {
    local source parent
    mountpoint -q /mnt || return 0
    # Left over from a failed attempt of this step.
    source=$(findmnt -no SOURCE /mnt)
    source=${source%%\[*}
    parent=$(lsblk -no PKNAME "$source" 2>/dev/null | head -n1)
    [[ /dev/$parent == "$TARGET_DEVICE" ]] || die "/mnt holds another filesystem ($source); unmount it first"
    umount -R /mnt
}

prepare_target_disk() {
    local error
    resolve_target_disk
    release_target_mounts
    error=$(target_disk_error)
    [[ -z $error ]] || die "$TARGET_DISK: $error"
    partition_disk
    format_partitions
    mount_target
}

partition_disk() {
    section "Partitioning $TARGET_DEVICE"
    run wipefs -a "$TARGET_DEVICE"
    run sgdisk --zap-all "$TARGET_DEVICE"
    run sgdisk -n "1:0:+${EFI_SIZE}" -t 1:ef00 -c 1:"EFI System Partition" "$TARGET_DEVICE"
    run sgdisk -n 2:0:0 -t 2:8304 -c 2:"Linux Root" "$TARGET_DEVICE"
    run partprobe "$TARGET_DEVICE"
    run udevadm settle
}

format_partitions() {
    section "Formatting partitions"
    retry mkfs.fat -F 32 "$EFI_PARTITION"
    if [[ $ROOT_FS == btrfs ]]; then
        retry mkfs.btrfs -f "$ROOT_PARTITION"
    else
        retry mkfs.xfs -f -m crc=1,reflink=1,rmapbt=1 "$ROOT_PARTITION"
    fi
    # Refresh filesystem metadata after replacing a previous filesystem.
    run udevadm trigger --action=change "$EFI_PARTITION" "$ROOT_PARTITION"
    run udevadm settle
}

mount_target() {
    section "Mounting target"
    if [[ $ROOT_FS == btrfs ]]; then
        local options=noatime,compress=zstd:3,discard=async
        local subvolume
        run mount -t btrfs -o "$options,subvolid=5" "$ROOT_PARTITION" /mnt
        for subvolume in @ @home @log @cache @docker @containerd @snapshots; do
            run btrfs subvolume create "/mnt/$subvolume"
        done
        run umount /mnt
        run mount -t btrfs -o "$options,subvol=@" "$ROOT_PARTITION" /mnt
        run mount --mkdir -t btrfs -o "$options,subvol=@home" "$ROOT_PARTITION" /mnt/home
        run mount --mkdir -t btrfs -o "$options,subvol=@log" "$ROOT_PARTITION" /mnt/var/log
        run mount --mkdir -t btrfs -o "$options,subvol=@cache" "$ROOT_PARTITION" /mnt/var/cache
        run mount --mkdir -t btrfs -o "$options,subvol=@docker" "$ROOT_PARTITION" /mnt/var/lib/docker
        run mount --mkdir -t btrfs -o "$options,subvol=@containerd" "$ROOT_PARTITION" /mnt/var/lib/containerd
        run mount --mkdir -t btrfs -o "$options,subvol=@snapshots" "$ROOT_PARTITION" /mnt/.snapshots
        chmod 700 /mnt/.snapshots
    else
        run mount -t xfs -o noatime "$ROOT_PARTITION" /mnt
    fi
    run mount --mkdir -t vfat -o defaults,noatime,umask=0077 "$EFI_PARTITION" /mnt/boot
    mkdir -p /mnt/etc /mnt/var/cache/pacman/pkg /mnt/var/log
    printf 'KEYMAP=%s\n' "$KEYMAP" >/mnt/etc/vconsole.conf
}

setup_mount_cleanup() {
    cleanup_mounts() {
        local status=$?
        remove_install_sudoers /mnt
        copy_install_log_to_target
        if mountpoint -q /mnt; then
            umount -R /mnt || true
        fi
        exit "$status"
    }

    trap cleanup_mounts EXIT
}

final_unmount() {
    section "Unmounting target"
    copy_install_log_to_target
    run umount -R /mnt
    trap - EXIT
}
