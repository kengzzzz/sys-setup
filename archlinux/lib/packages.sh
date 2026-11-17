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
    greetd hyprland swaybg swayimg hypridle hyprsunset
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk gnome-keyring seahorse
    qt6ct papirus-icon-theme thunar mousepad gvfs tumbler kitty grim slurp satty hyprpicker
    pipewire pipewire-pulse pipewire-jack wireplumber pavucontrol blueman brave-origin-bin mpv playerctl qalculate-gtk
    nvidia-utils lib32-nvidia-utils egl-gbm libva-nvidia-driver
    zsh zsh-completions zsh-syntax-highlighting imagemagick ffmpegthumbnailer
    ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-common ttf-ibm-plex ttf-cascadia-code fzf pkgfile
    eza fastfetch freerdp jq bc cpio ripgrep docker bubblewrap gpu-screen-recorder
    pacman-contrib cachyos-settings socat steam proton-cachyos-slr stow tailscale docker-compose
    paru
    docker-buildx accountsservice python python-gobject zed nwg-look vesktop-bin pam-u2f
    networkmanager lact fwupd yubikey-manager openai-codex opencode zenity
    cava claude-code ddcutil btop wine clang cmake rustup nasm
    edk2-shell sbctl sbsigntools
    rsync dconf wl-clipboard xdg-utils which
    rtkit libvirt virt-manager qemu-desktop edk2-ovmf swtpm dnsmasq
    xwayland-satellite passt
)

AUR_PACKAGES=(
    tokyonight-gtk-theme-git hypr-kblayoutd-bin catppuccin-cursors-mocha
    broadcast-linux-bin tiny-poe2smoother-bin
)

LIVE_PACKAGES=(
    git curl rsync arch-install-scripts gptfdisk dosfstools btrfs-progs xfsprogs parted
    docker docker-compose pam-u2f libfido2 openssh yubikey-manager pcsclite ccid efibootmgr
)

INSTALL_SUDOERS=/etc/sudoers.d/00-sys-setup-install

DESKSHELL_RELEASE_URL=https://github.com/kengzzzz/deskshell/releases/latest/download

PATCHED_PACKAGES_RAW=https://raw.githubusercontent.com/kengzzzz/patched-pkgs/main
PATCHED_PACKAGES_RELEASES=https://github.com/kengzzzz/patched-pkgs/releases/download
PATCHED_PACKAGES=(aquamarine egl-wayland2 hyprland freerdp)

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
    local db_dir metadata expected_nvidia available_nvidia deskshell
    validate_custom_kernel_packages
    deskshell=$(deskshell_package "$STATE_DIR/deskshell")
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
    if ! pacman --dbpath "$db_dir" -Up --noconfirm --print-format '%n %v' "$deskshell"; then
        rm -rf "$db_dir"
        die "deskshell dependencies cannot be resolved; disk was left unchanged"
    fi
    rm -rf "$db_dir"
    patched_package_builds "$PATCHED_PACKAGES_DIR" >/dev/null
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

