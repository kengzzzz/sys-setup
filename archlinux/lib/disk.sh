#!/usr/bin/env bash

partition_suffix() {
    local disk=$1

    if [[ $disk == *nvme* || $disk == *mmcblk* || $disk == *loop* ]]; then
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
    retry mkfs.xfs -f -m crc=1,reflink=1,rmapbt=1 "$ROOT_PARTITION"
}

mount_target() {
    section "Mounting target"
    run mount -o noatime "$ROOT_PARTITION" /mnt
    run mount --mkdir -o defaults,noatime,umask=0077 "$EFI_PARTITION" /mnt/boot
    mkdir -p /mnt/etc /mnt/var/cache/pacman/pkg /mnt/var/log
    printf 'KEYMAP=%s\n' "$KEYMAP" >/mnt/etc/vconsole.conf
}

setup_mount_cleanup() {
    cleanup_mounts() {
        local status=$?
        copy_install_log_to_target
        if mountpoint -q /mnt/boot; then
            umount /mnt/boot || true
        fi
        if mountpoint -q /mnt; then
            umount /mnt || true
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
