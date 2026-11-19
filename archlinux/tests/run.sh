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
# shellcheck source=../lib/config.sh
source "$ROOT_DIR/lib/config.sh"
# shellcheck source=../lib/steps.sh
source "$ROOT_DIR/lib/steps.sh"
# shellcheck source=../lib/enroll.sh
source "$ROOT_DIR/lib/enroll.sh"

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

expected_cmdline='root=PARTUUID=abc-123 rw nvidia-drm.modeset=1 nvidia-drm.fbdev=1 quiet loglevel=3 systemd.show_status=false video=DP-3:3440x1440@240 fbcon=nodefer libahci.ignore_sss=1 usbcore.quirks=048d:5711:i'
ROOT_FS=xfs
assert_eq "$expected_cmdline" "$(kernel_cmdline abc-123)" "kernel command line"
[[ $(PRIMARY_KERNEL=linux-eevdf-lto-prop render_limine_defaults abc-123) != *SNAPPER* ]] || {
    printf 'FAIL: XFS installs have no snapshot boot entries\n' >&2
    exit 1
}
ROOT_FS=btrfs
btrfs_cmdline=$(kernel_cmdline abc-123)
[[ $btrfs_cmdline == *'rootflags=subvol=@,compress=zstd:3,discard=async'* ]] || {
    printf 'FAIL: Btrfs command line must mount @ with asynchronous TRIM\n' >&2
    exit 1
}
[[ $btrfs_cmdline != *subvolid=* ]] || {
    printf 'FAIL: root must remain bootable when a snapshot restore changes its subvolume ID\n' >&2
    exit 1
}
expected_limine='ESP_PATH="/boot"
UEFI_BOOT_ORDER=first
ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=no
KERNEL_CMDLINE[default]=root=PARTUUID=abc-123 rw rootflags=subvol=@,compress=zstd:3,discard=async nvidia-drm.modeset=1 nvidia-drm.fbdev=1 quiet loglevel=3 systemd.show_status=false video=DP-3:3440x1440@240 fbcon=nodefer libahci.ignore_sss=1 usbcore.quirks=048d:5711:i
BOOT_ORDER="linux-eevdf-lto-prop, *, *fallback, Snapshots"

SNAPPER_CONFIG_NAME="root"
ROOT_SUBVOLUME_PATH="/@"
ROOT_SNAPSHOTS_PATH="/@snapshots"
EXCLUDE_SNAPSHOT_TYPES="post"'
assert_eq "$expected_limine" "$(PRIMARY_KERNEL=linux-eevdf-lto-prop render_limine_defaults abc-123)" "Limine defaults rendering"
assert_eq $'btrfs-progs\nsnapper\nsnap-pac\nrsync' "$(filesystem_packages)" "Btrfs recovery packages"
ROOT_FS=xfs
assert_eq xfsprogs "$(filesystem_packages)" "XFS filesystem package"
ROOT_FS=btrfs

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
NETWORK_INTERFACE=enp14s0
NETWORK_ADDRESS=192.168.0.10/24
NETWORK_GATEWAY=192.168.0.1
NETWORK_DNS=192.168.0.3
configure_static_network "$tmpdir/system-connections/static-enp14s0.nmconnection" >/dev/null
assert_eq "600" "$(stat -c %a "$tmpdir/system-connections/static-enp14s0.nmconnection")" "NetworkManager keyfile mode"
assert_eq "700" "$(stat -c %a "$tmpdir/system-connections")" "NetworkManager connections directory mode"
configure_resolver_link "$tmpdir/resolv.conf"
assert_eq "/run/systemd/resolve/resolv.conf" "$(readlink "$tmpdir/resolv.conf")" "resolved resolv.conf link"

cat >"$tmpdir/system-auth" <<'EOF'
auth       required                    pam_faillock.so      preauth
-auth      [success=2 default=ignore]  pam_systemd_home.so
-auth      [success=1 default=bad]     pam_unix.so          try_first_pass nullok
-account   [success=1 default=ignore]  pam_systemd_home.so
account    required                    pam_unix.so
-password  [success=1 default=ignore]  pam_systemd_home.so
password   required                    pam_unix.so
-session   optional                    pam_systemd_home.so
session    required                    pam_unix.so
EOF
patch_system_auth_file "$tmpdir/system-auth" pam://installed-host
assert_eq "1" "$(grep -c '^auth.*pam_u2f' "$tmpdir/system-auth")" "one U2F authentication step in the complete PAM stack"
grep -q 'origin=pam://installed-host appid=pam://installed-host' "$tmpdir/system-auth"
cp "$tmpdir/system-auth" "$tmpdir/system-auth-once"
patch_system_auth_file "$tmpdir/system-auth" pam://installed-host
cmp "$tmpdir/system-auth-once" "$tmpdir/system-auth"
grep -q 'pam_u2f.so           authfile=/etc/Yubico/u2f_mappings cue pin=1' "$tmpdir/system-auth" || {
    printf 'FAIL: system-auth missing pam_u2f line\n' >&2
    exit 1
}
grep -q '^# -auth      \[success=1 default=bad\]     pam_unix.so' "$tmpdir/system-auth" || {
    printf 'FAIL: system-auth pam_unix auth was not commented\n' >&2
    exit 1
}

