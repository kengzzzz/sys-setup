#!/usr/bin/env bash
set -euo pipefail

mkdir -p /build/linux-rpi
cp -a /src/. /build/linux-rpi/
cd /build/linux-rpi
chown -R builder:builder /patches /build

su builder -c "
  make bcm2712_defconfig
  cp .config /tmp/.config.base
  make menuconfig
  diff -u /tmp/.config.base .config > /patches/config.patch
"
