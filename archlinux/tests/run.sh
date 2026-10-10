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

expected_boot='title Arch Linux (linux-bore-flto-pgo)
linux /vmlinuz-linux-bore-flto-pgo
initrd /initramfs-linux-bore-flto-pgo.img
options root=PARTUUID=abc-123 rw nvidia-drm.modeset=1 nvidia-drm.fbdev=1'
ROOT_FS=xfs
assert_eq "$expected_boot" "$(render_boot_entry linux-bore-flto-pgo linux-bore-flto-pgo abc-123)" "boot entry rendering"
ROOT_FS=btrfs
btrfs_boot=$(render_boot_entry linux-bore-flto-pgo linux-bore-flto-pgo abc-123)
[[ $btrfs_boot == *'rootflags=subvol=@,compress=zstd:3,discard=async'* ]] || {
    printf 'FAIL: Btrfs boot entry must mount @ with asynchronous TRIM\n' >&2
    exit 1
}
[[ $btrfs_boot != *subvolid=* ]] || {
    printf 'FAIL: root must remain bootable when rollback changes its subvolume ID\n' >&2
    exit 1
}
[[ $(render_boot_entry linux-bore-flto-pgo linux-bore-flto-pgo abc-123 arch-1) == $'title Arch Linux (linux-bore-flto-pgo)\nsort-key arch-1\nlinux '* ]] || {
    printf 'FAIL: boot entry sort key\n' >&2
    exit 1
}
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

for pkg in networkmanager quickshell hypridle uwsm brave-origin-bin lact fzf pkgfile \
    ripgrep fwupd yubikey-manager yubikey-touch-detector wlr-randr pipewire-jack openai-codex zenity zed \
    rsync dconf wl-clipboard xdg-utils which proton-cachyos-slr mousepad; do
    if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: %s should be in official package list\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in systemd-networkd waybar swaync rofi swayidle swaylock helium-browser-bin kolourpaint python-pywal vesktop vesktop-bin vscodium btop mate-polkit gpu-screen-recorder-ui; do
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
for pkg in cmake clang cava claude-code ddcutil hyprsunset mission-center wine ttf-cascadia-code ttf-material-symbols-variable; do
    if ! printf '%s\n' "${OFFICIAL_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: installed package %s should be in the repo package list\n' "$pkg" >&2
        exit 1
    fi
done
for pkg in broadcast-linux-bin tiny-poe2smoother-bin python-pywal vesktop; do
    if ! printf '%s\n' "${AUR_PACKAGES[@]}" | grep -qx "$pkg"; then
        printf 'FAIL: installed foreign package %s should be in the AUR package list\n' "$pkg" >&2
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
make_kernel_fixture() {
    local output=$1 name=$2 version=$3
    mkdir -p "$tmpdir/metadata"
    printf 'pkgname = %s\npkgver = %s\narch = x86_64\n' "$name" "$version" >"$tmpdir/metadata/.PKGINFO"
    tar --zstd -cf "$output" -C "$tmpdir/metadata" .PKGINFO
}
mkdir -p "$tmpdir/kernel-only" "$tmpdir/nvidia-only" "$tmpdir/packages"
make_kernel_fixture "$tmpdir/kernel-only/linux-bore-flto-pgo-1-1-x86_64.pkg.tar.zst" "$PRIMARY_KERNEL" 1-1
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/kernel-only"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a missing NVIDIA package\n' >&2
    exit 1
fi
make_kernel_fixture "$tmpdir/nvidia-only/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 1-1
CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/nvidia-only"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a missing kernel package\n' >&2
    exit 1
fi

CUSTOM_KERNEL_PACKAGES_DIR="$tmpdir/packages"
cp "$tmpdir/kernel-only/"*.pkg.tar.zst "$tmpdir/nvidia-only/"*.pkg.tar.zst "$CUSTOM_KERNEL_PACKAGES_DIR/"
touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-headers-1-1-x86_64.pkg.tar.zst" \
    "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-dbg-1-1-x86_64.pkg.tar.zst"
validate_custom_kernel_packages
assert_eq "2" "${#CUSTOM_KERNEL_PACKAGES[@]}" "kernel package glob excludes headers and dbg"
if printf '%s\n' "${CUSTOM_KERNEL_PACKAGES[@]}" | grep -q -- '-headers-\|-dbg-'; then
    printf 'FAIL: kernel package glob picked up -headers or -dbg\n' >&2
    exit 1
fi

touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-2-1-x86_64.pkg.tar.zst"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted multiple kernel versions\n' >&2
    exit 1
fi
rm "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-2-1-x86_64.pkg.tar.zst"
touch "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-2-1-x86_64.pkg.tar.zst"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted multiple NVIDIA versions\n' >&2
    exit 1
fi
rm "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-2-1-x86_64.pkg.tar.zst"
make_kernel_fixture "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 2-1
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted mismatched package metadata versions\n' >&2
    exit 1
fi
make_kernel_fixture "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 1-1
printf 'invalid archive' >"$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst"
if (validate_custom_kernel_packages) >/dev/null 2>&1; then
    printf 'FAIL: custom kernel validation accepted a corrupt archive\n' >&2
    exit 1
fi
make_kernel_fixture "$CUSTOM_KERNEL_PACKAGES_DIR/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst" "${PRIMARY_KERNEL}-nvidia-open" 1-1

(
    # shellcheck source=../lib/config.sh
    source "$ROOT_DIR/lib/config.sh"
    unset CUSTOM_KERNEL_DIR CUSTOM_KERNEL_PACKAGES_DIR
    set_default_config
    assert_eq kernel/desktop "$CUSTOM_KERNEL_DIR" "desktop workspace default"
    assert_eq linux-bore-flto-pgo "$PRIMARY_KERNEL" "package name remains descriptive"
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

for package in docs applications swayidle swaylock xsettingsd etc usr utils gpu-screen-recorder btop; do
    if printf '%s\n' "${ARCH_STOW_PACKAGES[@]}" | grep -qx "$package"; then
        printf 'FAIL: %s should not be in the Arch Stow allowlist\n' "$package" >&2
        exit 1
    fi
done
for package in hypr quickshell uwsm zshrc broadcast-linux claude hypr-kblayoutd qalculate zed mpv; do
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
    mkdir -p "$STATE_DIR/dotfiles/etc/greetd" "$STATE_DIR/dotfiles/etc/tuigreet"
    for package in "${ARCH_STOW_PACKAGES[@]}"; do
        [[ $package == zed ]] || mkdir -p "$STATE_DIR/dotfiles/$package"
    done
    touch "$STATE_DIR/dotfiles/etc/greetd/config.toml" "$STATE_DIR/dotfiles/etc/tuigreet/config.toml"
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
    PRIMARY_KERNEL=linux-bore-flto-pgo
    cache="$tmpdir/kernel-cache"
    mkdir -p "$cache"
    cp "$tmpdir/packages/linux-bore-flto-pgo-1-1-x86_64.pkg.tar.zst" \
        "$tmpdir/packages/linux-bore-flto-pgo-nvidia-open-1-1-x86_64.pkg.tar.zst" "$cache/"
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

printf 'archlinux installer tests passed\n'