for pkg in networkmanager hypridle brave-origin-bin lact fzf pkgfile \
    ripgrep fwupd yubikey-manager pipewire-jack openai-codex opencode zenity zed python-gobject \
    rsync dconf wl-clipboard xdg-utils which proton-cachyos-slr mousepad xwayland-satellite passt; do
    if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: %s should be in official package list\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in systemd-networkd waybar swaync rofi swayidle swaylock helium-browser-bin kolourpaint python-pywal vesktop vscodium resources mate-polkit gpu-screen-recorder-ui \
    quickshell uwsm cliphist cpupower yubikey-touch-detector ttf-material-symbols-variable qt5ct wlr-randr python-dbus cava; do
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

for pkg in base-devel sudo cachyos-keyring cachyos-mirrorlist; do
    if ! printf '%s\n' "${BASE_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: required base package %s is missing\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in cmake clang rustup nasm claude-code ddcutil hyprsunset btop wine ttf-cascadia-code \
    vesktop-bin rtkit libvirt virt-manager qemu-desktop edk2-ovmf swtpm dnsmasq; do
    if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: installed package %s should be in the repo package list\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in broadcast-linux-bin tiny-poe2smoother-bin; do
    if ! printf '%s\n' "${AUR_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: installed foreign package %s should be in the AUR package list\n' "$pkg" >&2
        exit 1
    fi
done
if printf '%s\n' "${AUR_PACKAGES[@]}" | grep -qx python-pywal; then
    printf 'FAIL: stale package python-pywal should not be in the AUR package list\n' >&2
    exit 1
fi
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

PRIMARY_KERNEL=linux-eevdf-lto-prop
make_kernel_fixture() {
    local output=$1 name=$2 version=$3
    mkdir -p "$tmpdir/metadata"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$tmpdir/metadata/.PKGINFO"
    tar --zstd -cf "$output" -C "$tmpdir/metadata" .PKGINFO
}
mkdir -p "$tmpdir/kernel-only" "$tmpdir/nvidia-only" "$tmpdir/packages"
make_kernel_fixture "$tmpdir/kernel-only/linux-eevdf-lto-prop-1-1-x86_64.pkg.tar.zst" "$PRIMARY_KERNEL" 1-1
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/kernel-only"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a missing NVIDIA package\n' >&2
    exit 1
fi
make_kernel_fixture "$tmpdir/nvidia-only/linux-eevdf-lto-prop-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 1-1
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/nvidia-only"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a missing kernel package\n' >&2
    exit 1
fi

CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/packages"
cp "$tmpdir/kernel-only/"*.pkg.tar.zst "$tmpdir/nvidia-only/"*.pkg.tar.zst "$CUSTOM_KERNEL_PACKAGES_DIR/"
touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-headers-1-1-x86_64.pkg.tar.zst" \
    "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-dbg-1-1-x86_64.pkg.tar.zst"
validate_custom_kernel_packages
assert_eq "2" "${#CUSTOM_KERNEL_PACKAGES[@]}" "kernel package glob excludes headers and dbg"
if printf '%s\n' "${CUSTOM_KERNEL_PACKAGES[@]}" | grep -q -- '-headers-\|-dbg-'; then
    printf 'FAIL: kernel package glob picked up -headers or -dbg\n' >&2
    exit 1
fi

touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-2-1-x86_64.pkg.tar.zst"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted multiple kernel versions\n' >&2
    exit 1
fi
rm "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-2-1-x86_64.pkg.tar.zst"
touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-nvidia-open-2-1-x86_64.pkg.tar.zst"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted multiple NVIDIA versions\n' >&2
    exit 1
fi
rm "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-nvidia-open-2-1-x86_64.pkg.tar.zst"
make_kernel_fixture "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 2-1
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted mismatched package metadata versions\n' >&2
    exit 1
fi
make_kernel_fixture "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 1-1
printf 'invalid archive' >"$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-nvidia-open-1-1-x86_64.pkg.tar.zst"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a corrupt archive\n' >&2
    exit 1
fi
make_kernel_fixture "$CUSTOM_KERNEL_PACKAGES_DIR/linux-eevdf-lto-prop-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 1-1

(
    # shellcheck source=../lib/config.sh
    source "$ROOT_DIR/lib/config.sh"
    unset CUSTOM_KERNEL_DIR CUSTOM_KERNEL_PACKAGES_DIR
    set_default_config
    assert_eq kernel/desktop "$CUSTOM_KERNEL_DIR" "desktop workspace default"
    assert_eq linux-eevdf-lto-prop "$PRIMARY_KERNEL" "package name remains descriptive"
    SCRIPT_DIR="$ROOT_DIR"
    retry() { printf '%s\n' "$*" >> "$tmpdir/build-commands"; }
    build_custom_kernel_packages >/dev/null
    assert_eq "$(cd "$ROOT_DIR/.." && pwd)/kernel/desktop/out/kernel" "$CUSTOM_KERNEL_PACKAGES_DIR" "desktop package output"
    grep -Fxq 'docker compose run --rm -T --build kernel-builder' "$tmpdir/build-commands"
    CUSTOM_KERNEL_DIR=custom/workspace
    CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/packages"
    set_default_config
    build_custom_kernel_packages
    assert_eq custom/workspace "$CUSTOM_KERNEL_DIR" "workspace override preserved"
    assert_eq "$tmpdir/packages" "$CUSTOM_KERNEL_PACKAGES_DIR" "package override preserved"
)

