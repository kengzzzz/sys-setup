#!/usr/bin/env bash
# Variables come from the sourced PKGBUILD.
# shellcheck disable=SC2154
set -eo pipefail
# PKGBUILD expects unset variables to be allowed.
_die() { error "$@"; exit 1; }
error() { printf '%s\n' "$*" >&2; }
# shellcheck disable=SC1090
source "${1:?PKGBUILD path required}"
if [[ $_autofdo == yes && -n $_autofdo_profile_name ]]; then
    test -s "$_autofdo_profile_name" || { error "Missing required AutoFDO profile: $_autofdo_profile_name"; exit 1; }
fi
if [[ $_propeller == yes && $_propeller_profiles == yes ]]; then
    for profile in propeller_cc_profile.txt propeller_ld_profile.txt; do
        test -s "$profile" || { error "Missing required Propeller profile: $profile"; exit 1; }
    done
fi
