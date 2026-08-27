#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${KERNEL_SOURCE_SHA256:-}" ]]; then
  echo "KERNEL_SOURCE_SHA256 is unset; skipping explicit kernel source verification"
  exit 0
fi

source_archive="cachyos-${KERNEL_VERSION:?set KERNEL_VERSION}-${KERNEL_TAGREL:?set KERNEL_TAGREL}.tar.gz"
expected_sha256="${KERNEL_SOURCE_SHA256}"

printf '%s  %s\n' "${expected_sha256}" "${source_archive}" | sha256sum --check --strict -
