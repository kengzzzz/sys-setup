#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/scratch" "$test_root/archive/usr/src/debug/linux-profiler"

reject() {
    local stage=$1 expected=$2
    if bash -c 'source "$1"; check_profile_kernel "$2" "$3" "$4"' -- \
        "$root/scripts/check-profile-kernel.sh" "$stage" "$test_root/out" \
        "$test_root/scratch" > "$test_root/result" 2>&1; then
        echo "FAIL: $stage accepted $expected" >&2
        exit 1
    fi
    grep -Fq "$expected" "$test_root/result" || { cat "$test_root/result"; exit 1; }
}

for stage in autofdo propeller; do
    mkdir -p "$test_root/out/$stage"
    reject "$stage" 'found 0'
    touch "$test_root/out/$stage/linux-profiler-dbg-1-1-x86_64.pkg.tar.zst" \
        "$test_root/out/$stage/linux-profiler-dbg-2-1-x86_64.pkg.tar.zst"
    reject "$stage" 'found 2'
    rm "$test_root/out/$stage/"*.pkg.tar.zst

    printf '\nLinux version deliberately-wrong (test)\n' > "$test_root/archive/usr/src/debug/linux-profiler/vmlinux"
    tar --zstd -cf "$test_root/out/$stage/linux-profiler-dbg-1-1-x86_64.pkg.tar.zst" \
        -C "$test_root/archive" usr/src/debug/linux-profiler/vmlinux
    reject "$stage" 'does not match booted'

    # Match the release but deliberately use a different ELF build ID.
    cp /bin/ls "$test_root/archive/usr/src/debug/linux-profiler/vmlinux"
    printf '\nLinux version %s (test)\n' "$(uname -r)" >> "$test_root/archive/usr/src/debug/linux-profiler/vmlinux"
    tar --zstd -cf "$test_root/out/$stage/linux-profiler-dbg-1-1-x86_64.pkg.tar.zst" \
        -C "$test_root/archive" usr/src/debug/linux-profiler/vmlinux
    reject "$stage" 'build identity mismatch or unavailable'
done
printf 'PASS: both profiling stages reject missing, ambiguous, wrong-release and wrong-build artifacts\n'
