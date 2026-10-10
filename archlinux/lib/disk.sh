#!/usr/bin/env bash

partition_suffix() {
    local disk=$1

    if [[ $disk =~ [0-9]$ ]]; then
        printf 'p'
    fi
}

derive_partitions() {
    local suffix
    suffix=$(partition_suffix "$TARGET_DISK")
    EFI_PARTITION="${TARGET_DISK}${suffix}1"
    ROOT_PARTITION="${TARGET_DISK}${suffix}2"
}

confirm_destructive_install() {
    section "Destructive confirmation"
    printf 'All data on %s will be erased.\n' "$TARGET_DISK"
    confirm_exact "ERASE $TARGET_DISK" "Type 'ERASE $TARGET_DISK' to continue:" || die "aborted"
}

prepare_live_environment() {
    section "Preparing live environment"
    run mount -o remount,size=20G /run/archiso/cowspace || warn "could not resize archiso cowspace"
}

validate_target_disk() {
    TARGET_DISK=$(readlink -f -- "$TARGET_DISK")
    local disk_type
    disk_type=$(lsblk -dn -o TYPE "$TARGET_DISK")
    [[ $disk_type == disk || $disk_type == loop ]] || die "target must be a whole disk: $TARGET_DISK"
    if [[ ${DRY_RUN:-0} != 1 ]]; then
        if lsblk -nr -o MOUNTPOINTS "$TARGET_DISK" | grep -q '[^[:space:]]'; then
            die "target disk or a child device is mounted/in use: $TARGET_DISK"
        fi
        if mountpoint -q /mnt || mountpoint -q /mnt/boot; then
            die "unmount the existing installation target at /mnt before continuing"
        fi
    fi
    sgdisk --pretend --clear -n "1:0:+${EFI_SIZE}" -t 1:ef00 \
        -n 2:0:0 -t 2:8304 "$TARGET_DISK" >/dev/null \
        || die "partition layout does not fit $TARGET_DISK"
}

partition_disk() {
    section "Partitioning $TARGET_DISK"
    derive_partitions
    run wipefs -a "$TARGET_DISK"
    run sgdisk --zap-all "$TARGET_DISK"
    run sgdisk -n "1:0:+${EFI_SIZE}" -t 1:ef00 -c 1:"EFI System Partition" "$TARGET_DISK"
    run sgdisk -n 2:0:0 -t 2:8304 -c 2:"Linux Root" "$TARGET_DISK"
    run partprobe "$TARGET_DISK"
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
