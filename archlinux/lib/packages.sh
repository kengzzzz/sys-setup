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
    greetd greetd-tuigreet hyprland swaybg swaylock swayimg hypridle hyprsunset
    quickshell uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk gnome-keyring seahorse
    qt5ct qt6ct papirus-icon-theme thunar gvfs tumbler kitty cliphist grim slurp swappy hyprpicker
    pipewire pipewire-pulse pipewire-jack wireplumber pavucontrol blueman brave-origin-bin mpv playerctl qalculate-gtk
    nvidia-utils lib32-nvidia-utils egl-gbm libva-nvidia-driver cpupower
    zsh zsh-completions zsh-syntax-highlighting imagemagick tesseract tesseract-data-eng tesseract-data-tha ffmpegthumbnailer
    ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-common ttf-ibm-plex ttf-cascadia-code ttf-material-symbols-variable fzf pkgfile
    eza fastfetch freerdp jq bc cpio ripgrep docker bubblewrap gpu-screen-recorder
    pacman-contrib cachyos-settings socat steam stow tailscale docker-compose
    paru
    docker-buildx accountsservice python-dbus zed nwg-look pam-u2f
    networkmanager lact fwupd yubikey-manager wlr-randr openai-codex zenity
    cava claude-code ddcutil mission-center wine clang cmake
    edk2-shell sbctl sbsigntools
)

AUR_PACKAGES=(
    tokyonight-gtk-theme-git hypr-kblayoutd-bin catppuccin-cursors-mocha
    broadcast-linux-bin tiny-poe2smoother-bin python-pywal vesktop
)

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

sync_pacman() {
    section "Syncing package databases"
    retry pacman -Syu --noconfirm
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

install_aur_packages_as_user() {
    section "Installing AUR packages (sudo may request the new user's password)"
    configure_makepkg
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        command -v paru >/dev/null 2>&1 || {
            printf "paru not found; expected it from the CachyOS repo\n" >&2
            exit 1
        }
        paru -S --noconfirm --needed "$@"
    ' bash "${AUR_PACKAGES[@]}"
}

build_custom_kernel_packages() {
    [[ ${CUSTOM_KERNEL_BUILD:-1} == 1 ]] || return 0
    [[ -z ${CUSTOM_KERNEL_PACKAGES_DIR:-} ]] || return 0

    section "Building custom kernel packages"
    local repo_root
    repo_root=$(cd "$SCRIPT_DIR/.." && pwd)
    local kernel_dir="$repo_root/$CUSTOM_KERNEL_DIR"
    [[ -d $kernel_dir ]] || die "custom kernel directory not found: $kernel_dir"

    retry systemctl start docker
    (
        cd "$kernel_dir" || exit
        retry docker compose run --rm --build kernel-builder
    )
    CUSTOM_KERNEL_PACKAGES_DIR="$kernel_dir/out/kernel"
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

copy_custom_kernel_packages_to_target() {
    section "Copying custom kernel packages"
    local target_dir=/mnt/root/sys-setup-install/custom-kernel
    mkdir -p "$target_dir"
    cp -f "${CUSTOM_KERNEL_PACKAGES[@]}" "$target_dir/"
}

install_custom_kernel_packages() {
    section "Installing custom kernel packages"
    shopt -s nullglob
    local packages=(/root/sys-setup-install/custom-kernel/*.pkg.tar.zst)
    shopt -u nullglob
    ((${#packages[@]} > 0)) || die "no custom kernel packages copied into target"
    retry pacman -U --noconfirm "${packages[@]}"
}
