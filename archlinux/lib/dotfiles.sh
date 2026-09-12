#!/usr/bin/env bash

ARCH_STOW_PACKAGES=(
    Thunar
    applications
    autostart
    btop
    codex
    desktop
    fastfetch
    fontconfig
    gpu-screen-recorder
    gtk-3.0
    gtk-4.0
    hypr
    icons
    kitty
    muse
    nwg-look
    pipewire
    qt6ct
    quickshell
    ssh
    swaylock
    uwsm
    vesktop
    zshrc
)

DEFAULT_BROWSER_DESKTOP=brave-origin.desktop

configure_makepkg() {
    section "Configuring makepkg.conf"
    sed -i 's/ debug / !debug /g' /etc/makepkg.conf
    sed -i 's|^#BUILDDIR=/tmp/makepkg|BUILDDIR=/tmp/makepkg|g' /etc/makepkg.conf
}

install_aur_packages_as_user() {
    section "Installing AUR packages"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        command -v paru >/dev/null 2>&1 || {
            printf "paru not found; expected it from the cachyos repo\n" >&2
            exit 1
        }
        paru -S --noconfirm --needed tokyonight-gtk-theme-git hypr-kblayoutd-bin catppuccin-cursors-mocha
    '
}

install_oh_my_zsh() {
    section "Installing Oh My Zsh"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        if [[ ! -d ~/.oh-my-zsh ]]; then
            git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
        fi
        if [[ ! -e ~/.zshrc ]]; then
            cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
        fi
    '
}

