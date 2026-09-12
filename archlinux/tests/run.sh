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
# shellcheck source=../lib/dotfiles.sh
source "$ROOT_DIR/lib/dotfiles.sh"
# shellcheck source=../lib/services.sh
source "$ROOT_DIR/lib/services.sh"

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

expected_network='[connection]
id=static-enp14s0
type=ethernet
interface-name=enp14s0
autoconnect=true

[ipv4]
method=manual
address1=192.168.0.10/24,192.168.0.1
dns=192.168.0.3;

[ipv6]
method=link-local'
assert_eq "$expected_network" "$(render_static_network enp14s0 192.168.0.10/24 192.168.0.1 192.168.0.3)" "static network rendering"

expected_boot='title Arch Linux (linux-bore-flto-pgo)
linux /vmlinuz-linux-bore-flto-pgo
initrd /initramfs-linux-bore-flto-pgo.img
options root=PARTUUID=abc-123 rw nvidia-drm.modeset=1 nvidia-drm.fbdev=1'
assert_eq "$expected_boot" "$(render_boot_entry linux-bore-flto-pgo linux-bore-flto-pgo abc-123)" "boot entry rendering"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
NETWORK_INTERFACE=enp14s0
NETWORK_ADDRESS=192.168.0.10/24
NETWORK_GATEWAY=192.168.0.1
NETWORK_DNS=192.168.0.3
configure_static_network "$tmpdir/static-enp14s0.nmconnection" "$tmpdir/resolv.conf" >/dev/null
assert_eq "600" "$(stat -c %a "$tmpdir/static-enp14s0.nmconnection")" "NetworkManager keyfile mode"
assert_eq "/run/systemd/resolve/resolv.conf" "$(readlink "$tmpdir/resolv.conf")" "resolved resolv.conf link"

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

for pkg in networkmanager quickshell hypridle uwsm brave-origin-bin lact fzf pkgfile \
    ripgrep fwupd yubikey-manager wlr-randr pipewire-jack openai-codex zenity; do
    if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: %s should be in official package list\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in systemd-networkd waybar swaync rofi swayidle helium-browser-bin kolourpaint sbctl sbsigntools python-pywal vesktop; do
    if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: stale package %s should not be in official package list\n' "$pkg" >&2
        exit 1
    fi
done
if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'nvidia-open-dkms'; then
    printf 'FAIL: nvidia-open-dkms should not be in official package list\n' >&2
    exit 1
fi

assert_eq "brave-origin.desktop" "$DEFAULT_BROWSER_DESKTOP" "default browser desktop file"
if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'firefox'; then
    printf 'FAIL: firefox should not be in official package list\n' >&2
    exit 1
fi

if printf '%s\n' "${BASE_PACKAGES[@]}" | grep -qx 'base-devel'; then
    printf 'FAIL: base-devel should not be in base package list (no host toolchain)\n' >&2
    exit 1
fi
for pkg in fakeroot binutils sudo; do
    if ! printf '%s\n' "${BASE_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: %s must stay in base package list; makepkg breaks without it\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in cmake gcc clang rust; do
    if printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: %s should not be in official package list (no host toolchain)\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in nvidia-container-toolkit qemu-user-static qemu-user-static-binfmt; do
    if ! printf '%s\n' "${WORKLOAD_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: %s should be in workload package list\n' "$pkg" >&2
        exit 1
    fi
done
if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx 'paru'; then
    printf 'FAIL: paru must come prebuilt from the repo, not be built from AUR\n' >&2
    exit 1
fi

PRIMARY_KERNEL=linux-bore-flto-pgo
mkdir -p "$tmpdir/kernel-only" "$tmpdir/nvidia-only" "$tmpdir/packages"
touch "$tmpdir/kernel-only/linux-bore-flto-pgo-1-1-x86_64.pkg.tar.zst"
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/kernel-only"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a missing NVIDIA package\n' >&2
    exit 1
fi
touch "$tmpdir/nvidia-only/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst"
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/nvidia-only"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a missing kernel package\n' >&2
    exit 1
fi

CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/packages"
touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-1-1-x86_64.pkg.tar.zst" \
    "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-headers-1-1-x86_64.pkg.tar.zst" \
    "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-dbg-1-1-x86_64.pkg.tar.zst" \
    "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst"
