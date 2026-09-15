#!/usr/bin/env bash
set -euo pipefail

stage=${1:-}
case "$stage" in
    kernel|autofdo|propeller) ;;
    *) echo "Usage: $0 <kernel|autofdo|propeller>" >&2; exit 2 ;;
esac
[[ $# == 1 ]] || exit 2

expect() {
    local symbol=$1 expected=$2 actual
    actual=$(scripts/config --state "$symbol")
    if [[ $actual != "$expected" ]]; then
        printf 'Stage %s: CONFIG_%s expected %q, actual %q\n' "$stage" "$symbol" "$expected" "$actual" >&2
        exit 1
    fi
}

test -f .config
test -x scripts/config
export LLVM=1 LLVM_IAS=1

make olddefconfig
before=$(mktemp)
trap 'rm -f "$before"' EXIT
cp .config "$before"

# Keep AMDGPU: it selects DRM_DISPLAY_HDCP_HELPER for nvidia-drm 615.71.09.
disable=(
    X86_INTEL_LPSS X86_MCE_INTEL PERF_EVENTS_INTEL_UNCORE
    PERF_EVENTS_INTEL_CSTATE X86_SGX KVM_INTEL EFI_HANDOVER_PROTOCOL
    AGP VGA_SWITCHEROO DRM_AST DRM_GMA500 DRM_GUD DRM_I915
    DRM_MGAG200 DRM_NOUVEAU DRM_RADEON DRM_XE
)
for symbol in "${disable[@]}" IOSF_MBI DEFAULT_HOSTNAME; do
    if [[ $(scripts/config --state "$symbol") == undef ]]; then
        echo "Stage $stage: CONFIG_$symbol expected present for modification, actual undef; review Kconfig." >&2
        exit 1
    fi
done
for symbol in "${disable[@]}"; do
    scripts/config --disable "$symbol"
done
scripts/config --module IOSF_MBI --set-str DEFAULT_HOSTNAME ""

make olddefconfig
for symbol in "${disable[@]}"; do
    expect "$symbol" n
done
expect IOSF_MBI m
expect DEFAULT_HOSTNAME ''

keep=(DRM DRM_KMS_HELPER DRM_SIMPLEDRM DRM_TTM DRM_TTM_HELPER
      DRM_DISPLAY_HELPER DRM_DISPLAY_HDCP_HELPER
      KVM_AMD SND_HDA_INTEL SND_USB_AUDIO
      R8169 NVME_CORE USB_XHCI_HCD USB4 XFS_FS)
for symbol in "${keep[@]}"; do
    previous=$(scripts/config --file "$before" --state "$symbol")
    current=$(scripts/config --state "$symbol")
    if [[ $previous != y && $previous != m ]] || [[ $current != "$previous" ]]; then
        echo "Stage $stage: CONFIG_$symbol expected enabled and unchanged ($previous), actual $current." >&2
        exit 1
    fi
done

# Update these expectations together with the stage patches.
expect SCHED_BORE y
expect LTO_NONE n
expect AUTOFDO_CLANG y
case "$stage" in
    kernel|autofdo)
        expect LTO_CLANG_FULL y
        expect LTO_CLANG_THIN n
        expect PROPELLER_CLANG n
        ;;
    propeller)
        expect LTO_CLANG_FULL n
        expect LTO_CLANG_THIN y
        expect PROPELLER_CLANG y
        ;;
esac
expect LTO_CLANG_THIN_DIST n
if [[ $stage != kernel ]]; then
    expect DEBUG_INFO y
    expect DEBUG_INFO_NONE n
fi

scripts/diffconfig "$before" .config
