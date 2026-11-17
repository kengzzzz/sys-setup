# Raspberry Pi kernel

## Config

The Compose services run as `linux/arm64`, so the x86_64 host needs AArch64 binfmt.
On Arch, install `qemu-user-static` and `qemu-user-static-binfmt`, and check that
`/proc/sys/fs/binfmt_misc/qemu-aarch64` exists. Then run:

```sh
docker compose run --rm kernel-config
```

## Build

```sh
docker compose run --rm kernel-builder
```

## Install

```sh
sudo mkdir -p /boot/firmware/custom
sudo cp -r ./out/lib/modules/* /lib/modules/
rm -rf ./out/lib
sudo cp -r ./out/* /boot/firmware/custom/
sudo cp /boot/firmware/cmdline.txt /boot/firmware/custom/
```

Add these lines to `/boot/firmware/config.txt`:

```
os_prefix=custom/
kernel=kernel_2712.img
```
