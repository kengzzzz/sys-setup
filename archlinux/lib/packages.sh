#!/usr/bin/env bash

BASE_PACKAGES=(
    base
    linux-firmware
    git
    openssh
    nano
    pcsclite
    libfido2
    ccid
    sudo
    xfsprogs
    fakeroot
    binutils
    make
    patch
    pkgconf
    which
)

OFFICIAL_PACKAGES=(
    gnu-free-fonts noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra
    greetd greetd-tuigreet hyprland swaybg swaylock swayimg hypridle mate-polkit
    quickshell uwsm xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    qt5ct qt6ct papirus-icon-theme thunar gvfs tumbler kitty cliphist grim slurp swappy hyprpicker
    pipewire pipewire-pulse pipewire-jack wireplumber pavucontrol blueman brave-origin-bin mpv playerctl qalculate-gtk
    nvidia-utils lib32-nvidia-utils egl-gbm libva-nvidia-driver cpupower
    zsh zsh-completions zsh-syntax-highlighting imagemagick tesseract tesseract-data-eng tesseract-data-tha ffmpegthumbnailer
    ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-common ttf-ibm-plex fzf pkgfile
    btop eza fastfetch freerdp jq bc cpio ripgrep docker bubblewrap gpu-screen-recorder
    pacman-contrib cachyos-settings socat steam stow tailscale docker-compose
    paru
    docker-buildx accountsservice python-dbus zed nwg-look gpu-screen-recorder-ui vesktop-bin pam-u2f
    networkmanager lact fwupd yubikey-manager wlr-randr openai-codex zenity
)

WORKLOAD_PACKAGES=(
    nvidia-container-toolkit
    qemu-user-static
    qemu-user-static-binfmt
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
        "${BASE_PACKAGES[@]}" "$FALLBACK_KERNEL" "$FALLBACK_NVIDIA_PACKAGE"
}

generate_fstab() {
    section "Generating fstab"
    genfstab -U /mnt >>/mnt/etc/fstab
}

install_official_packages() {
    section "Installing official packages"
    local packages=("${OFFICIAL_PACKAGES[@]}")
    if [[ ${ENABLE_WORKLOAD_PACKAGES:-1} == 1 ]]; then
        packages+=("${WORKLOAD_PACKAGES[@]}")
    fi
    retry pacman -S --noconfirm --needed "${packages[@]}"
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
