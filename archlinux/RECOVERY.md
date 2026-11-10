# Btrfs recovery

Default: Btrfs with `compress=zstd:3,discard=async`. Periodic TRIM is disabled.
Snapper takes snapshots before and after package changes. limine-snapper-sync
adds the "before" and manual snapshots to the Limine menu, with the kernel and
initramfs each one needs.

A restore replaces `/` and its boot files. Home, logs, caches, container data,
and snapshot history stay unchanged.

## Snapshots

```sh
sudo snapper -c root list
```

For a manual snapshot:

```sh
sudo snapper -c root create --description 'Before manual changes' --cleanup-algorithm number
```

## Restore

1. In the Limine menu, open Arch Linux, then Snapshots, and pick a known working
   snapshot from before the update.
2. It boots read-only with a temporary writable layer in RAM. Changes made there
   are lost at reboot.
3. Check that it works, then run `sudo limine-snapper-restore` and pick the same
   snapshot.
4. Reboot.

The replaced root stays in the menu as a "backup" snapshot entry, so a restore
can be undone the same way.

Fix the failed update before upgrading again. Keep independent backups on
another disk or NAS. Local snapshots do not protect against disk failure.

## Limine does not start

Pick "UEFI OS" in the firmware boot menu. It is a copy of Limine at
`EFI/BOOT/BOOTX64.EFI`. If that fails too, boot an Arch ISO in UEFI mode and
run this, with your root and EFI partitions from `lsblk -f`:

```sh
mount -o subvol=@ /dev/nvme0n1p2 /mnt
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt limine-update
```

## Failed installation

The failure menu retries the step after a fix, skipping finished steps. Running
the installer again reuses the answers, YubiKeys and kernel saved in
`/root/sys-setup-state`. Log: `/tmp/sys-setup-arch-install.log`.

## Login screen

The Quickshell greeter only takes a YubiKey PIN. No attempt is used until the
key is plugged in.

If it breaks, it shows a "press Enter to try again" screen. Ctrl+Alt+Backspace
forces that screen. Ctrl+Alt+F2 opens a text login. Logs:
`journalctl -b -t qs-greeter`.

## Locked out

There are no passwords. If no enrolled YubiKey works, boot the ISO, mount the
root subvolume at `/mnt` and either add a key:

```sh
pacman -Sy pam-u2f
cred=$(pamu2fcfg -N -u keng -o pam://arch-pc -i pam://arch-pc | cut -d: -f2-)
sed -i "s|\$|:$cred|" /mnt/etc/Yubico/u2f_mappings
```

or run `arch-chroot /mnt passwd keng` and uncomment the `pam_unix.so` auth line
in `/mnt/etc/pam.d/system-auth`. The login screen only takes a YubiKey, so sign
in with the password on a text login (Ctrl+Alt+F2).
