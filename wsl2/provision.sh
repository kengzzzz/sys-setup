#!/usr/bin/env bash
set -Eeuo pipefail

# In-distro provisioner for a fresh WSL2 Debian. Run as root inside the distro
# (wsl2.ps1 invokes it after creating the user). Installs the zsh shell
# environment and, when the forwarded Windows ssh-agent can reach GitHub, clones
# and stows the private dotfiles. Reuses the helpers from the Arch installer.

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Defaults (overridable via flags).
INSTALL_USER=${SUDO_USER:-}
WIN_USER=''
NPIPERELAY_PATH=''
DOTFILES_REPO='git@github.com:kengzzzz/dotfiles.git'
DOTFILES_BRANCH='main'
ENABLE_DOTFILES=1
export DRY_RUN=0

# Populated by resolve_defaults.
USER_HOME=''
USER_UID=''
DOTFILES_DIR=''

usage() {
    cat <<'EOF'
Usage: provision.sh [options]

Provisions a fresh WSL2 Debian: zsh + oh-my-zsh (the robbyrussell theme and the
plugins the dotfiles expect) plus the CLI tools the dotfiles' aliases use, and
(if the forwarded Windows ssh-agent can authenticate to GitHub) clones and stows
the private dotfiles. Must run as root inside the distro.

Options:
  --user NAME              target UNIX user (default: $SUDO_USER)
  --win-user NAME          Windows username under /mnt/c/Users (default: auto-detect)
  --npiperelay-path PATH   WSL path to npiperelay.exe
                           (default: /mnt/c/Users/<win-user>/npiperelay.exe)
  --dotfiles-repo URL      dotfiles git remote (default: git@github.com:kengzzzz/dotfiles.git)
  --dotfiles-branch NAME   dotfiles branch (default: main)
  --no-dotfiles            skip the SSH bridge, clone, and stow steps
  --dry-run                print actions without executing them
  -h, --help               show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user) INSTALL_USER=$2; shift 2 ;;
            --win-user) WIN_USER=$2; shift 2 ;;
            --npiperelay-path) NPIPERELAY_PATH=$2; shift 2 ;;
            --dotfiles-repo) DOTFILES_REPO=$2; shift 2 ;;
            --dotfiles-branch) DOTFILES_BRANCH=$2; shift 2 ;;
            --no-dotfiles) ENABLE_DOTFILES=0; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

detect_win_user() {
    local dir base first=''
    for dir in /mnt/c/Users/*/; do
        [[ -d $dir ]] || continue
        base=${dir%/}
        base=${base##*/}
        case $base in
            Public|Default|'Default User'|'All Users'|defaultuser0) continue ;;
        esac
        [[ -z $first ]] && first=$base
        if [[ -f "${dir}npiperelay.exe" ]]; then
            printf '%s\n' "$base"
            return 0
        fi
    done
    [[ -n $first ]] && printf '%s\n' "$first"
}

resolve_defaults() {
    USER_HOME=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    [[ -n $USER_HOME ]] || USER_HOME="/home/$INSTALL_USER"
    USER_UID=$(id -u "$INSTALL_USER" 2>/dev/null || true)
    DOTFILES_DIR="$USER_HOME/dotfiles"

    [[ -n $WIN_USER ]] || WIN_USER=$(detect_win_user || true)

    if [[ -z $NPIPERELAY_PATH ]]; then
        if [[ -n $WIN_USER ]]; then
            NPIPERELAY_PATH="/mnt/c/Users/$WIN_USER/npiperelay.exe"
        else
            NPIPERELAY_PATH="/mnt/c/npiperelay.exe"
        fi
    fi
}

# Run a login shell command as the target user (dry-run aware).
as_user() {
    run runuser -u "$INSTALL_USER" -- bash -lc "$1"
}

# Same, but with the user's systemd/D-Bus session env so `systemctl --user` works.
as_user_systemd() {
    run runuser -u "$INSTALL_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/${USER_UID:-0}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_UID:-0}/bus" \
        bash -lc "$1"
}

print_summary() {
    section "WSL2 Debian provisioning"
    log "user:            $INSTALL_USER ($USER_HOME)"
    log "windows user:    ${WIN_USER:-<unknown>}"
    log "npiperelay:      $NPIPERELAY_PATH"
    log "dotfiles:        $([[ $ENABLE_DOTFILES == 1 ]] && echo "$DOTFILES_REPO ($DOTFILES_BRANCH)" || echo disabled)"
    log "dry-run:         $([[ $DRY_RUN == 1 ]] && echo yes || echo no)"
}

install_packages() {
    section "Installing packages"
    export DEBIAN_FRONTEND=noninteractive
    retry apt-get update
    retry apt-get install -y --no-install-recommends \
        zsh git stow build-essential curl ca-certificates locales socat sudo gnupg
}

configure_locale() {
    section "Configuring locale (en_US.UTF-8)"
    run sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    run locale-gen
    run update-locale LANG=en_US.UTF-8
}

enable_user_systemd() {
    section "Enabling the user systemd manager"
    [[ -d /run/systemd/system ]] || warn "systemd does not appear to be running; ensure [boot] systemd=true in /etc/wsl.conf"
    run loginctl enable-linger "$INSTALL_USER"
}

