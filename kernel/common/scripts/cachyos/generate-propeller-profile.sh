#!/usr/bin/env bash
set -euo pipefail

cd /build
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o kernel.data sleep 1800
mkdir -p extract_dbg
tar --use-compress-program=zstd -xvf /out/propeller/linux-profiler-dbg-*.pkg.tar.zst -C extract_dbg
generate_propeller_profiles --binary=extract_dbg/usr/src/debug/linux-profiler/vmlinux --profile=kernel.data --cc_profile=/profiles/propeller_cc_profile.txt --ld_profile=/profiles/propeller_ld_profile.txt