validate_custom_kernel_packages
assert_eq "2" "${#CUSTOM_KERNEL_PACKAGES[@]}" "kernel package glob excludes headers and dbg"
if printf '%s\n' "${CUSTOM_KERNEL_PACKAGES[@]}" | grep -q -- '-headers-\|-dbg-'; then
    printf 'FAIL: kernel package glob picked up -headers or -dbg\n' >&2
    exit 1
fi

for package in docs swayidle xsettingsd etc usr utils; do
    if printf '%s\n' "${ARCH_STOW_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should not be in the Arch Stow allowlist\n' "$package" >&2
        exit 1
    fi
done
for package in hypr quickshell uwsm zshrc; do
    if ! printf '%s\n' "${ARCH_STOW_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should be in the Arch Stow allowlist\n' "$package" >&2
        exit 1
    fi
done

mkdir -p "$tmpdir/user-units" "$tmpdir/home"
touch "$tmpdir/user-units/ssh-agent.socket" "$tmpdir/user-units/hypr-kblayoutd.service"
link_user_unit "$tmpdir/home" ssh-agent.socket sockets.target "$tmpdir/user-units"
link_user_unit "$tmpdir/home" hypr-kblayoutd.service graphical-session.target "$tmpdir/user-units"
assert_eq "$tmpdir/user-units/ssh-agent.socket" \
    "$(readlink "$tmpdir/home/.config/systemd/user/sockets.target.wants/ssh-agent.socket")" \
    "ssh-agent socket enablement"
assert_eq "$tmpdir/user-units/hypr-kblayoutd.service" \
    "$(readlink "$tmpdir/home/.config/systemd/user/graphical-session.target.wants/hypr-kblayoutd.service")" \
    "keyboard layout service enablement"
if printf '%s\n' "${SYSTEM_SERVICES[@]}" | grep -qx 'systemd-networkd.service'; then
    printf 'FAIL: systemd-networkd should not be enabled\n' >&2
    exit 1
fi
for service in NetworkManager.service systemd-resolved.service lactd.service; do
    if ! printf '%s\n' "${SYSTEM_SERVICES[@]}" | grep -qx "$service"; then
        printf 'FAIL: %s should be enabled\n' "$service" >&2
        exit 1
    fi
done

mkdir -p "$tmpdir/efivars"
printf '\0\0\0\0\1' >"$tmpdir/efivars/SecureBoot-test"
secure_boot_enabled "$tmpdir/efivars" || {
    printf 'FAIL: enabled Secure Boot state was not detected\n' >&2
    exit 1
}
printf '\0\0\0\0\0' >"$tmpdir/efivars/SecureBoot-test"
if secure_boot_enabled "$tmpdir/efivars"; then
    printf 'FAIL: disabled Secure Boot state was reported as enabled\n' >&2
    exit 1
fi

expected_loader='default default.conf
timeout 3
console-mode max
editor no'
assert_eq "$expected_loader" "$(render_loader_config default.conf)" "loader config rendering"

mkdir -p "$tmpdir/sysfs/0000:01:00.0"
printf '0x10de\n' >"$tmpdir/sysfs/0000:01:00.0/vendor"
printf '0x2705\n' >"$tmpdir/sysfs/0000:01:00.0/device"
printf '0x1771\n' >"$tmpdir/sysfs/0000:01:00.0/subsystem_vendor"
printf '0x10de\n' >"$tmpdir/sysfs/0000:01:00.0/subsystem_device"
cat >"$tmpdir/lact.yaml" <<'EOF'
version: 7
gpus:
  10DE:2705-1771:10DE-0000:01:00.0:
    fan_control_enabled: false
EOF
validate_lact_hardware "$tmpdir/lact.yaml" "$tmpdir/sysfs"
printf '0xffff\n' >"$tmpdir/sysfs/0000:01:00.0/device"
if (validate_lact_hardware "$tmpdir/lact.yaml" "$tmpdir/sysfs") >/dev/null 2>&1; then
    printf 'FAIL: LACT hardware validation accepted a mismatched GPU\n' >&2
    exit 1
fi

printf 'archlinux installer tests passed\n'
