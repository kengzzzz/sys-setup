#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=check-profile-kernel.sh
source "$(dirname "$0")/check-profile-kernel.sh"
trap '[[ -z ${profile_extract:-} ]] || rm -rf "$profile_extract"' EXIT
check_profile_kernel propeller
cd /build
perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o kernel.data sleep 1800
generate_propeller_profiles --binary="$profile_binary" --profile=kernel.data --cc_profile=/profiles/propeller_cc_profile.txt.new --ld_profile=/profiles/propeller_ld_profile.txt.new
mv /profiles/propeller_cc_profile.txt.new /profiles/propeller_cc_profile.txt
mv /profiles/propeller_ld_profile.txt.new /profiles/propeller_ld_profile.txt
sha256sum /profiles/propeller_{cc,ld}_profile.txt