for package in docs applications swayidle swaylock xsettingsd etc usr utils gpu-screen-recorder quickshell uwsm browser gamebridge; do
    if printf '%s\n' "${ARCH_STOW_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should not be in the Arch Stow allowlist\n' "$package" >&2
        exit 1
    fi
done
for package in hypr zshrc broadcast-linux claude hypr-kblayoutd qalculate zed mpv opencode tenant-host btop deskshell environment; do
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
for service in NetworkManager.service systemd-resolved.service lactd.service systemd-timesyncd.service; do
    if ! printf '%s\n' "${SYSTEM_SERVICES[@]}" | grep -qx "$service"; then
        printf 'FAIL: %s should be enabled\n' "$service" >&2
        exit 1
    fi
done
if ! printf '%s\n' "${DISABLED_SYSTEM_SERVICES[@]}" | grep -qx 'ananicy-cpp.service'; then
    printf 'FAIL: ananicy-cpp should be disabled after cachyos-settings enables it\n' >&2
    exit 1
fi

cat >"$tmpdir/pacman.conf" <<'EOF'
#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
EOF
enable_multilib "$tmpdir/pacman.conf"
assert_eq $'#[multilib-testing]\n#Include = /etc/pacman.d/mirrorlist\n\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' \
    "$(<"$tmpdir/pacman.conf")" "live ISO multilib enablement"

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

efibootmgr() {
    cat <<'EOF'
BootCurrent: 0002
BootOrder: 0002,0001,0004,0000
Boot0000* UiApp	FvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)
Boot0001* UEFI OS	HD(1,GPT,11111111-aaaa-4bbb-8ccc-000000000001,0x800,0xa00000)/\EFI\BOOT\BOOTX64.EFI
Boot0002* UEFI OS	HD(2,GPT,22222222-aaaa-4bbb-8ccc-000000000002,0x800,0x10000)/\EFI\BOOT\BOOTX64.EFI
Boot0003* Linux Boot Manager	HD(1,GPT,11111111-aaaa-4bbb-8ccc-000000000001,0x800,0xa00000)/\EFI\systemd\systemd-bootx64.efi
Boot0004* Limine	HD(1,GPT,11111111-AAAA-4BBB-8CCC-000000000001,0x800,0xa00000)/\EFI\limine\limine_x64.efi
EOF
}
assert_eq 0004 "$(firmware_boot_entry 11111111-aaaa-4bbb-8ccc-000000000001)" "Limine entry on the target ESP"
assert_eq "" "$(firmware_boot_entry 22222222-aaaa-4bbb-8ccc-000000000002)" "fallback entries are not Limine"
unset -f efibootmgr
assert_eq 0004,0002,0001,0000 "$(boot_order_with_first 0004 0002,0001,0004,0000)" "new system first in boot order"
assert_eq 0004 "$(boot_order_with_first 0004 '')" "boot order without other entries"

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

STEP_DONE_DIR="$tmpdir/steps"
STEP_FAILURE_HANDLER=
stops_at_first_error() {
    false
    touch "$tmpdir/continued-after-error"
}
set +e
(run_step errexit stops_at_first_error) 2>/dev/null
status=$?
set -e
assert_eq 1 "$status" "a failing step reports its status"
[[ ! -e $tmpdir/continued-after-error ]] || {
    printf 'FAIL: a step kept running after a failing command\n' >&2
    exit 1
}
[[ ! -e $STEP_DONE_DIR/errexit ]] || {
    printf 'FAIL: a failed step was marked done\n' >&2
    exit 1
}
fails_once() {
    [[ -e $tmpdir/failed-once ]] || {
        touch "$tmpdir/failed-once"
        return 1
    }
}
retry_answer() { return 0; }
STEP_FAILURE_HANDLER=retry_answer
run_step retried fails_once >/dev/null
[[ -e $STEP_DONE_DIR/retried ]] || {
    printf 'FAIL: a retried step was not marked done\n' >&2
    exit 1
}
must_not_run() { touch "$tmpdir/ran-finished-step"; }
run_step retried must_not_run >/dev/null
[[ ! -e $tmpdir/ran-finished-step ]] || {
    printf 'FAIL: a finished step ran again\n' >&2
    exit 1
}
skip_answer() { return 2; }
always_fails() { return 3; }
STEP_FAILURE_HANDLER=skip_answer
run_step skipped always_fails 2>/dev/null
[[ ! -e $STEP_DONE_DIR/skipped ]] || {
    printf 'FAIL: a skipped step was marked done\n' >&2
    exit 1
}
quit_answer() { return 1; }
STEP_FAILURE_HANDLER=quit_answer
set +e
(run_step quit always_fails)
status=$?
set -e
assert_eq 3 "$status" "quitting keeps the failed step's status"
STEP_DONE_DIR=
STEP_FAILURE_HANDLER=

