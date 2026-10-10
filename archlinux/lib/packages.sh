#!/usr/bin/env bash

BASE_PACKAGES=(
    base
    base-devel
    linux-firmware
    cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist
    git
    openssh
    nano
    pcsclite
    libfido2
    ccid
    sudo
    dosfstools
)

OFFICIAL_PACKAGES=(
    gnu-free-fonts noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
    greetd greetd-tuigreet hyprland swaybg swayimg hypridle hyprsunset
    quickshell uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk gnome-keyring seahorse
    qt5ct qt6ct papirus-icon-theme thunar mousepad gvfs tumbler kitty cliphist grim slurp swappy hyprpicker
    pipewire pipewire-pulse pipewire-jack wireplumber pavucontrol blueman brave-origin-bin mpv playerctl qalculate-gtk
    nvidia-utils lib32-nvidia-utils egl-gbm libva-nvidia-driver cpupower
    zsh zsh-completions zsh-syntax-highlighting imagemagick tesseract tesseract-data-eng tesseract-data-tha ffmpegthumbnailer
    ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-common ttf-ibm-plex ttf-cascadia-code ttf-material-symbols-variable fzf pkgfile
    eza fastfetch freerdp jq bc cpio ripgrep docker bubblewrap gpu-screen-recorder
    pacman-contrib cachyos-settings socat steam proton-cachyos-slr stow tailscale docker-compose
    paru
    docker-buildx accountsservice python-dbus zed nwg-look pam-u2f
    networkmanager lact fwupd yubikey-manager yubikey-touch-detector wlr-randr openai-codex zenity
    cava claude-code ddcutil mission-center wine clang cmake
    edk2-shell sbctl sbsigntools
    rsync dconf wl-clipboard xdg-utils which
)

AUR_PACKAGES=(
    tokyonight-gtk-theme-git hypr-kblayoutd-bin catppuccin-cursors-mocha
    broadcast-linux-bin tiny-poe2smoother-bin python-pywal vesktop
)

LIVE_PACKAGES=(
    git curl rsync arch-install-scripts gptfdisk dosfstools btrfs-progs xfsprogs parted
    docker docker-compose pam-u2f libfido2 openssh yubikey-manager pcsclite ccid efibootmgr
)

INSTALL_SUDOERS=/etc/sudoers.d/00-sys-setup-install

WORKLOAD_PACKAGES=(
    nvidia-container-toolkit
    qemu-user-static
    qemu-user-static-binfmt
)

filesystem_packages() {
    if [[ ${ROOT_FS:-btrfs} == btrfs ]]; then
        printf '%s\n' btrfs-progs snapper snap-pac rsync
    else
        printf '%s\n' xfsprogs
    fi
}

