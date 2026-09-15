#!/usr/bin/env bash
set -euo pipefail

check_profile_kernel() {
    local stage=$1 output_root=${2:-/out} scratch=${3:-/build}
    local packages binary_release binary_id boot_id
    shopt -s nullglob
    packages=("$output_root/$stage"/linux-profiler-dbg-[0-9]*.pkg.tar.zst)
    shopt -u nullglob
    if [[ ${#packages[@]} != 1 ]]; then
        echo "Stage $stage: expected exactly one linux-profiler debug package in $output_root/$stage; found ${#packages[@]}. Archive older versions explicitly." >&2
        return 1
    fi
    profile_extract=$(mktemp -d "$scratch/profile-debug.XXXXXX")
    profile_binary="$profile_extract/vmlinux"
    tar --use-compress-program=zstd -xOf "${packages[0]}" usr/src/debug/linux-profiler/vmlinux > "$profile_binary"
    binary_release=$(strings "$profile_binary" | sed -n 's/^Linux version \([^ ]*\) .*/\1/p' | sort -u)
    if [[ $binary_release != "$(uname -r)" ]]; then
        echo "Stage $stage: debug kernel release '$binary_release' does not match booted '$(uname -r)'" >&2
        return 1
    fi
    binary_id=$(readelf -n "$profile_binary" | sed -n 's/.*Build ID: //p' | sort -u)
    # /sys/kernel/notes is raw, aligned ELF notes in x86-64 byte order.
    boot_id=$(python - <<'PY'
import struct
from pathlib import Path
notes = Path('/sys/kernel/notes').read_bytes()
offset = 0
ids = set()
while offset + 12 <= len(notes):
    namesz, descsz, kind = struct.unpack_from('<III', notes, offset)
    offset += 12
    name = notes[offset:offset + namesz].rstrip(b'\0')
    offset += (namesz + 3) & ~3
    desc = notes[offset:offset + descsz]
    offset += (descsz + 3) & ~3
    if name == b'GNU' and kind == 3:
        ids.add(desc.hex())
print('\n'.join(sorted(ids)))
PY
    )
    if [[ -z $binary_id || -z $boot_id || $binary_id != "$boot_id" ]]; then
        echo "Stage $stage: build identity mismatch or unavailable (debug '$binary_id', booted '$boot_id')" >&2
        return 1
    fi
    printf 'Verified %s: release %s, build ID %s\n' "${packages[0]}" "$binary_release" "$binary_id"
}
