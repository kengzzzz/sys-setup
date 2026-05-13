# Create Config

- `docker compose run --rm kernel-config`

# Compile Kernel

- `docker compose run --rm kernel-builder`

# Installation

- `sudo mkdir -p /boot/firmware/custom`
- `sudo cp -r ./out/lib/modules/* /lib/modules/`
- `rm -rf ./out/lib`
- `sudo cp -r ./out/* /boot/firmware/custom/`

# Config Bootloader

- update `/boot/firmware/config.txt`. Add
```
os_prefix=custom/
kernel=kernel_2712.img
```
- `sudo cp /boot/firmware/cmdline.txt /boot/firmware/custom/`
