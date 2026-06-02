#!/usr/bin/env bash
set -euo pipefail

mkdir -p /build/linux-cachyos
cp -a /src/. /build/linux-cachyos/
cd "/build/linux-cachyos/${KERNEL_SOURCE_SUBDIR:?set KERNEL_SOURCE_SUBDIR}"
chown -R builder:builder /patches /build

su builder -c "
  updpkgsums
  makepkg -o --skippgpcheck
  cd /build/linux-cachyos/${KERNEL_SOURCE_SUBDIR}/src/cachyos-*/
  cp /build/linux-cachyos/${KERNEL_SOURCE_SUBDIR}/${KERNEL_CONFIG_GLOB:?set KERNEL_CONFIG_GLOB} .config
  LLVM=1 LLVM_IAS=1 make menuconfig
  diff -u --label .config --label .config /build/linux-cachyos/${KERNEL_SOURCE_SUBDIR}/${KERNEL_CONFIG_GLOB} .config > config.patch
  cp config.patch /patches/
"
