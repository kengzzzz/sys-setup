#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=../lib/disk.sh
source "$ROOT_DIR/lib/disk.sh"
# shellcheck source=../lib/network.sh
source "$ROOT_DIR/lib/network.sh"
# shellcheck source=../lib/auth.sh
source "$ROOT_DIR/lib/auth.sh"
# shellcheck source=../lib/boot.sh
source "$ROOT_DIR/lib/boot.sh"
# shellcheck source=../../lib/common.sh
source "$ROOT_DIR/../lib/common.sh"
# shellcheck source=../lib/packages.sh
source "$ROOT_DIR/lib/packages.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local label=$3

    if [[ $expected != "$actual" ]]; then
        printf 'FAIL: %s: expected %q, got %q\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_eq "" "$(partition_suffix /dev/sda)" "sata partition suffix"
assert_eq "p" "$(partition_suffix /dev/nvme0n1)" "nvme partition suffix"
assert_eq "p" "$(partition_suffix /dev/mmcblk0)" "mmc partition suffix"
assert_eq "p" "$(partition_suffix /dev/loop0)" "loop partition suffix"

if confirm_yes_no "Reboot now?" "N" <<<""; then
    printf 'FAIL: reboot prompt should default to no\n' >&2
    exit 1
fi

expected_network='[Match]
Name=enp14s0

[Network]
Address=192.168.0.10/24
Gateway=192.168.0.1
DNS=192.168.0.3
LinkLocalAddressing=ipv6

[Link]
RequiredForOnline=yes'
assert_eq "$expected_network" "$(render_static_network enp14s0 192.168.0.10/24 192.168.0.1 192.168.0.3)" "static network rendering"

expected_boot='title Arch Linux (linux-bore-flto-pgo)
linux /vmlinuz-linux-bore-flto-pgo
initrd /initramfs-linux-bore-flto-pgo.img
options root=PARTUUID=abc-123 rw nvidia-drm.modeset=1 nvidia-drm.fbdev=1'
assert_eq "$expected_boot" "$(render_boot_entry linux-bore-flto-pgo linux-bore-flto-pgo abc-123)" "boot entry rendering"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cat >"$tmpdir/system-auth" <<'EOF'
auth       required                    pam_faillock.so      preauth
-auth      [success=2 default=ignore]  pam_systemd_home.so
-auth      [success=1 default=bad]     pam_unix.so          try_first_pass nullok
account    required                    pam_unix.so
EOF
patch_system_auth_file "$tmpdir/system-auth"
grep -q 'pam_u2f.so           authfile=/etc/Yubico/u2f_mappings cue pin=1' "$tmpdir/system-auth" || {
    printf 'FAIL: system-auth missing pam_u2f line\n' >&2
    exit 1
}
grep -q '^# -auth      \[success=1 default=bad\]     pam_unix.so' "$tmpdir/system-auth" || {
    printf 'FAIL: system-auth pam_unix auth was not commented\n' >&2
    exit 1
}

if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'networkmanager'; then
    printf 'FAIL: NetworkManager should not be in official package list\n' >&2
    exit 1
fi
if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'nvidia-open-dkms'; then
    printf 'FAIL: nvidia-open-dkms should not be in official package list\n' >&2
    exit 1
fi

if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'helium-browser-bin'; then
    printf 'FAIL: helium-browser-bin should be in official package list\n' >&2
    exit 1
fi
if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'firefox'; then
    printf 'FAIL: firefox should not be in official package list\n' >&2
    exit 1
fi

PRIMARY_KERNEL=linux-bore-flto-pgo
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/packages"
mkdir -p "$CUSTOM_KERNEL_PACKAGES_DIR"
touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-1-1-x86_64.pkg.tar.zst"
validate_custom_kernel_packages
assert_eq "1" "${#CUSTOM_KERNEL_PACKAGES[@]}" "custom kernel package validation"

printf 'archlinux installer tests passed\n'
