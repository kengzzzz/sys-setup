#!/usr/bin/env bash
set -euo pipefail
umask 077

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [[ ${1:-} == --help || $# != 3 ]]; then
    printf 'Usage: %s ROOT_PARTITION EFI_PARTITION SNAPSHOT_NUMBER\n' "${0##*/}"
    printf 'Run from a live Arch ISO with both target partitions unmounted.\n'
    [[ ${1:-} == --help ]] && exit 0
    exit 1
fi
[[ $EUID == 0 ]] || die "run as root from a live Arch ISO"
root_device=$(readlink -f -- "$1")
efi_device=$(readlink -f -- "$2")
number=$3
[[ $number =~ ^[1-9][0-9]*$ ]] || die "snapshot number must be a positive integer"
[[ -b $root_device && -b $efi_device ]] || die "root and EFI partitions must be block devices"
[[ $(blkid -s TYPE -o value "$root_device") == btrfs ]] || die "root partition must use Btrfs"
[[ $(blkid -s TYPE -o value "$efi_device") == vfat ]] || die "EFI partition must use FAT"
for device in "$root_device" "$efi_device"; do
    if lsblk -nr -o MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
        die "unmount the target partition before recovery: $device"
    fi
done

recovery_dir=$(mktemp -d /tmp/sys-setup-rollback.XXXXXX)
top="$recovery_dir/top"
efi="$recovery_dir/efi"
mkdir "$top" "$efi"
cleanup() {
    local status=$?
    umount "$efi" 2>/dev/null || true
    umount "$top" 2>/dev/null || true
    rmdir "$efi" "$top" "$recovery_dir" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT
mount -o subvolid=5,noatime,compress=zstd:3,discard=async "$root_device" "$top"
snapshot="$top/@snapshots/$number/snapshot"
[[ -d $top/@ && -f $snapshot/etc/fstab ]] || die "root or snapshot $number is missing"
btrfs subvolume show "$snapshot" >/dev/null || die "snapshot path is not a Btrfs subvolume"

root_source=$(awk '$2 == "/" {print $1; exit}' "$snapshot/etc/fstab")
efi_source=$(awk '$2 == "/boot" {print $1; exit}' "$snapshot/etc/fstab")
[[ $root_source == "UUID=$(blkid -s UUID -o value "$root_device")" ]] || die "snapshot does not match the root partition"
[[ $efi_source == "UUID=$(blkid -s UUID -o value "$efi_device")" ]] || die "snapshot does not match the EFI partition"
[[ -s $snapshot/.bootbackup/loader/loader.conf ]] || die "snapshot has no saved boot configuration"
shopt -s nullglob
entries=("$snapshot/.bootbackup/loader/entries/"*.conf)
((${#entries[@]})) || die "snapshot has no saved boot entries"
for entry in "${entries[@]}"; do
    while read -r kind path _; do
        if [[ $kind == linux || $kind == initrd ]]; then
            [[ $path == /* && $path != *..* && -s $snapshot/.bootbackup$path ]] \
                || die "boot artifact missing from snapshot: $path"
        fi
    done <"$entry"
done

stamp=$(date -u +%Y%m%dT%H%M%S%N)
saved="@before-rollback-$stamp"
candidate="@restored-$stamp"
mount -o noatime,umask=0077 "$efi_device" "$efi"
mkdir "$top/@/.boot-before-rollback-$stamp"
rsync -rtc --delete -- "$efi/" "$top/@/.boot-before-rollback-$stamp/"
btrfs subvolume snapshot "$snapshot" "$top/$candidate"
# Pacman snapshots are taken while its transaction lock exists.
rm -f "$top/$candidate/var/lib/pacman/db.lck"

if ! rsync -rtc --delete -- "$top/$candidate/.bootbackup/" "$efi/"; then
    rsync -rtc --delete -- "$top/@/.boot-before-rollback-$stamp/" "$efi/" || true
    die "EFI restore failed; the old root and saved EFI files were preserved"
fi
if ! mv "$top/@" "$top/$saved"; then
    rsync -rtc --delete -- "$top/@/.boot-before-rollback-$stamp/" "$efi/" || true
    die "could not preserve the old root; it remains at @"
fi
if ! mv "$top/$candidate" "$top/@"; then
    mv "$top/$saved" "$top/@"
    rsync -rtc --delete -- "$top/@/.boot-before-rollback-$stamp/" "$efi/" || true
    die "root switch failed; the old root was restored"
fi
sync
printf 'Restored root snapshot %s and its matching EFI boot files.\n' "$number"
printf 'Previous root preserved as %s; /home and other data subvolumes were kept.\n' "$saved"
printf 'Unmounted recovery filesystems on exit. Reboot when ready.\n'
