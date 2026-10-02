#!/usr/bin/env bash
set -euo pipefail
umask 077

[[ $EUID == 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }
mountpoint -q /boot || { printf '/boot must be mounted before saving EFI files.\n' >&2; exit 1; }
[[ $(findmnt -n -o FSTYPE /) == btrfs ]] || { printf 'Root must use Btrfs.\n' >&2; exit 1; }
[[ $(findmnt -n -o FSTYPE /boot) == vfat ]] || { printf '/boot must be the FAT EFI partition.\n' >&2; exit 1; }

mkdir -p /.bootbackup
# FAT timestamps are coarse; changed files can retain both size and timestamp.
rsync -rtc --delete -- /boot/ /.bootbackup/
