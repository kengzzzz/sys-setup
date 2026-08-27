#!/usr/bin/env bash
set -euo pipefail

mkdir -p /build/linux-cachyos
cp -a /src/. /build/linux-cachyos/
cd "/build/linux-cachyos/${KERNEL_SOURCE_SUBDIR:?set KERNEL_SOURCE_SUBDIR}"
chown -R builder:builder /out /build

su builder -c "
  set -euo pipefail
  updpkgsums
  makepkg -o --skippgpcheck
  patch --fuzz=0 src/cachyos-*/.config < /patches/config.patch
  makepkg -e -s --noconfirm --skippgpcheck
  cp -v *.pkg.tar.zst /out/
"