assert_eq typed "$(ask answer 'Question:' <<<typed 2>/dev/null && printf '%s' "$answer")" "ask reads piped input"
read_into_value() {
    local value=old
    ask value 'Question:' <<<new 2>/dev/null
    printf '%s' "$value"
}
assert_eq new "$(read_into_value)" "ask sets the caller's local variable"

for address in 192.168.0.1 10.0.0.255; do
    valid_ipv4 "$address" || {
        printf 'FAIL: %s should be a valid IPv4 address\n' "$address" >&2
        exit 1
    }
done
for address in 192.168.0 256.1.1.1 1.2.3.4.5 a.b.c.d; do
    if valid_ipv4 "$address"; then
        printf 'FAIL: %s should be rejected\n' "$address" >&2
        exit 1
    fi
done
valid_ipv4_cidr 192.168.0.10/24 && ! valid_ipv4_cidr 192.168.0.10 && ! valid_ipv4_cidr 192.168.0.10/33 || {
    printf 'FAIL: CIDR validation\n' >&2
    exit 1
}
valid_dns_list '192.168.0.3;1.1.1.1' && ! valid_dns_list '192.168.0.3, 1.1.1.1' || {
    printf 'FAIL: DNS list validation\n' >&2
    exit 1
}
(
    unset TARGET_DISK
    set_default_config
    assert_eq "" "$TARGET_DISK" "no default target disk"
    assert_eq "" "$(setting_error INSTALL_USER)" "default user is valid"
    INSTALL_USER=root
    [[ -n $(setting_error INSTALL_USER) ]]
    HOSTNAME='bad host'
    [[ -n $(setting_error HOSTNAME) ]]
    TAILSCALE_UP_ARGS='--advertise-tags="tag:x"'
    [[ -n $(setting_error TAILSCALE_UP_ARGS) ]]
    ENABLE_DOTFILES=0
    RESTORE_LACT_CONFIG=1
    [[ -n $(setting_error RESTORE_LACT_CONFIG) ]]
) || {
    printf 'FAIL: setting validation\n' >&2
    exit 1
}

mkdir -p "$tmpdir/by-id" "$tmpdir/dev"
touch "$tmpdir/dev/nvme1n1" "$tmpdir/dev/nvme1n1p1"
ln -s ../dev/nvme1n1 "$tmpdir/by-id/nvme-eui.0025385b41b2a6a1"
ln -s ../dev/nvme1n1 "$tmpdir/by-id/nvme-Samsung_SSD_9100_PRO_4TB_S7XXNJ0Y"
ln -s ../dev/nvme1n1 "$tmpdir/by-id/nvme-Samsung_SSD_9100_PRO_4TB_S7XXNJ0Y_1"
ln -s ../dev/nvme1n1p1 "$tmpdir/by-id/nvme-Samsung_SSD_9100_PRO_4TB_S7XXNJ0Y-part1"
assert_eq "$tmpdir/by-id/nvme-Samsung_SSD_9100_PRO_4TB_S7XXNJ0Y" \
    "$(stable_disk_path "$tmpdir/dev/nvme1n1" "$tmpdir/by-id")" "disk saved by model and serial"
assert_eq /dev/vdz "$(stable_disk_path /dev/vdz "$tmpdir/by-id")" "disk without by-id link keeps its name"

credential_a='kh_A+/=,pkA+/=,es256,+presence+pin'
credential_b='kh_B+/=,pkB+/=,es256,+presence+pin'
mkdir -p "$tmpdir/keys/20683968" "$tmpdir/keys/36043558" "$tmpdir/keys/ssh-only"
printf '%s\n' "$credential_a" >"$tmpdir/keys/20683968/u2f"
printf '%s\n' "$credential_b" >"$tmpdir/keys/36043558/u2f"
assert_eq "$credential_a:$credential_b" "$(u2f_credentials "$tmpdir/keys")" "credentials of all keys are joined"
assert_eq "keng:$credential_a:$credential_b"$'\n'"root:$credential_a:$credential_b" \
    "$(render_u2f_mappings "$(u2f_credentials "$tmpdir/keys")" keng root)" "every key unlocks the user and root"
printf 'keng:%s\n' "$credential_a" >"$tmpdir/keys/36043558/u2f"
if u2f_credentials "$tmpdir/keys" >/dev/null; then
    printf 'FAIL: a malformed credential was accepted\n' >&2
    exit 1
fi
if u2f_credentials "$tmpdir/keys/ssh-only" >/dev/null; then
    printf 'FAIL: an empty credential list was accepted\n' >&2
    exit 1
fi