prepare_user_ssh() {
    section "Preparing user SSH keys"
    printf 'Plug in your YubiKey/security key for dotfiles SSH access, then press Enter.\n'
    read -r
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
        chmod 644 ~/.ssh/known_hosts
        cd ~/.ssh
        ssh-keygen -K
        rm -f ./*.pub 2>/dev/null || true
        eval "$(ssh-agent -s)" >/dev/null
        find . -maxdepth 1 -type f -name "*_sk*" -print0 | while IFS= read -r -d "" key; do
            ssh-add "$key" 2>/dev/null || true
        done
    '
}

clone_dotfiles() {
    section "Cloning dotfiles"
    runuser -u "$INSTALL_USER" -- bash -lc "
        set -euo pipefail
        if [[ ! -d '$DOTFILES_DIR/.git' ]]; then
            git clone --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$DOTFILES_DIR'
        fi
    "
}

install_zsh_plugins() {
    section "Installing Zsh plugins"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        mkdir -p "$ZSH_CUSTOM/plugins"
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true
    '
}

stow_dotfiles() {
    section "Linking dotfiles"
    local package_list
    printf -v package_list '%q ' "${ARCH_STOW_PACKAGES[@]}"
    runuser -u "$INSTALL_USER" -- bash -lc "
        set -euo pipefail
        cd '$DOTFILES_DIR'
        rm -f ~/.zshrc
        # keep stow folding at icons/default so app-installed icon dirs stay out of the repo
        mkdir -p ~/.local/share/icons
        for package in $package_list; do
            [[ -d \"\$package\" ]] || { printf 'missing dotfiles package: %s\\n' \"\$package\" >&2; exit 1; }
            stow -D \"\$package\" 2>/dev/null || true
            stow -v \"\$package\"
        done
    "
}

configure_default_browser() {
    section "Configuring default browser"
    runuser -u "$INSTALL_USER" -- env DEFAULT_BROWSER_DESKTOP="$DEFAULT_BROWSER_DESKTOP" bash -lc '
        set -euo pipefail
        xdg-settings set default-web-browser "$DEFAULT_BROWSER_DESKTOP" || true
        xdg-mime default "$DEFAULT_BROWSER_DESKTOP" \
            text/html \
            application/xhtml+xml \
            x-scheme-handler/http \
            x-scheme-handler/https \
            x-scheme-handler/about \
            x-scheme-handler/unknown
    '
}

validate_lact_hardware() {
    local config_file=$1
    local sysfs_root=${2:-/sys/bus/pci/devices}
    local gpu_key pci_id subsystem_id pci_address extra vendor device subsystem_vendor subsystem_device
    local actual_vendor actual_device actual_subsystem_vendor actual_subsystem_device device_dir

    gpu_key=$(awk '
        /^gpus:$/ { in_gpus=1; next }
        in_gpus && /^  [^ ]/ {
            sub(/^  /, "")
            sub(/:$/, "")
            print
            exit
        }
    ' "$config_file")
    [[ -n $gpu_key ]] || die "LACT config contains no GPU identity: $config_file"

    IFS=- read -r pci_id subsystem_id pci_address extra <<<"$gpu_key"
    [[ -z ${extra:-} && -n $pci_address ]] || die "unrecognized LACT GPU identity: $gpu_key"
    IFS=: read -r vendor device <<<"$pci_id"
    IFS=: read -r subsystem_vendor subsystem_device <<<"$subsystem_id"
    device_dir="$sysfs_root/$pci_address"
    [[ -d $device_dir ]] || die "LACT GPU is not present at PCI address $pci_address"

    actual_vendor=$(<"$device_dir/vendor")
    actual_device=$(<"$device_dir/device")
    actual_subsystem_vendor=$(<"$device_dir/subsystem_vendor")
    actual_subsystem_device=$(<"$device_dir/subsystem_device")
    actual_vendor=${actual_vendor#0x}
    actual_device=${actual_device#0x}
    actual_subsystem_vendor=${actual_subsystem_vendor#0x}
    actual_subsystem_device=${actual_subsystem_device#0x}

    [[ ${vendor^^}:${device^^}-${subsystem_vendor^^}:${subsystem_device^^} == \
        ${actual_vendor^^}:${actual_device^^}-${actual_subsystem_vendor^^}:${actual_subsystem_device^^} ]] \
        || die "LACT config GPU identity does not match hardware at $pci_address"
}

restore_lact_config() {
    [[ ${RESTORE_LACT_CONFIG:-0} == 1 ]] || return 0
    local source_file="$DOTFILES_DIR/etc/lact/config.yaml"

    section "Restoring hardware-specific LACT configuration"
    [[ -f $source_file ]] || die "LACT snapshot not found: $source_file"
    validate_lact_hardware "$source_file"
    install -Dm644 "$source_file" /etc/lact/config.yaml
}

install_dotfiles_system_files() {
    section "Installing dotfiles system files"
    local dot_dir=$DOTFILES_DIR

    if [[ -f $dot_dir/utils/cert/KengPi_RootCA.crt ]]; then
        install -m 644 "$dot_dir/utils/cert/KengPi_RootCA.crt" /etc/ca-certificates/trust-source/anchors/KengPi_RootCA.crt
        update-ca-trust
    fi

    mkdir -p /etc/tuigreet /usr/share/wayland-sessions /usr/local/bin
    cp -r "$dot_dir/etc/greetd/." /etc/greetd/ 2>/dev/null || true
    cp -r "$dot_dir/etc/tuigreet/." /etc/tuigreet/ 2>/dev/null || true
    cp -r "$dot_dir/usr/share/wayland-sessions/." /usr/share/wayland-sessions/ 2>/dev/null || true

    if [[ -f $dot_dir/usr/bin/hyprland-quiet ]]; then
        install -m 755 "$dot_dir/usr/bin/hyprland-quiet" /usr/local/bin/hyprland-quiet
    fi

    chmod 644 /etc/greetd/config.toml /etc/tuigreet/config.toml 2>/dev/null || true
    chmod 644 /usr/share/wayland-sessions/*.desktop 2>/dev/null || true
}

run_dotfiles_install() {
    [[ ${ENABLE_DOTFILES:-1} == 1 ]] || {
        warn "dotfiles install disabled"
        return 0
    }

    configure_makepkg
    install_aur_packages_as_user
    install_oh_my_zsh
    prepare_user_ssh
    clone_dotfiles
    install_zsh_plugins
    stow_dotfiles
    configure_default_browser
    install_dotfiles_system_files
    restore_lact_config
    enable_target_user_services
}
