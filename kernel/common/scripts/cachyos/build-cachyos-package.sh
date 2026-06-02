#!/usr/bin/env bash
set -euo pipefail

output_subdir="${1:?usage: build-cachyos-package.sh <output-subdir>}"

mkdir -p /build/linux-cachyos "/out/${output_subdir}"
cp -a /src/. /build/linux-cachyos/
cd "/build/linux-cachyos/${KERNEL_SOURCE_SUBDIR:?set KERNEL_SOURCE_SUBDIR}"
chown -R builder:builder /build /out

su builder -c "
  updpkgsums
  makepkg -o --skippgpcheck
  cp /build/linux-cachyos/${KERNEL_SOURCE_SUBDIR}/config-*-profiler config
  updpkgsums
  makepkg -e -s --noconfirm --skippgpcheck
  cp -v *.pkg.tar.zst /out/${output_subdir}/
"
