#!/usr/bin/env bash
set -euo pipefail

mkdir -p /build/linux-cachyos
cp -a /src/. /build/linux-cachyos/
cd "/build/linux-cachyos/${KERNEL_SOURCE_SUBDIR:?set KERNEL_SOURCE_SUBDIR}"
chown -R builder:builder /out /build

su builder -c "
  updpkgsums
  makepkg -o --skippgpcheck
  mv ${KERNEL_CONFIG_GLOB:?set KERNEL_CONFIG_GLOB} config
  patch config < /patches/config.patch
  updpkgsums
  makepkg -e -s --noconfirm --skippgpcheck
  cp -v *.pkg.tar.zst /out/
"
