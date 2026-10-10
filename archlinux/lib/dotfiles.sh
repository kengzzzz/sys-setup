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

install_user_ssh_keys() {
    section "Installing SSH keys"
    local user_home group ssh_dir dir name
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    group=$(id -gn "$INSTALL_USER")
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"
    ssh_dir="$user_home/.ssh"
    install -d -m700 -o "$INSTALL_USER" -g "$group" "$ssh_dir"
    if [[ -f $INSTALL_STATE/known_hosts ]]; then
        install -m644 -o "$INSTALL_USER" -g "$group" "$INSTALL_STATE/known_hosts" "$ssh_dir/known_hosts"
    fi
    for dir in "$INSTALL_STATE"/yubikeys/*/; do
        [[ -f $dir/ssh_name ]] || continue
        name=$(<"$dir/ssh_name")
        install -m600 -o "$INSTALL_USER" -g "$group" "$dir/ssh/key" "$ssh_dir/$name"
        install -m644 -o "$INSTALL_USER" -g "$group" "$dir/ssh/key.pub" "$ssh_dir/$name.pub"
    done
}

install_dotfiles_checkout() {
    section "Installing dotfiles checkout"
    local group
    group=$(id -gn "$INSTALL_USER")
    if [[ ! -d $DOTFILES_DIR/.git ]]; then
        [[ -d $INSTALL_STATE/dotfiles/.git ]] || die "dotfiles were not cloned before installation"
        cp -a "$INSTALL_STATE/dotfiles" "$DOTFILES_DIR"
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
        packages=()
        for package in "$@"; do
            if [[ -d $package ]]; then
                packages+=("$package")
            else
                printf "warning: dotfiles have no %s package; skipped\n" "$package" >&2
            fi
        done
        set -- "${packages[@]}"
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

    local proton_settings=usr/share/steam/compatibilitytools.d/proton-cachyos-slr/user_settings.py
    if [[ -f $dot_dir/$proton_settings ]]; then
        install -Dm644 "$dot_dir/$proton_settings" "/$proton_settings"
    fi

    if [[ -f $dot_dir/etc/tmpfiles.d/x3d-cache.conf ]]; then
        install -Dm644 "$dot_dir/etc/tmpfiles.d/x3d-cache.conf" /etc/tmpfiles.d/x3d-cache.conf
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

    run_step oh-my-zsh install_oh_my_zsh
    run_step dotfiles-checkout install_dotfiles_checkout
    run_step zsh-plugins install_zsh_plugins
    run_step stow stow_dotfiles
    run_step default-browser configure_default_browser
    run_step dotfiles-system-files install_dotfiles_system_files
    run_step lact restore_lact_config
    run_step user-services enable_target_user_services
    run_step workstation-preferences apply_workstation_preferences
}