prepare_live_environment() {
    section "Preparing live environment"
    local -a missing=()
    local package
    if [[ -d /run/archiso ]]; then
        # The default 256M overlay is too small for a full upgrade plus Docker.
        mount -o remount,size=20G /run/archiso/cowspace || warn "could not resize archiso cowspace"
    fi
    for package in "${LIVE_PACKAGES[@]}"; do
        pacman -Qq "$package" >/dev/null 2>&1 || missing+=("$package")
    done
    # Upgrading the live kernel deletes the running kernel's modules, which Docker needs.
    ((${#missing[@]} == 0)) || retry pacman -Syu --noconfirm --needed --ignore linux "${missing[@]}"
}

prepare_live_repos() {
    enable_multilib
    setup_cachyos_repo
    sync_pacman
}

setup_cachyos_repo() {
    section "Setting up CachyOS repository"
    if pacman-conf --repo-list | grep -qx cachyos; then
        log "CachyOS repository is already configured"
        return 0
    fi
    local repo_root
    repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
    run bash "$repo_root/kernel/desktop/scripts/setup-cachyos-repo.sh" \
        "$repo_root/kernel/common/assets/cachyos-signing-key.asc"
}

enable_multilib() {
    sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//;}' "${1:-/etc/pacman.conf}"
}

sync_pacman() {
    section "Syncing package databases"
    local -a ignore=()
    # Upgrading the live kernel deletes the running kernel's modules, which Docker needs.
    [[ ! -d /run/archiso ]] || ignore=(--ignore linux)
    retry pacman -Syu --noconfirm "${ignore[@]}"
}

pacstrap_base() {
    section "Installing base system"
    local packages=("${BASE_PACKAGES[@]}" "$FALLBACK_KERNEL" "$FALLBACK_NVIDIA_PACKAGE")
    local -a filesystem
    mapfile -t filesystem < <(filesystem_packages)
    packages+=("${filesystem[@]}")
    case "$(awk '/^vendor_id/ {print $3; exit}' /proc/cpuinfo)" in
        AuthenticAMD) packages+=(amd-ucode) ;;
        GenuineIntel) packages+=(intel-ucode) ;;
    esac
    retry pacstrap -K -P /mnt "${packages[@]}"
}

generate_fstab() {
    section "Generating fstab"
    genfstab -U /mnt >/mnt/etc/fstab
    if [[ $ROOT_FS == btrfs ]]; then
        # Restoring a snapshot changes its ID. Mount by the stable subvolume path.
        sed -i '/[[:space:]]btrfs[[:space:]]/ { s/subvolid=[0-9]*,//g; s/,subvolid=[0-9]*//g; }' /mnt/etc/fstab
    fi
}

install_official_packages() {
    section "Installing official packages"
    local packages=("${OFFICIAL_PACKAGES[@]}")
    if [[ ${ENABLE_WORKLOAD_PACKAGES:-1} == 1 ]]; then
        packages+=("${WORKLOAD_PACKAGES[@]}")
    fi
    retry pacman -S --noconfirm --needed "${packages[@]}"
}

validate_package_selection() {
    section "Checking package availability before erasing the disk"
    local db_dir metadata expected_nvidia available_nvidia
    validate_custom_kernel_packages
    local packages=("${BASE_PACKAGES[@]}" "${OFFICIAL_PACKAGES[@]}" "$FALLBACK_KERNEL" "$FALLBACK_NVIDIA_PACKAGE")
    local -a filesystem
    mapfile -t filesystem < <(filesystem_packages)
    packages+=("${filesystem[@]}")
    case "$(awk '/^vendor_id/ {print $3; exit}' /proc/cpuinfo)" in
        AuthenticAMD) packages+=(amd-ucode) ;;
        GenuineIntel) packages+=(intel-ucode) ;;
    esac
    [[ ${ENABLE_WORKLOAD_PACKAGES:-1} != 1 ]] || packages+=("${WORKLOAD_PACKAGES[@]}")
    db_dir=$(mktemp -d)
    mkdir -p "$db_dir/local"
    ln -s /var/lib/pacman/sync "$db_dir/sync"
    if ! pacman --dbpath "$db_dir" -Sp --noconfirm --print-format '%r/%n %v' "${packages[@]}"; then
        rm -rf "$db_dir"
        die "package selection cannot be resolved; disk was left unchanged"
    fi
    if ! pacman --dbpath "$db_dir" -Up --noconfirm --print-format '%n %v' "${CUSTOM_KERNEL_PACKAGES[@]}"; then
        rm -rf "$db_dir"
        die "custom kernel dependencies cannot be resolved; disk was left unchanged"
    fi
    rm -rf "$db_dir"
    metadata=$(tar -xOf "${CUSTOM_KERNEL_PACKAGES[1]}" .PKGINFO)
    expected_nvidia=$(awk '$1 == "depend" && $3 ~ /^nvidia-utils=/ {sub(/^nvidia-utils=/, "", $3); print $3; exit}' <<<"$metadata")
    available_nvidia=$(pacman -Sddp --print-format '%v' nvidia-utils)
    # NVIDIA dependencies normally omit pkgrel; pacman ignores it in that case.
    [[ $expected_nvidia == *-* ]] || available_nvidia=${available_nvidia%-*}
    [[ -z $expected_nvidia || $(vercmp "$expected_nvidia" "$available_nvidia") == 0 ]] \
        || die "custom kernel needs nvidia-utils=$expected_nvidia, but the repo has $available_nvidia; rebuild the packages before installing"
}

remove_install_sudoers() {
    rm -f "${1:-}$INSTALL_SUDOERS"
}

install_aur_packages_as_user() {
    section "Installing AUR packages"
    configure_makepkg
    # paru needs sudo and the user has no password.
    trap remove_install_sudoers EXIT
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$INSTALL_USER" >"$INSTALL_SUDOERS"
    chmod 440 "$INSTALL_SUDOERS"
    visudo -cqf "$INSTALL_SUDOERS"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        command -v paru >/dev/null 2>&1 || {
            printf "paru not found; expected it from the CachyOS repo\n" >&2
            exit 1
        }
        paru -S --noconfirm --needed --skipreview "$@"
    ' bash "${AUR_PACKAGES[@]}"
    remove_install_sudoers
}

prepare_live_docker_storage() {
    [[ -d /run/archiso ]] || return 0
    local dir
    # Container overlays cannot use the live ISO's overlay root as their upper layer.
    for dir in /var/lib/docker /var/lib/containerd; do
        mountpoint -q "$dir" || run mount --mkdir -t tmpfs -o mode=0711 tmpfs "$dir"
    done
}

