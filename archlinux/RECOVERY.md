# Btrfs recovery

Default: Btrfs with `compress=zstd:3,discard=async`; periodic TRIM is disabled.
Snapper takes snapshots before and after package changes, including matching
EFI files saved in `/.bootbackup`.

Rollback restores `/` and `/boot`. Home, logs, caches, container data, and
snapshot history stay unchanged.

## Snapshots

```sh
sudo snapper -c root list
```

For a manual snapshot, with no package transaction running:

```sh
sudo sys-setup-boot-backup &&
sudo snapper -c root create --description 'Before manual changes' --cleanup-algorithm number
```

## Restore

Boot an Arch ISO in UEFI mode. Run as root with `btrfs-progs`, `rsync`, and a
checkout of this repository available. Replace device paths and `NUMBER` with
your root partition, EFI partition, and a known working pre-update snapshot.

Inspect snapshots:

```sh
lsblk -f
mount -o ro,subvol=@snapshots /dev/nvme0n1p2 /mnt
ls /mnt
cat /mnt/NUMBER/info.xml
umount /mnt
```

With both target partitions unmounted, run from the repository directory:

```sh
bash archlinux/scripts/rollback.sh /dev/nvme0n1p2 /dev/nvme0n1p1 NUMBER
```

Reboot after successful recovery. The previous root remains at
`@before-rollback-TIMESTAMP`, with its EFI files in `.boot-before-rollback-TIMESTAMP`.
Remove these preserved roots manually after confirming recovery; Snapper cleanup
does not manage them.

Fix the failed update before upgrading again. Keep independent backups on
another disk or NAS; local snapshots do not protect against disk failure.