install_shell_framework() {
    # The dotfiles set ZSH_THEME=robbyrussell (a built-in theme, no install
    # needed) and load these three custom plugins; clone exactly those so the
    # prompt loads without "plugin not found" warnings.
    section "Installing Oh My Zsh and the zsh plugins the dotfiles expect"
    as_user '
        set -euo pipefail
        if [[ ! -d ~/.oh-my-zsh ]]; then
            git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
        fi
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        mkdir -p "$ZSH_CUSTOM/plugins"
        [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] \
            || git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        [[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] \
            || git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        [[ -d "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" ]] \
            || git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"
    '
}

install_cli_tools() {
    # The dotfiles aliases assume these exist: ls/ll/lt -> eza, ff -> fastfetch
    # (also run from 30-autostart on every interactive shell), v/vim -> nano.
    # Install them so the aliases work instead of erroring "command not found".
    section "Installing CLI tools the dotfiles aliases use (eza, fastfetch, nano)"
    export DEBIAN_FRONTEND=noninteractive
    retry apt-get install -y --no-install-recommends nano
    install_eza
    install_fastfetch
}

# eza landed in Debian 13 (trixie); on older releases fall back to the upstream
# apt repo. Not all of this is run() wrapped, so short-circuit in dry-run.
install_eza() {
    if [[ ${DRY_RUN:-0} == 1 ]]; then
        run apt-get install -y --no-install-recommends eza
        return 0
    fi
    if apt-get install -y --no-install-recommends eza 2>/dev/null; then
        log "installed eza from apt"
        return 0
    fi
    warn "eza not in this release's repos; adding deb.gierens.de"
    install -d -m 0755 /etc/apt/keyrings
    if curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg; then
        chmod 0644 /etc/apt/keyrings/gierens.gpg
        printf 'deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main\n' \
            >/etc/apt/sources.list.d/gierens.list
        chmod 0644 /etc/apt/sources.list.d/gierens.list
        apt-get update && apt-get install -y eza \
            && { log "installed eza from deb.gierens.de"; return 0; }
    fi
    warn "could not install eza; the ls/ll/lt aliases will be inactive"
}

# fastfetch is in Debian 13 (trixie); on older releases fetch the upstream .deb.
install_fastfetch() {
    if [[ ${DRY_RUN:-0} == 1 ]]; then
        run apt-get install -y --no-install-recommends fastfetch
        return 0
    fi
    if apt-get install -y --no-install-recommends fastfetch 2>/dev/null; then
        log "installed fastfetch from apt"
        return 0
    fi
    warn "fastfetch not in this release's repos; fetching the upstream .deb"
    local arch deb tmp
    arch=$(dpkg --print-architecture)
    case $arch in
        amd64) deb=fastfetch-linux-amd64.deb ;;
        arm64) deb=fastfetch-linux-aarch64.deb ;;
        *) warn "no fastfetch .deb for $arch; the ff alias/banner will be inactive"; return 0 ;;
    esac
    tmp=$(mktemp -d)
    if curl -fsSL -o "$tmp/$deb" \
        "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/$deb" \
        && apt-get install -y "$tmp/$deb"; then
        log "installed fastfetch from the upstream .deb"
    else
        warn "could not install fastfetch; the ff alias/banner will be inactive"
    fi
    rm -rf "$tmp"
}

start_bootstrap_bridge() {
    section "Starting temporary Windows ssh-agent bridge"
    if [[ ! -f $NPIPERELAY_PATH ]]; then
        warn "npiperelay.exe not found at $NPIPERELAY_PATH"
        warn "  wsl2.ps1 downloads it on the Windows side; the bridge will fail without it"
    fi
    as_user '
        set -euo pipefail
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || true
        chmod 644 ~/.ssh/known_hosts 2>/dev/null || true
    '
    local exec_arg="EXEC:$NPIPERELAY_PATH -ei -s //./pipe/openssh-ssh-agent,nofork"
    as_user_systemd "
        systemctl --user stop wsl-ssh-bridge 2>/dev/null || true
        systemctl --user reset-failed wsl-ssh-bridge 2>/dev/null || true
        systemd-run --user --collect --unit wsl-ssh-bridge -- \
            /usr/bin/socat UNIX-LISTEN:\$HOME/.ssh/agent.sock,fork '$exec_arg'
        for _ in 1 2 3 4 5; do [ -S \$HOME/.ssh/agent.sock ] && break; sleep 1; done
    "
}

github_ssh_ok() {
    [[ ${DRY_RUN:-0} == 1 ]] && return 0
    runuser -u "$INSTALL_USER" -- bash -lc '
        out=$(SSH_AUTH_SOCK="$HOME/.ssh/agent.sock" \
            ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 || true)
        printf "%s\n" "$out" | grep -q "successfully authenticated"
    '
}

clone_dotfiles() {
    section "Cloning dotfiles"
    as_user "
        set -euo pipefail
        export SSH_AUTH_SOCK=\$HOME/.ssh/agent.sock
        if [[ ! -d '$DOTFILES_DIR/.git' ]]; then
            git clone --branch '$DOTFILES_BRANCH' '$DOTFILES_REPO' '$DOTFILES_DIR'
        fi
    "
}