DOTFILES_REPO=git@github.com:kengzzzz/dotfiles.git
dotfiles_repo_uses_ssh && assert_eq github.com "$(dotfiles_repo_host)" "scp-style repo host"
DOTFILES_REPO=ssh://git@git.example.com/dotfiles.git
dotfiles_repo_uses_ssh && assert_eq git.example.com "$(dotfiles_repo_host)" "ssh URL repo host"
for DOTFILES_REPO in https://github.com/kengzzzz/dotfiles.git /root/dotfiles.bundle; do
    if dotfiles_repo_uses_ssh; then
        printf 'FAIL: %s does not need an SSH key\n' "$DOTFILES_REPO" >&2
        exit 1
    fi
done

(
    STATE_DIR="$tmpdir/state"
    DOTFILES_REPO=git@github.com:kengzzzz/dotfiles.git
    mkdir -p "$STATE_DIR/dotfiles/ssh/.ssh" "$STATE_DIR/yubikeys" "$tmpdir/bin"
    cat >"$STATE_DIR/dotfiles/ssh/.ssh/config" <<'EOF'
Match exec "ykman list --serials 2>/dev/null | grep -qx 36043558"
    Tag yubikey-5c-nfc

Match tagged yubikey-5c-nfc
    IdentityFile ~/.ssh/id_ed25519_sk_5c_nfc

Match !tagged yubikey-5c-nfc
    IdentityFile ~/.ssh/id_ed25519_sk
EOF
    printf '#!/bin/sh\ncat %q\n' "$tmpdir/plugged-serial" >"$tmpdir/bin/ykman"
    chmod +x "$tmpdir/bin/ykman"
    PATH="$tmpdir/bin:$PATH"
    for serial in 20683968 36043558 99999999; do
        mkdir -p "$STATE_DIR/yubikeys/$serial/ssh"
        printf 'id_ed25519_sk_rk\n' >"$STATE_DIR/yubikeys/$serial/ssh/downloaded-name"
        printf '%s\n' "$serial" >"$tmpdir/plugged-serial"
        choose_ssh_key_name "$STATE_DIR/yubikeys/$serial" "$serial" 2>/dev/null
    done
    assert_eq id_ed25519_sk "$(<"$STATE_DIR/yubikeys/20683968/ssh_name")" "5 Nano SSH key name"
    assert_eq id_ed25519_sk_5c_nfc "$(<"$STATE_DIR/yubikeys/36043558/ssh_name")" "5C NFC SSH key name"
    assert_eq id_ed25519_sk_99999999 "$(<"$STATE_DIR/yubikeys/99999999/ssh_name")" "unmatched key gets a unique name"
    rm -rf "$STATE_DIR/dotfiles"
    mkdir -p "$STATE_DIR/yubikeys/11111111/ssh"
    printf 'id_ecdsa_sk_rk_ssh_work\n' >"$STATE_DIR/yubikeys/11111111/ssh/downloaded-name"
    choose_ssh_key_name "$STATE_DIR/yubikeys/11111111" 11111111
    assert_eq id_ecdsa_sk "$(<"$STATE_DIR/yubikeys/11111111/ssh_name")" "default name without a dotfiles config"
)

(
    STATE_DIR="$tmpdir/dotfiles-state"
    ENABLE_DOTFILES=1
    RESTORE_LACT_CONFIG=0
    mkdir -p "$STATE_DIR/dotfiles/etc/greetd"
    for package in "${ARCH_STOW_PACKAGES[@]}"; do
        [[ $package == zed ]] || mkdir -p "$STATE_DIR/dotfiles/$package"
    done
    touch "$STATE_DIR/dotfiles/etc/greetd/config.toml" "$STATE_DIR/dotfiles/etc/greetd/install.sh"
    problems=$(dotfiles_problems)
    [[ $problems == *"warning: dotfiles have no 'zed' Stow package"* ]]
    [[ $problems == *"error: dotfiles lack usr/share/wayland-sessions"* ]]
    [[ $problems != *"etc/greetd"* ]]
) || {
    printf 'FAIL: dotfiles checks before erasing the disk\n' >&2
    exit 1
}

(
    INSTALL_SUDOERS="$tmpdir/sudoers-install"
    INSTALL_USER=keng
    configure_makepkg() { :; }
    visudo() { :; }
    runuser() { [[ -f $INSTALL_SUDOERS ]] && return 7; }
    set +e
    (
        set -e
        install_aur_packages_as_user
    ) >/dev/null
    status=$?
    set -e
    assert_eq 7 "$status" "AUR step saw the temporary sudo rule"
    [[ ! -e $INSTALL_SUDOERS ]] || {
        printf 'FAIL: temporary sudo rule left behind after a failed AUR build\n' >&2
        exit 1
    }
    runuser() { :; }
    install_aur_packages_as_user >/dev/null
    [[ ! -e $INSTALL_SUDOERS ]] || {
        printf 'FAIL: temporary sudo rule left behind after AUR packages\n' >&2
        exit 1
    }
)