deskshell_package() {
    local dir=$1
    shopt -s nullglob
    local packages=("$dir"/deskshell-[0-9]*-x86_64.pkg.tar.zst)
    shopt -u nullglob
    ((${#packages[@]} == 1)) || die "expected one deskshell package in $dir, found ${#packages[@]}"
    printf '%s\n' "${packages[0]}"
}

# The release must list exactly one package, and its name ends up in a URL and a path.
deskshell_release_entry() {
    local -a entries
    mapfile -t entries < <(grep -E '^[0-9a-f]{64}  deskshell-[0-9][A-Za-z0-9._+:-]*-x86_64\.pkg\.tar\.zst$')
    ((${#entries[@]} == 1)) || die "deskshell SHA256SUMS must list exactly one package, found ${#entries[@]}"
    printf '%s\n' "${entries[0]}"
}

fetch_deskshell_package() {
    section "Downloading deskshell"
    local dir=$STATE_DIR/deskshell sums entry name
    sums=$(curl -fsSL --retry 3 "$DESKSHELL_RELEASE_URL/SHA256SUMS") || die "cannot download the deskshell SHA256SUMS"
    entry=$(deskshell_release_entry <<<"$sums")
    name=${entry##* }
    mkdir -p "$dir"
    if [[ -f $dir/$name ]] && (cd "$dir" && sha256sum -c --quiet <<<"$entry") >/dev/null 2>&1; then
        log "reusing $name"
        return 0
    fi
    rm -f "$dir"/*.pkg.tar.zst "$dir"/*.part
    retry curl -fL --retry 3 -o "$dir/$name.part" "$DESKSHELL_RELEASE_URL/$name"
    mv "$dir/$name.part" "$dir/$name"
    (cd "$dir" && sha256sum -c --quiet <<<"$entry") || {
        rm -f "${dir:?}/$name"
        die "$name does not match the release SHA256SUMS"
    }
    log "verified $name"
}

render_deskshell_greeter_config() {
    local user=$1 source=$2
    grep -qx 'users = .*' "$source" || die "no users line in $source"
    sed "s/^users = .*/users = [\"$user\"]/" "$source"
}

install_deskshell() {
    section "Installing deskshell"
    local package share=/usr/share/deskshell/greetd
    package=$(deskshell_package "$INSTALL_STATE/deskshell")
    retry pacman -U --noconfirm --needed "$package"
    usermod -aG deskshell-power "$INSTALL_USER"

    # The dotfiles replace these with the machine's own greeter files later.
    install -Dm644 "$share/deskshell-greeter.tmpfiles" /etc/tmpfiles.d/deskshell-greeter.conf
    systemd-tmpfiles --create /etc/tmpfiles.d/deskshell-greeter.conf
    install -Dm755 "$share/deskshell-greeter.sh" /etc/greetd/deskshell-greeter.sh
    install -Dm644 "$share/deskshell-hyprland.lua" /etc/greetd/deskshell-hyprland.lua
    install -Dm644 "$share/config.toml" /etc/greetd/config.toml
    install -d /etc/deskshell
    render_deskshell_greeter_config "$INSTALL_USER" "$share/greeter.toml" >/etc/deskshell/greeter.toml
    chmod 644 /etc/deskshell/greeter.toml
}

patched_package_version() {
    (
        set -a
        # shellcheck source=/dev/null
        source "$1"
        printf '%s-%s\n' "$PKGVER" "$PKGREL"
    )
}

patched_package_abi() {
    (
        ABI_PACKAGES=
        # shellcheck source=/dev/null
        source "$1"
        printf '%s\n' "$ABI_PACKAGES"
    )
}

patched_package_builds() {
    local checkout=$1 pkg env version out
    if [[ ! -d $checkout ]]; then
        warn "no patched packages in $checkout; the stock packages stay"
        return 0
    fi
    for pkg in "${PATCHED_PACKAGES[@]}"; do
        env=$checkout/$pkg/package.env
        if [[ ! -f $env ]]; then
            warn "$checkout has no $pkg; the stock package stays"
            continue
        fi
        version=$(patched_package_version "$env")
        out=$checkout/$pkg/dist/$version
        if [[ ! -f $out/SHA256SUMS ]]; then
            warn "$pkg $version was not built; the stock package stays"
            continue
        fi
        printf '%s %s\n' "$pkg" "$out"
    done
}

patched_release_version() {
    local env=$1 pkgver pkgrel
    pkgver=$(sed -n 's/^PKGVER=//p' <<<"$env")
    pkgrel=$(sed -n 's/^PKGREL=//p' <<<"$env")
    [[ $pkgver =~ ^[A-Za-z0-9._+~]+$ && $pkgrel =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    printf '%s-%s\n' "$pkgver" "$pkgrel"
}

# Members must stay inside <pkg>/ and be plain files or directories.
patched_release_tar_ok() {
    local tarball=$1 pkg=$2 member
    [[ -z $(tar -tvf "$tarball" | grep -v '^[-d]') ]] || return 1
    while IFS= read -r member; do
        [[ $member == "$pkg"/* && $member != *..* ]] || return 1
    done < <(tar -tf "$tarball")
}

fetch_patched_package() {
    local dir=$1 pkg=$2 env version tag out work url
    env=$(curl -fsSL --retry 3 "$PATCHED_PACKAGES_RAW/$pkg/package.env") || {
        warn "cannot read $pkg's package.env; the stock package stays"
        return 0
    }
    version=$(patched_release_version "$env") || {
        warn "$pkg's package.env has no usable PKGVER and PKGREL; the stock package stays"
        return 0
    }
    tag=$pkg-$version
    out=$dir/$pkg/dist/$version
    if [[ -f $out/SHA256SUMS ]] && (cd "$out" && sha256sum -c --quiet SHA256SUMS) >/dev/null 2>&1; then
        log "reusing $tag"
        return 0
    fi
    rm -rf "${dir:?}/$pkg"
    work=$(mktemp -d)
    url=$PATCHED_PACKAGES_RELEASES/$tag/$tag.tar
    if ! curl -fsSL --retry 3 -o "$work/$tag.tar.sha256" "$url.sha256" \
        || ! curl -fL --retry 3 -o "$work/$tag.tar" "$url"; then
        warn "no release $tag; the stock $pkg stays"
    elif [[ $(awk '{ print $2 }' "$work/$tag.tar.sha256") != "$tag.tar" ]] \
        || ! (cd "$work" && sha256sum -c --quiet "$tag.tar.sha256"); then
        warn "$tag.tar does not match its checksum; the stock $pkg stays"
    elif ! patched_release_tar_ok "$work/$tag.tar" "$pkg"; then
        warn "$tag.tar holds files outside $pkg/; the stock $pkg stays"
    else
        mkdir -p "$dir"
        tar --no-same-owner -xf "$work/$tag.tar" -C "$dir"
        log "verified $tag"
    fi
    rm -rf "$work"
}

fetch_patched_packages() {
    local dir=$1 pkg
    section "Downloading patched packages"
    for pkg in "${PATCHED_PACKAGES[@]}"; do
        fetch_patched_package "$dir" "$pkg"
    done
}

stage_patched_packages() {
    local checkout=$1 dest=$2 pkg out
    rm -rf "$dest"
    install -d "$dest"
    while read -r pkg out; do
        if ! (cd "$out" && sha256sum -c --quiet SHA256SUMS); then
            warn "$pkg packages in $out do not match their SHA256SUMS; the stock package stays"
            continue
        fi
        install -d "$dest/$pkg"
        cp -f "$out"/*.pkg.tar.zst "$out/build-packages.txt" "$dest/$pkg/"
        cp -f "$checkout/$pkg/package.env" "$dest/$pkg/package.env"
    done < <(patched_package_builds "$checkout")
}

package_info() {
    bsdtar -xOf "$1" .PKGINFO | awk -v key="$2" '$1 == key { sub(/^[^=]*= /, ""); print }'
}

patched_package_problems() {
    local dir=$1 abi built installed file name version
    local -a deps
    for abi in $(patched_package_abi "$dir/package.env"); do
        built=$(awk -v p="$abi" '$1 == p { print $2 }' "$dir/build-packages.txt")
        installed=$(pacman -Q "$abi" 2>/dev/null | cut -d' ' -f2) || installed=
        [[ ${built%-*} == "${installed%-*}" ]] \
            || printf '%s built against %s, the system has %s\n' "$abi" "${built:-none}" "${installed:-none}"
    done
    for file in "$dir"/*.pkg.tar.zst; do
        name=$(package_info "$file" pkgname)
        installed=$(pacman -Q "$name" 2>/dev/null | cut -d' ' -f2) || continue
        version=$(package_info "$file" pkgver)
        [[ ${version%-*} == "${installed%-*}" ]] \
            || printf '%s is %s, the system has %s\n' "$name" "$version" "$installed"
        mapfile -t deps < <(package_info "$file" depend)
        ((${#deps[@]} == 0)) || pacman -T "${deps[@]}" | sed "s/^/$name needs /" || true
    done
}

install_patched_packages() {
    section "Installing patched packages"
    local root=$INSTALL_STATE/patched-packages dir pkg file problems
    local -a packages=()
    shopt -s nullglob
    for dir in "$root"/*/; do
        dir=${dir%/}
        pkg=${dir##*/}
        problems=$(patched_package_problems "$dir")
        if [[ -n $problems ]]; then
            warn "patched $pkg does not fit this system; the stock package stays:"
            printf '  %s\n' "${problems//$'\n'/$'\n'  }" >&2
            continue
        fi
        for file in "$dir"/*.pkg.tar.zst; do
            ! pacman -Q "$(package_info "$file" pkgname)" >/dev/null 2>&1 || packages+=("$file")
        done
    done
    shopt -u nullglob
    if ((${#packages[@]} == 0)); then
        warn "no patched packages to install; the stock packages stay"
        return 0
    fi
    retry pacman -U --noconfirm "${packages[@]}"
}
