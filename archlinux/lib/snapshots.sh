#!/usr/bin/env bash

configure_btrfs_snapshots() {
    [[ $ROOT_FS == btrfs ]] || return 0
    section "Configuring Btrfs recovery"

    if [[ ! -f /etc/snapper/configs/root ]]; then
        # Snapper creates its own .snapshots subvolume. Replace that with the
        # separately mounted @snapshots so root restores keep the snapshot list.
        umount /.snapshots
        rmdir /.snapshots
        snapper --no-dbus -c root create-config /
        btrfs subvolume delete /.snapshots
        mkdir /.snapshots
        mount /.snapshots
    fi
    chmod 700 /.snapshots
    snapper --no-dbus -c root set-config \
        'TIMELINE_CREATE=no' 'TIMELINE_CLEANUP=no' \
        'NUMBER_CLEANUP=yes' 'NUMBER_LIMIT=20' 'NUMBER_LIMIT_IMPORTANT=10' \
        'EMPTY_PRE_POST_CLEANUP=yes'

    systemctl enable limine-snapper-sync.service
}

create_initial_snapshot() {
    [[ $ROOT_FS == btrfs ]] || return 0
    section "Taking the initial system snapshot"
    # A plain chroot leaves the final resolv.conf symlink intact; arch-chroot
    # would temporarily bind-mount the live resolver again.
    mountpoint -q /mnt/proc || run mount -t proc proc /mnt/proc
    run chroot /mnt snapper --no-dbus -c root create \
        --description 'Fresh installation' --cleanup-algorithm number --userdata important=yes
    run umount /mnt/proc
}
