# Recovery

Snapper takes a Btrfs snapshot before and after each package change. The "before"
snapshots appear in the Limine menu. A restore replaces `/` and its boot files and
keeps home, logs and caches.

## Snapshots

```sh
sudo snapper -c root list
sudo snapper -c root create --description 'Before manual changes' --cleanup-algorithm number
```

## Restore

1. In Limine, open Arch Linux, then Snapshots, and boot a working snapshot. It runs
   read-only, and changes are lost at reboot.
2. Run `sudo limine-snapper-restore` and pick the same snapshot.
3. Reboot.

The old root stays in the menu as a "backup" snapshot, so you can undo a restore.
Snapshots live on the same disk, so keep backups elsewhere.

## Limine does not start

Pick "UEFI OS" in the firmware boot menu. If that fails, boot an Arch ISO and run:

```sh
mount -o subvol=@ /dev/nvme0n1p2 /mnt
mount /dev/nvme0n1p1 /mnt/boot
arch-chroot /mnt limine-update
```

## Failed installation

The failure menu retries the step. Running the installer again reuses what
`/root/sys-setup-state` holds. The log is `/tmp/sys-setup-arch-install.log`.

## Login screen

The greeter only takes a YubiKey PIN. If it fails, press Enter to retry, or press
Ctrl+Alt+F2 for a text login. Logs: `journalctl -b -t deskshell-greeter`.

## Locked out

If no YubiKey works, boot the ISO, mount the root subvolume at `/mnt` and add a key:

```sh
pacman -Sy pam-u2f
cred=$(pamu2fcfg -N -u keng -o pam://arch-pc -i pam://arch-pc | cut -d: -f2-)
sed -i "s|\$|:$cred|" /mnt/etc/Yubico/u2f_mappings
```

Or run `arch-chroot /mnt passwd keng`, uncomment the `pam_unix.so` auth line in
`/mnt/etc/pam.d/system-auth`, and log in on the text login.
