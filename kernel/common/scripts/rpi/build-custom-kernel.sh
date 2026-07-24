#!/usr/bin/env bash
set -euo pipefail

mkdir -p /build/linux-rpi /out/overlays
cp -a /src/. /build/linux-rpi/
cd /build/linux-rpi
chown -R builder:builder /out /build

su builder -c "
  set -eu
  make bcm2712_defconfig
  patch --fuzz=0 .config < /patches/config.patch
  make -j\$(nproc) Image.gz modules dtbs KCFLAGS='-mcpu=native'
  make -j\$(nproc) INSTALL_MOD_PATH=/out modules_install
  cp arch/arm64/boot/Image /out/kernel_2712.img
  cp arch/arm64/boot/dts/broadcom/*.dtb /out/
  cp arch/arm64/boot/dts/overlays/*.dtbo /out/overlays/
  cp arch/arm64/boot/dts/overlays/README /out/overlays/
"