build_custom_kernel_packages() {
    [[ ${CUSTOM_KERNEL_BUILD:-1} == 1 ]] || return 0
    [[ -z ${CUSTOM_KERNEL_PACKAGES_DIR:-} ]] || return 0

    section "Building custom kernel packages"
    local repo_root
    repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
    local kernel_dir="$repo_root/$CUSTOM_KERNEL_DIR"
    [[ -d $kernel_dir ]] || die "custom kernel directory not found: $kernel_dir"

    prepare_live_docker_storage
    retry systemctl start docker
    (
        cd "$kernel_dir" || exit
        retry docker compose run --rm -T --build kernel-builder </dev/null
    )
    CUSTOM_KERNEL_PACKAGES_DIR="$kernel_dir/out/kernel"
}

kernel_build_inputs() {
    local repo_root tree
    repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
    tree=$(git -C "$repo_root" rev-parse HEAD:kernel 2>/dev/null) || return 1
    printf '%s %s %s\n' "$PRIMARY_KERNEL" "$CUSTOM_KERNEL_DIR" "$tree"
    {
        git -C "$repo_root" diff HEAD -- kernel
        git -C "$repo_root" status --porcelain -- kernel
    } | sha256sum
}

prepare_custom_kernel_packages() {
    local cache=$1 inputs=''
    inputs=$(kernel_build_inputs) || inputs=''
    if [[ -n $inputs && -f $cache/inputs && $(<"$cache/inputs") == "$inputs" ]] \
        && (CUSTOM_KERNEL_PACKAGES_DIR=$cache validate_custom_kernel_packages) >/dev/null 2>&1; then
        log "reusing kernel packages built by an earlier attempt"
        return 0
    fi
    [[ ${CUSTOM_KERNEL_BUILD:-1} == 1 ]] || die "CUSTOM_KERNEL_BUILD=0 needs --kernel-packages-dir"
    CUSTOM_KERNEL_PACKAGES_DIR=
    build_custom_kernel_packages
    validate_custom_kernel_packages
    rm -rf "$cache"
    mkdir -p "$cache"
    cp -f "${CUSTOM_KERNEL_PACKAGES[@]}" "$cache/"
    [[ -z $inputs ]] || printf '%s\n' "$inputs" >"$cache/inputs"
}

validate_custom_kernel_packages() {
    [[ -n ${CUSTOM_KERNEL_PACKAGES_DIR:-} ]] || die "custom kernel packages directory is required"
    [[ -d $CUSTOM_KERNEL_PACKAGES_DIR ]] || die "custom kernel packages directory not found: $CUSTOM_KERNEL_PACKAGES_DIR"

    local kernel_packages nvidia_packages
    shopt -s nullglob
    kernel_packages=("$CUSTOM_KERNEL_PACKAGES_DIR"/"${PRIMARY_KERNEL}"-[0-9]*.pkg.tar.zst)
    nvidia_packages=("$CUSTOM_KERNEL_PACKAGES_DIR"/"${PRIMARY_KERNEL}"-nvidia-open-[0-9]*.pkg.tar.zst)
    shopt -u nullglob

    ((${#kernel_packages[@]} > 0)) || die "custom kernel package not found in $CUSTOM_KERNEL_PACKAGES_DIR"
    ((${#nvidia_packages[@]} > 0)) || die "custom kernel NVIDIA package not found in $CUSTOM_KERNEL_PACKAGES_DIR"
    ((${#kernel_packages[@]} == 1)) || die "multiple custom kernel versions in $CUSTOM_KERNEL_PACKAGES_DIR; archive older packages"
    ((${#nvidia_packages[@]} == 1)) || die "multiple custom kernel NVIDIA versions in $CUSTOM_KERNEL_PACKAGES_DIR; archive older packages"
    CUSTOM_KERNEL_PACKAGES=("${kernel_packages[@]}" "${nvidia_packages[@]}")

    local package metadata name version kernel_version='' nvidia_version=''
    for package in "${CUSTOM_KERNEL_PACKAGES[@]}"; do
        metadata=$(tar -xOf "$package" .PKGINFO) || die "cannot read package metadata: $package"
        name=$(awk '$1 == "pkgname" {print $3; exit}' <<<"$metadata")
        version=$(awk '$1 == "pkgver" {print $3; exit}' <<<"$metadata")
        [[ -n $version ]] || die "package version is missing: $package"
        case "$name" in
            "$PRIMARY_KERNEL") kernel_version=$version ;;
            "${PRIMARY_KERNEL}-nvidia-open") nvidia_version=$version ;;
            *) die "unexpected custom kernel package name: $name ($package)" ;;
        esac
    done
    [[ $kernel_version == "$nvidia_version" ]] || die "custom kernel and NVIDIA package versions differ: $kernel_version / $nvidia_version"
}

install_custom_kernel_packages() {
    section "Installing custom kernel packages"
    shopt -s nullglob
    local packages=("$INSTALL_STATE"/custom-kernel/*.pkg.tar.zst)
    shopt -u nullglob
    ((${#packages[@]} > 0)) || die "no custom kernel packages copied into target"
    retry pacman -U --noconfirm "${packages[@]}"
}