(
    PRIMARY_KERNEL=linux-eevdf-lto-prop
    cache="$tmpdir/kernel-cache"
    mkdir -p "$cache"
    cp "$tmpdir/packages/linux-eevdf-lto-prop-1-1-x86_64.pkg.tar.zst" \
        "$tmpdir/packages/linux-eevdf-lto-prop-nvidia-open-1-1-x86_64.pkg.tar.zst" "$cache/"
    kernel_build_inputs() { printf 'same sources\n'; }
    build_custom_kernel_packages() { touch "$tmpdir/kernel-rebuilt"; }
    printf 'same sources\n' >"$cache/inputs"
    prepare_custom_kernel_packages "$cache" >/dev/null
    [[ ! -e $tmpdir/kernel-rebuilt ]] || {
        printf 'FAIL: matching kernel packages were rebuilt\n' >&2
        exit 1
    }
    printf 'older sources\n' >"$cache/inputs"
    build_custom_kernel_packages() {
        touch "$tmpdir/kernel-rebuilt"
        CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/packages"
    }
    prepare_custom_kernel_packages "$cache" >/dev/null
    [[ -e $tmpdir/kernel-rebuilt ]] || {
        printf 'FAIL: kernel packages from other sources were reused\n' >&2
        exit 1
    }
    assert_eq 'same sources' "$(<"$cache/inputs")" "rebuilt kernel cache records its sources"
)

(
    bin="$tmpdir/tailscale-bin"
    mkdir -p "$bin" "$tmpdir/tailscale-home"
    cat >"$bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
    cat >"$bin/tailscale" <<EOF
#!/bin/bash
case \$1 in
    status) [[ -e $tmpdir/tailscale-up ]] && echo '{"BackendState":"Running"}' || echo '{"BackendState":"NeedsLogin"}' ;;
    up)
        shift
        printf '%s\n' "\$*" >$tmpdir/tailscale-args
        printf '\nTo authenticate, visit:\n\n\thttps://login.tailscale.com/a/abc123\n\n' >&2
        touch $tmpdir/tailscale-up
        ;;
