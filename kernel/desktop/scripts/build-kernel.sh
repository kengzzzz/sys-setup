#!/usr/bin/env bash
set -euo pipefail

stage=${1:-}
case "$stage" in
    kernel|autofdo|propeller) ;;
    *) echo "Usage: $0 <kernel|autofdo|propeller> [--config-only]" >&2; exit 2 ;;
esac
config_only=no
if [[ $# == 2 && $2 == --config-only ]]; then
    config_only=yes
elif [[ $# != 1 ]]; then
    echo "Usage: $0 <kernel|autofdo|propeller> [--config-only]" >&2
    exit 2
fi

if (( EUID == 0 )); then
    test ! -e /build/linux-cachyos || { echo 'Expected fresh /build scratch space' >&2; exit 1; }
    mkdir -p /build/linux-cachyos "/out/$stage"
    cp -a /src/. /build/linux-cachyos/
    chown -R builder:builder /build
    chown builder:builder "/out/$stage"
    exec su -s /bin/bash builder -c 'exec bash /scripts/build-kernel.sh "$@"' -- "$0" "$@"
fi

cd "/build/linux-cachyos/${KERNEL_SOURCE_SUBDIR:?set KERNEL_SOURCE_SUBDIR}"
export PKGDEST=/build/packages
mkdir "$PKGDEST"
updpkgsums
makepkg -o --skippgpcheck
shopt -s nullglob
trees=(src/cachyos-*/)
if [[ ${#trees[@]} != 1 || ! -f ${trees[0]}/.config ]]; then
    echo "Stage $stage: expected exactly one prepared kernel tree; found ${#trees[@]}" >&2
    exit 1
fi
tree=$(realpath "${trees[0]}")
(
    cd "$tree"
    cp .config /build/baseline.config
    bash /scripts/configure-kernel.sh "$stage"
    cp .config /build/resolved.config
    make LLVM=1 LLVM_IAS=1 olddefconfig
    cmp .config /build/resolved.config
    make LLVM=1 LLVM_IAS=1 prepare
    cmp .config /build/resolved.config
)
exec 9>"/out/$stage/.publish.lock"
flock -n 9 || { echo "Another $stage invocation is publishing/building" >&2; exit 1; }
cp /build/resolved.config "/out/$stage/kernel.config"
if [[ $config_only == yes ]]; then
    echo "PASS: $stage configuration resolved and stable; /out/$stage/kernel.config"
    exit 0
fi
expected_output=$(makepkg --packagelist)
mapfile -t expected <<< "$expected_output"
for package in "${expected[@]}"; do
    destination="/out/$stage/${package##*/}"
    test ! -e "$destination" || { echo "Archive existing package before rebuilding: $destination" >&2; exit 1; }
done
makepkg -e -s --noconfirm --skippgpcheck
cmp "$tree/.config" /build/resolved.config
packages=("$PKGDEST"/*.pkg.tar.zst)
((${#packages[@]} > 0)) || { echo 'Build produced no packages' >&2; exit 1; }
for package in "${packages[@]}"; do
    destination="/out/$stage/${package##*/}"
    test ! -e "$destination" || { echo "Archive existing package before publication: $destination" >&2; exit 1; }
done
# Publish complete files without overwriting existing packages.
publication=$(mktemp -d "/out/$stage/.packages.XXXXXX")
trap 'rm -rf "$publication"' EXIT
for package in "${packages[@]}"; do
    cp "$package" "$publication/${package##*/}"
done
for package in "${packages[@]}"; do
    ln "$publication/${package##*/}" "/out/$stage/${package##*/}"
    printf 'Package: /out/%s/%s\n' "$stage" "${package##*/}"
done
