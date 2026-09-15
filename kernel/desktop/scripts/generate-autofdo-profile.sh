#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=check-profile-kernel.sh
source "$(dirname "$0")/check-profile-kernel.sh"
trap '[[ -z ${profile_extract:-} ]] || rm -rf "$profile_extract"' EXIT
check_profile_kernel autofdo
cd /build
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o kernel.data sleep 1800
llvm-profgen --kernel --binary="$profile_binary" --perfdata=kernel.data -o /profiles/kernel.afdo.new
mv /profiles/kernel.afdo.new /profiles/kernel.afdo
sha256sum /profiles/kernel.afdo
