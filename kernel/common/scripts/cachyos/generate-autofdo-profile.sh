#!/usr/bin/env bash
set -euo pipefail

cd /build
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o kernel.data sleep 1800
mkdir -p extract_dbg
tar --use-compress-program=zstd -xvf /out/autofdo/linux-profiler-dbg-*.pkg.tar.zst -C extract_dbg
llvm-profgen --kernel --binary=extract_dbg/usr/src/debug/linux-profiler/vmlinux --perfdata=kernel.data -o /profiles/kernel.afdo