stow_dotfiles() {
    section "Linking dotfiles with stow"
    as_user "
        set -euo pipefail
        cd '$DOTFILES_DIR'
        rm -f ~/.zshrc
        for dir in */; do
            dir=\${dir%/}
            [[ -d \"\$dir\" ]] || continue
            case \"\$dir\" in
                utils|etc|usr) continue ;;
            esac
            stow -D \"\$dir\" 2>/dev/null || true
            stow -v \"\$dir\"
        done
    "
}

install_agent_service() {
    section "Installing the persistent ssh-agent bridge service"
    local unit_dir="$USER_HOME/.config/systemd/user"
    local unit="$unit_dir/wsl-ssh-agent.service"
    local group
    group=$(id -gn "$INSTALL_USER" 2>/dev/null || echo "$INSTALL_USER")

    if [[ ${DRY_RUN:-0} == 1 ]]; then
        log "[dry-run] write $unit (npiperelay: $NPIPERELAY_PATH)"
    elif [[ -e $unit ]]; then
        log "wsl-ssh-agent.service already provided by dotfiles; leaving it in place"
        warn "verify its ExecStart points at $NPIPERELAY_PATH for this machine"
    else
        install -d -o "$INSTALL_USER" -g "$group" "$unit_dir"
        cat >"$unit" <<EOF
[Unit]
Description=Forward Windows ssh-agent to WSL
After=network.target

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%h/.ssh/agent.sock
ExecStartPre=-/bin/rm -f %h/.ssh/agent.sock
ExecStart=/usr/bin/socat UNIX-LISTEN:%h/.ssh/agent.sock,fork EXEC:"$NPIPERELAY_PATH -ei -s //./pipe/openssh-ssh-agent",nofork
Restart=on-failure

[Install]
WantedBy=default.target
EOF
        chown "$INSTALL_USER:$group" "$unit"
    fi

    as_user_systemd '
        systemctl --user stop wsl-ssh-bridge 2>/dev/null || true
        systemctl --user reset-failed wsl-ssh-bridge 2>/dev/null || true
        systemctl --user daemon-reload
        systemctl --user enable --now wsl-ssh-agent.service
    '
}

# The dotfiles' 00-init points SSH_AUTH_SOCK at $XDG_RUNTIME_DIR/ssh-agent.socket
# (the Arch/desktop agent). On WSL the forwarded agent lives at ~/.ssh/agent.sock,
# so drop a machine-local override into ~/.zshrc_custom, which the dotfiles' .zshrc
# sources last (and which lives in $HOME, never inside the stow tree).
write_zsh_local_overrides() {
    section "Writing WSL zsh overrides (~/.zshrc_custom)"
    local f="$USER_HOME/.zshrc_custom"
    local group
    group=$(id -gn "$INSTALL_USER" 2>/dev/null || echo "$INSTALL_USER")
    if [[ ${DRY_RUN:-0} == 1 ]]; then
        log "[dry-run] write $f (SSH_AUTH_SOCK -> \$HOME/.ssh/agent.sock)"
        return 0
    fi
    cat >"$f" <<'EOF'
# Machine-local zsh overrides for WSL2 (written by sys-setup wsl2/provision.sh).
# Sourced last by the dotfiles' ~/.zshrc, so it wins over ~/.config/zshrc/00-init.

# The forwarded Windows ssh-agent bridge (wsl-ssh-agent.service) listens here,
# not at $XDG_RUNTIME_DIR/ssh-agent.socket (the Arch/desktop path in 00-init).
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
EOF
    chown "$INSTALL_USER:$group" "$f"
}

run_dotfiles_install() {
    start_bootstrap_bridge
    if github_ssh_ok; then
        log "GitHub SSH reachable over the forwarded agent"
        clone_dotfiles
        stow_dotfiles
        write_zsh_local_overrides
        install_agent_service
    else
        warn "GitHub SSH is not available over the forwarded agent; skipping dotfiles."
        warn "  1. plug in your YubiKey"
        warn "  2. in Windows PowerShell: Start-Service ssh-agent; ssh-add -K"
        warn "  3. re-run this provisioner (or wsl2.ps1)"
    fi
}

set_default_shell() {
    section "Setting zsh as the default shell"
    local zsh_bin
    zsh_bin=$(command -v zsh || echo /usr/bin/zsh)
    run chsh -s "$zsh_bin" "$INSTALL_USER"
}

main() {
    parse_args "$@"
    [[ -n $INSTALL_USER ]] || die "no target user; pass --user NAME"
    require_root
    resolve_defaults
    print_summary

    install_packages
    configure_locale
    enable_user_systemd
    install_shell_framework
    install_cli_tools

    if [[ $ENABLE_DOTFILES == 1 ]]; then
        run_dotfiles_install
    else
        warn "dotfiles disabled (--no-dotfiles)"
    fi

    set_default_shell

    section "Done"
    log "Open the distro with 'wsl' — zsh (robbyrussell prompt) should load."
}

main "$@"