esac
EOF
    printf '#!/bin/bash\nprintf "%%s\\n" "$1" >%q\n' "$tmpdir/opened-url" >"$bin/xdg-open"
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >%q\n' "$tmpdir/kitty-args" >"$bin/kitty"
    chmod +x "$bin"/*
    printf 'TAILSCALE_UP_ARGS=( --accept-dns=false --accept-routes )\n' >"$tmpdir/tailscale-login.conf"
    export PATH="$bin:$PATH" HOME="$tmpdir/tailscale-home" TAILSCALE_LOGIN_CONF="$tmpdir/tailscale-login.conf"
    export TAILSCALE_LOGIN_CLOSE_DELAY=0
    unset XDG_STATE_HOME
    script="$ROOT_DIR/scripts/tailscale-login.sh"
    bash "$script"
    [[ $(<"$tmpdir/kitty-args") == *"$script --terminal" ]]
    bash "$script" --terminal </dev/null >/dev/null
    sleep 0.2
    assert_eq '--accept-dns=false --accept-routes' "$(<"$tmpdir/tailscale-args")" "tailscale up options"
    assert_eq https://login.tailscale.com/a/abc123 "$(<"$tmpdir/opened-url")" "login page opened"
    [[ -e $HOME/.local/state/sys-setup/tailscale-login.done ]]
    rm "$tmpdir/kitty-args"
    bash "$script"
    [[ ! -e $tmpdir/kitty-args ]]
) || {
    printf 'FAIL: Tailscale first-login script\n' >&2
    exit 1
}

(
    sum=169a1b42c1fba9589ce173ea09c5fc89094d45cb31aab2ec82cd5a456d82593e
    entry="$sum  deskshell-0.2.0-1-x86_64.pkg.tar.zst"
    assert_eq "$entry" "$(printf '%s\n%s  SHA256SUMS.sig\n' "$entry" "$sum" | deskshell_release_entry)" "deskshell release entry"
    (printf '%s\n%s  deskshell-0.1.0-1-x86_64.pkg.tar.zst\n' "$entry" "$sum" | deskshell_release_entry) 2>/dev/null && exit 1
    (printf '%s  deskshell-1/../../x-x86_64.pkg.tar.zst\n' "$sum" | deskshell_release_entry) 2>/dev/null && exit 1
    (: | deskshell_release_entry) 2>/dev/null && exit 1
    printf '# comment\nusers = ["alice"]\n# users = ["bob"]\n' >"$tmpdir/greeter.toml"
    assert_eq $'# comment\nusers = ["keng"]\n# users = ["bob"]' \
        "$(render_deskshell_greeter_config keng "$tmpdir/greeter.toml")" "deskshell greeter users"
) || {
    printf 'FAIL: deskshell release and greeter config\n' >&2
    exit 1
}

make_package_fixture() {
    local output=$1 name=$2 version=$3 dep
    shift 3
    rm -rf "$tmpdir/pkginfo"
    mkdir -p "$tmpdir/pkginfo"
    {
        printf 'pkgname = %s\npkgver = %s\n' "$name" "$version"
        for dep in "$@"; do
            printf 'depend = %s\n' "$dep"
        done
    } >"$tmpdir/pkginfo/.PKGINFO"
    tar --zstd -cf "$output" -C "$tmpdir/pkginfo" .PKGINFO
}

(
    checkout="$tmpdir/patched-checkout"
    add_build() {
        local pkg=$1 version=$2 abi=$3
        shift 3
        mkdir -p "$checkout/$pkg/dist/$version"
        printf 'PKGVER=%s\nPKGREL=%s\nABI_PACKAGES="%s"\n' "${version%-*}" "${version##*-}" "$abi" \
            >"$checkout/$pkg/package.env"
        printf '%s\n' "$@" >"$checkout/$pkg/dist/$version/build-packages.txt"
    }
    add_build aquamarine 0.16.0-1.4 hyprutils 'hyprutils 0.14.3-1'
    make_package_fixture "$checkout/aquamarine/dist/0.16.0-1.4/aquamarine-0.16.0-1.4-x86_64.pkg.tar.zst" \
        aquamarine 0.16.0-1.4 'hyprutils>=0.14'
    add_build hyprland 0.57.2-1.8 'aquamarine hyprutils' 'aquamarine 0.16.0-1' 'hyprutils 0.14.3-1'
    make_package_fixture "$checkout/hyprland/dist/0.57.2-1.8/hyprland-0.57.2-1.8-x86_64.pkg.tar.zst" \
        hyprland 0.57.2-1.8 aquamarine 'hyprutils>=0.14'
    make_package_fixture "$checkout/hyprland/dist/0.57.2-1.8/hyprpm-0.57.2-1.8-x86_64.pkg.tar.zst" \
        hyprpm 0.57.2-1.8 not-installed-dep
    add_build freerdp 3.33.1-1.3 ''
    make_package_fixture "$checkout/freerdp/dist/3.33.1-1.3/freerdp-2:3.33.1-1.3-x86_64.pkg.tar.zst" \
        freerdp 2:3.33.1-1.3 missing-dep
    add_build egl-wayland2 1.0.2-1.4 ''
    rm -rf "$checkout/egl-wayland2/dist"
    for dir in "$checkout"/*/dist/*/; do
        (cd "$dir" && sha256sum -- *.pkg.tar.zst >SHA256SUMS)
    done

    builds=$(patched_package_builds "$checkout" 2>"$tmpdir/patched-warnings")
    assert_eq "aquamarine $checkout/aquamarine/dist/0.16.0-1.4
hyprland $checkout/hyprland/dist/0.57.2-1.8
freerdp $checkout/freerdp/dist/3.33.1-1.3" "$builds" "finished patched builds"
    grep -q 'egl-wayland2 1.0.2-1.4 was not built' "$tmpdir/patched-warnings"
    [[ -z $(patched_package_builds "$tmpdir/no-such-checkout" 2>/dev/null) ]]

    INSTALL_STATE="$tmpdir/patched-state"
    stage_patched_packages "$checkout" "$INSTALL_STATE/patched-packages" 2>/dev/null
    assert_eq 'aquamarine freerdp hyprland' "$(cd "$INSTALL_STATE/patched-packages" && echo *)" "staged patched packages"
    [[ -f $INSTALL_STATE/patched-packages/hyprland/package.env ]]
    [[ -f $INSTALL_STATE/patched-packages/hyprland/build-packages.txt ]]

    pacman_db='aquamarine 0.16.0-1
hyprutils 0.14.3-1
hyprland 0.57.2-1
freerdp 2:3.33.1-1'
    pacman() {
        case $1 in
            -Q) awk -v p="$2" '$1 == p { print; found=1 } END { exit !found }' <<<"$pacman_db" ;;
            -T)
                shift
                local dep status=0
                for dep in "$@"; do
                    if ! awk -v p="${dep%%[<>=]*}" '$1 == p { found=1 } END { exit !found }' <<<"$pacman_db"; then
                        printf '%s\n' "$dep"
                        status=127
                    fi
                done
                return "$status"
                ;;
            -U)
                shift 2
                printf '%s\n' "${@##*/}" >"$tmpdir/patched-installed"
                ;;
        esac
    }
    [[ -z $(patched_package_problems "$INSTALL_STATE/patched-packages/hyprland") ]]
    assert_eq 'freerdp needs missing-dep' "$(patched_package_problems "$INSTALL_STATE/patched-packages/freerdp")" \
        "missing patched dependency"
    pacman_db=${pacman_db/hyprutils 0.14.3-1/hyprutils 0.15.0-1}
    assert_eq 'hyprutils built against 0.14.3-1, the system has 0.15.0-1' \
        "$(patched_package_problems "$INSTALL_STATE/patched-packages/aquamarine")" "patched ABI mismatch"
    pacman_db=${pacman_db/hyprutils 0.15.0-1/hyprutils 0.14.3-1}
    pacman_db=${pacman_db/hyprland 0.57.2-1/hyprland 0.57.3-1}
    assert_eq 'hyprland is 0.57.2-1.8, the system has 0.57.3-1' \
        "$(patched_package_problems "$INSTALL_STATE/patched-packages/hyprland")" "patched package older than the system"
    pacman_db=${pacman_db/hyprland 0.57.3-1/hyprland 0.57.2-1}

    install_patched_packages >/dev/null 2>"$tmpdir/patched-install-warnings"
    assert_eq $'aquamarine-0.16.0-1.4-x86_64.pkg.tar.zst\nhyprland-0.57.2-1.8-x86_64.pkg.tar.zst' \
        "$(<"$tmpdir/patched-installed")" "installed patched packages"
    grep -q 'patched freerdp does not fit this system' "$tmpdir/patched-install-warnings"

    rm "$tmpdir/patched-installed"
    INSTALL_STATE="$tmpdir/empty-state"
    install_patched_packages >/dev/null 2>&1
    [[ ! -e $tmpdir/patched-installed ]]
) || {
    printf 'FAIL: patched packages\n' >&2
    exit 1
}

