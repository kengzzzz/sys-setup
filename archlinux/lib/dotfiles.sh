#!/usr/bin/env bash

ARCH_STOW_PACKAGES=(
    Thunar
    autostart
    broadcast-linux
    claude
    codex
    desktop
    fastfetch
    fontconfig
    gnupg
    gtk-3.0
    gtk-4.0
    hypr
    hypr-kblayoutd
    icons
    kitty
    mpv
    muse
    nwg-look
    pipewire
    qalculate
    qt6ct
    quickshell
    ssh
    uwsm
    vesktop
    zed
    zshrc
)

DEFAULT_BROWSER_DESKTOP=brave-origin.desktop

configure_makepkg() {
    section "Configuring makepkg.conf"
    sed -i 's/ debug / !debug /g' /etc/makepkg.conf
    sed -i 's|^#BUILDDIR=/tmp/makepkg|BUILDDIR=/tmp/makepkg|g' /etc/makepkg.conf
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
    local user_home group ssh_dir
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    group=$(id -gn "$INSTALL_USER")
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"
    ssh_dir="$user_home/.ssh"
    printf 'Plug in your YubiKey/security key for dotfiles SSH access, then press Enter.\n'
    read -r
    install -d -m700 -o "$INSTALL_USER" -g "$group" "$ssh_dir"
    ssh-keyscan -H github.com >>"$ssh_dir/known_hosts" 2>/dev/null || true
    chmod 644 "$ssh_dir/known_hosts"
    # A new chroot user has no active seat ACL for the live ISO's FIDO device.
    (
        cd "$ssh_dir" || exit
        if [[ ! -f id_ed25519_sk ]]; then
            ssh-keygen -K
            shopt -s nullglob
            keys=()
            for key in id_ed25519_sk_rk*; do
                [[ $key == *.pub ]] || keys+=("$key")
            done
            ((${#keys[@]} == 1)) || {
                printf "Expected one resident Ed25519 key; select a key as ~/.ssh/id_ed25519_sk before continuing\n" >&2
                exit 1
            }
            cp -p "${keys[0]}" id_ed25519_sk
            cp -p "${keys[0]}.pub" id_ed25519_sk.pub
        fi
        chmod 600 id_ed25519_sk
    )
    chown -R "$INSTALL_USER:$group" "$ssh_dir"
}

clone_dotfiles() {
    section "Cloning dotfiles"
    local user_home group ssh_command
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    group=$(id -gn "$INSTALL_USER")
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"
    printf -v ssh_command '%q ' ssh -F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes \
        -o "UserKnownHostsFile=$user_home/.ssh/known_hosts" -i "$user_home/.ssh/id_ed25519_sk"
    if [[ ! -d $DOTFILES_DIR/.git ]]; then
        # Sign as root while there is no logged-in target user to access FIDO.
        GIT_SSH_COMMAND=$ssh_command git clone --branch "$DOTFILES_BRANCH" -- "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi
    chown -R "$INSTALL_USER:$group" "$DOTFILES_DIR"
}

install_zsh_plugins() {
    section "Installing Zsh plugins"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        mkdir -p "$ZSH_CUSTOM/plugins"
        for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
            if [[ ! -d $ZSH_CUSTOM/plugins/$plugin/.git ]]; then
                git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$ZSH_CUSTOM/plugins/$plugin"
            fi
        done
    '
}

stow_dotfiles() {
    section "Linking dotfiles"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        cd "$1"
        shift
        for package in "$@"; do
            [[ -d $package ]] || { printf "missing dotfiles package: %s\n" "$package" >&2; exit 1; }
        done
        rm -f ~/.zshrc
        # keep stow folding at icons/default so app-installed icon dirs stay out of the repo
        mkdir -p ~/.local/share/icons ~/.config/qalculate
        install -d -m 700 ~/.gnupg
        stow -n -v "$@"
        stow -R -v "$@"
        # Extra plain preferences use file links so newly generated files stay
        # in HOME, outside Git. Older dotfiles checkouts may lack this package.
        if [[ -d workstation ]]; then
            stow -n -v --no-folding workstation
            stow -R -v --no-folding workstation
        fi
    ' bash "$DOTFILES_DIR" "${ARCH_STOW_PACKAGES[@]}"
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

apply_workstation_preferences() {
    [[ -f $DOTFILES_DIR/workstation/.config/workstation/dconf.ini ]] || return 0
    section "Applying desktop preferences from private dotfiles"
    local user_home script_dir
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"
    # The installer lives under /root, which the target user cannot traverse.
    script_dir=$(mktemp -d)
    chmod 755 "$script_dir"
    install -m644 "$SCRIPT_DIR/scripts/workstation-preferences.py" "$script_dir/"
    runuser -u "$INSTALL_USER" -- env -u XDG_RUNTIME_DIR HOME="$user_home" XDG_CONFIG_HOME="$user_home/.config" \
        dbus-run-session -- python "$script_dir/workstation-preferences.py" \
        apply --home "$user_home" --dotfiles "$DOTFILES_DIR"
    rm -rf "$script_dir"
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

    install -Dm644 "$dot_dir/etc/greetd/config.toml" /etc/greetd/config.toml
    install -Dm644 "$dot_dir/etc/tuigreet/config.toml" /etc/tuigreet/config.toml
    mkdir -p /usr/share/wayland-sessions /usr/local/bin
    cp -r "$dot_dir/usr/share/wayland-sessions/." /usr/share/wayland-sessions/

    if [[ -f $dot_dir/usr/bin/hyprland-quiet ]]; then
        install -m 755 "$dot_dir/usr/bin/hyprland-quiet" /usr/local/bin/hyprland-quiet
    fi

    chmod 644 /usr/share/wayland-sessions/*.desktop
    seed_greeter_session
}

seed_greeter_session() {
    local session=/usr/share/wayland-sessions/hyprland-uwsm.desktop
    local cache_dir=/var/cache/tuigreet

    [[ -f $session ]] || die "greeter session not found: $session"
    [[ ! -e $cache_dir/lastsession-path ]] || return 0
    # tuigreet otherwise starts the first session, plain Hyprland, which
    # bypasses uwsm's graphical-session.target and ~/.config/uwsm/env.
    install -d -o greeter -g greeter "$cache_dir"
    printf '%s' "$session" >"$cache_dir/lastsession-path"
    chown greeter:greeter "$cache_dir/lastsession-path"
}

run_dotfiles_install() {
    [[ ${ENABLE_DOTFILES:-1} == 1 ]] || {
        warn "dotfiles install disabled"
        return 0
    }

    install_oh_my_zsh
    prepare_user_ssh
    clone_dotfiles
    install_zsh_plugins
    stow_dotfiles
    configure_default_browser
    install_dotfiles_system_files
    restore_lact_config
    enable_target_user_services
    apply_workstation_preferences
}
