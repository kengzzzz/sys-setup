#!/usr/bin/env bash

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
        git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" 2>/dev/null || true
    '
}

stow_dotfiles() {
    section "Linking dotfiles"
    runuser -u "$INSTALL_USER" -- bash -lc "
        set -euo pipefail
        cd '$DOTFILES_DIR'
        rm -f ~/.zshrc
        # keep stow folding at icons/default so app-installed icon dirs stay out of the repo
        mkdir -p ~/.local/share/icons
        for dir in *; do
            [[ -d \"\$dir\" ]] || continue
            case \"\$dir\" in
                utils|etc|usr) continue ;;
            esac
            stow -D \"\$dir\" 2>/dev/null || true
            stow -v \"\$dir\"
        done
    "
}

configure_default_browser() {
    section "Configuring default browser"
    runuser -u "$INSTALL_USER" -- bash -lc '
        set -euo pipefail
        xdg-settings set default-web-browser helium.desktop || true
        xdg-mime default helium.desktop \
            text/html \
            application/xhtml+xml \
            x-scheme-handler/http \
            x-scheme-handler/https \
            x-scheme-handler/about \
            x-scheme-handler/unknown
    '
}

install_dotfiles_system_files() {
    section "Installing dotfiles system files"
    local dot_dir=$DOTFILES_DIR

    if [[ -f $dot_dir/utils/cert/KengPi_RootCA.crt ]]; then
        install -m 644 "$dot_dir/utils/cert/KengPi_RootCA.crt" /etc/ca-certificates/trust-source/anchors/KengPi_RootCA.crt
        update-ca-trust
    fi

    mkdir -p /usr/share/backgrounds /usr/share/wayland-sessions /usr/local/bin
    cp -r "$dot_dir/etc/greetd/." /etc/greetd/ 2>/dev/null || true
    cp -r "$dot_dir/etc/usr/share/backgrounds/." /usr/share/backgrounds/ 2>/dev/null || true
    cp -r "$dot_dir/usr/share/wayland-sessions/." /usr/share/wayland-sessions/ 2>/dev/null || true

    if [[ -f $dot_dir/usr/bin/hyprland-quiet ]]; then
        install -m 755 "$dot_dir/usr/bin/hyprland-quiet" /usr/local/bin/hyprland-quiet
    fi

    chmod 644 /etc/greetd/regreet.toml 2>/dev/null || true
    chmod 644 /usr/share/backgrounds/wallpaper.jpg 2>/dev/null || true
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
}