(
    releases="$tmpdir/releases"
    mkdir -p "$releases/raw"
    make_release() {
        local pkg=$1 version=$2 src="$tmpdir/release-src/$1"
        mkdir -p "$src/$pkg/dist/$version" "$releases/raw/$pkg" "$releases/$pkg-$version"
        printf 'PKGVER=%s\nPKGREL=%s\n' "${version%-*}" "${version##*-}" | tee "$src/$pkg/package.env" \
            >"$releases/raw/$pkg/package.env"
        make_package_fixture "$src/$pkg/dist/$version/$pkg-$version-x86_64.pkg.tar.zst" "$pkg" "$version"
        printf '%s 1-1\n' "$pkg" >"$src/$pkg/dist/$version/build-packages.txt"
        (cd "$src/$pkg/dist/$version" && sha256sum -- *.pkg.tar.zst >SHA256SUMS)
        tar -cf "$releases/$pkg-$version/$pkg-$version.tar" -C "$src" "$pkg"
        (cd "$releases/$pkg-$version" && sha256sum "$pkg-$version.tar" >"$pkg-$version.tar.sha256")
    }
    make_release aquamarine 0.16.0-1.4
    make_release hyprland 0.57.2-1.8
    make_release freerdp 3.33.1-1.3
    printf 'tampered\n' >>"$releases/freerdp-3.33.1-1.3/freerdp-3.33.1-1.3.tar"
    make_release egl-wayland2 1.0.2-1.4
    ln -s /etc/passwd "$tmpdir/release-src/egl-wayland2/egl-wayland2/link"
    tar -cf "$releases/egl-wayland2-1.0.2-1.4/egl-wayland2-1.0.2-1.4.tar" -C "$tmpdir/release-src/egl-wayland2" egl-wayland2
    (cd "$releases/egl-wayland2-1.0.2-1.4" && sha256sum egl-wayland2-1.0.2-1.4.tar >egl-wayland2-1.0.2-1.4.tar.sha256)
    rm -r "$releases/hyprland-0.57.2-1.8"

    PATCHED_PACKAGES_RAW=https://raw.test
    PATCHED_PACKAGES_RELEASES=https://releases.test
    curl() {
        local url=${*: -1} output='' file
        while (($#)); do
            [[ $1 != -o ]] || output=$2
            shift
        done
        case $url in
            https://raw.test/*) file=$releases/raw/${url#https://raw.test/} ;;
            https://releases.test/*) file=$releases/${url#https://releases.test/} ;;
        esac
        printf '%s\n' "$url" >>"$tmpdir/curl-urls"
        [[ -f $file ]] || return 22
        if [[ -n $output ]]; then cp "$file" "$output"; else cat "$file"; fi
    }
    dir="$tmpdir/patched-download"
    fetch_patched_packages "$dir" >/dev/null 2>"$tmpdir/fetch-warnings"
    [[ -f $dir/aquamarine/dist/0.16.0-1.4/SHA256SUMS && -f $dir/aquamarine/package.env ]]
    [[ ! -e $dir/hyprland && ! -e $dir/freerdp && ! -e $dir/egl-wayland2 ]]
    grep -q 'no release hyprland-0.57.2-1.8' "$tmpdir/fetch-warnings"
    grep -q 'freerdp-3.33.1-1.3.tar does not match its checksum' "$tmpdir/fetch-warnings"
    grep -q 'egl-wayland2-1.0.2-1.4.tar holds files outside' "$tmpdir/fetch-warnings"
    assert_eq "aquamarine $dir/aquamarine/dist/0.16.0-1.4" "$(patched_package_builds "$dir" 2>/dev/null)" "downloaded patched builds"

    rm "$tmpdir/curl-urls"
    fetch_patched_package "$dir" aquamarine >/dev/null
    assert_eq https://raw.test/aquamarine/package.env "$(<"$tmpdir/curl-urls")" "verified release reused"

    printf 'PKGVER=0.16.0\nPKGREL=$(reboot)\n' >"$releases/raw/aquamarine/package.env"
    fetch_patched_package "$dir" aquamarine >/dev/null 2>"$tmpdir/fetch-warnings"
    grep -q 'no usable PKGVER' "$tmpdir/fetch-warnings"
) || {
    printf 'FAIL: patched package downloads\n' >&2
    exit 1
}

printf 'archlinux installer tests passed\n'
