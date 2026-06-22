#!/usr/bin/env bash

BASE_PACKAGES=(
    base
    base-devel
    linux-firmware
    git
    openssh
    nano
    pcsclite
    libfido2
    ccid
    sudo
    xfsprogs
)

OFFICIAL_PACKAGES=(
    gnu-free-fonts noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
    greetd greetd-regreet cage hyprland swaybg swaylock swayidle swayimg mate-polkit
    waybar swaync xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    qt5ct qt6ct papirus-icon-theme thunar gvfs tumbler kitty cliphist grim slurp swappy hyprpicker
    pipewire pipewire-pulse wireplumber pavucontrol blueman librewolf-bin mpv playerctl
    nvidia-utils lib32-nvidia-utils egl-gbm libva-nvidia-driver cpupower
    zsh zsh-completions zsh-syntax-highlighting imagemagick tesseract tesseract-data-eng tesseract-data-tha ffmpegthumbnailer
    ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-common ttf-ibm-plex
    btop eza fastfetch wakeonlan freerdp bc cmake cpio docker bubblewrap drawing gpu-screen-recorder
    pacman-contrib python-pywal rofi sbctl sbsigntools socat steam stow tailscale docker-compose
    docker-buildx accountsservice python-dbus vscodium nwg-look gpu-screen-recorder-ui vesktop pam-u2f
)

setup_cachyos_repo() {
    section "Setting up CachyOS repository"
    local work_dir=/tmp/cachyos-repo-bootstrap
    rm -rf "$work_dir"
    mkdir -p "$work_dir"
    retry curl -L https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$work_dir/cachyos-repo.tar.xz"
    run tar -C "$work_dir" -xf "$work_dir/cachyos-repo.tar.xz"
    (
        cd "$work_dir/cachyos-repo"
        retry ./cachyos-repo.sh
    )
}

sync_pacman() {
    section "Syncing package databases"
    retry pacman -Sy --noconfirm
}

pacstrap_base() {
    section "Installing base system"
    retry pacstrap -K /mnt --cachedir /mnt/var/cache/pacman/pkg --noconfirm \
        "${BASE_PACKAGES[@]}" "$FALLBACK_KERNEL" "$FALLBACK_KERNEL_HEADERS" "$FALLBACK_NVIDIA_PACKAGE"
}

generate_fstab() {
    section "Generating fstab"
    genfstab -U /mnt >>/mnt/etc/fstab
}

install_official_packages() {
    section "Installing official packages"
    retry pacman -S --noconfirm --needed "${OFFICIAL_PACKAGES[@]}"
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
        cd "$kernel_dir"
        retry docker compose run --rm kernel-builder
    )
    CUSTOM_KERNEL_PACKAGES_DIR="$kernel_dir/out"
}

validate_custom_kernel_packages() {
    [[ -n ${CUSTOM_KERNEL_PACKAGES_DIR:-} ]] || die "custom kernel packages directory is required"
    [[ -d $CUSTOM_KERNEL_PACKAGES_DIR ]] || die "custom kernel packages directory not found: $CUSTOM_KERNEL_PACKAGES_DIR"

    shopt -s nullglob
    CUSTOM_KERNEL_PACKAGES=("$CUSTOM_KERNEL_PACKAGES_DIR"/"${PRIMARY_KERNEL}"*.pkg.tar.zst)
    shopt -u nullglob

    ((${#CUSTOM_KERNEL_PACKAGES[@]} > 0)) || die "no custom kernel packages found in $CUSTOM_KERNEL_PACKAGES_DIR"
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
    retry pacman -U --noconfirm --overwrite '*' "${packages[@]}"
}
