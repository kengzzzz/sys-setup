#!/usr/bin/env bash

SYSTEM_SERVICES=(
    NetworkManager.service
    systemd-resolved.service
    greetd.service
    pcscd.service
    bluetooth.service
    tailscaled.service
    docker.socket
    lactd.service
    accounts-daemon.service
    systemd-timesyncd.service
)

enable_system_services() {
    section "Enabling services"
    local services=("${SYSTEM_SERVICES[@]}")
    if [[ ${ROOT_FS:-btrfs} == btrfs ]]; then
        systemctl disable fstrim.timer
        services+=(snapper-cleanup.timer btrfs-scrub@-.timer)
    else
        services+=(fstrim.timer xfs_scrub_all.timer)
    fi
    systemctl enable "${services[@]}"
}

configure_container_runtime() {
    [[ ${ENABLE_WORKLOAD_PACKAGES:-1} == 1 ]] || return 0
    section "Configuring NVIDIA Docker runtime"
    nvidia-ctk runtime configure --runtime=docker
}

link_user_unit() {
    local user_home=$1
    local unit=$2
    local target=$3
    local unit_root=${4:-/usr/lib/systemd/user}
    local wants_dir="$user_home/.config/systemd/user/${target}.wants"

    [[ -e $unit_root/$unit ]] || die "user unit not found: $unit_root/$unit"
    install -d "$wants_dir"
    ln -sfn "$unit_root/$unit" "$wants_dir/$unit"
}

enable_target_user_services() {
    section "Enabling user services"
    local user_home group ssh_wants keyboard_wants broadcast_wants
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    group=$(id -gn "$INSTALL_USER")
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"

    ssh_wants="$user_home/.config/systemd/user/sockets.target.wants"
    keyboard_wants="$user_home/.config/systemd/user/graphical-session.target.wants"
    broadcast_wants="$user_home/.config/systemd/user/default.target.wants"
    install -d -o "$INSTALL_USER" -g "$group" \
        "$user_home/.config" \
        "$user_home/.config/systemd" \
        "$user_home/.config/systemd/user" \
        "$ssh_wants" \
        "$keyboard_wants" \
        "$broadcast_wants"
    link_user_unit "$user_home" ssh-agent.socket sockets.target
    link_user_unit "$user_home" hypr-kblayoutd.service graphical-session.target
    link_user_unit "$user_home" hyprsunset.service graphical-session.target
    link_user_unit "$user_home" broadcast-linux.service default.target
    link_user_unit "$user_home" yubikey-touch-detector.socket sockets.target
    link_user_unit "$user_home" yubikey-touch-detector.service default.target
    chown -h "$INSTALL_USER:$group" "$ssh_wants/ssh-agent.socket" \
        "$keyboard_wants/hypr-kblayoutd.service" "$broadcast_wants/broadcast-linux.service"
    chown -h "$INSTALL_USER:$group" "$keyboard_wants/hyprsunset.service"
    chown -h "$INSTALL_USER:$group" "$ssh_wants/yubikey-touch-detector.socket" \
        "$broadcast_wants/yubikey-touch-detector.service"
}

install_user_dirs() {
    local user_home=$1 group=$2 dir=$3
    local path=$user_home part
    local -a parts
    IFS=/ read -ra parts <<<"${dir#"$user_home"/}"
    for part in "${parts[@]}"; do
        path+=/$part
        install -d -o "$INSTALL_USER" -g "$group" "$path"
    done
}

configure_tailscale_first_login() {
    [[ ${TAILSCALE_FIRST_LOGIN:-1} == 1 ]] || return 0
    section "Scheduling Tailscale login for the first desktop session"
    local archlinux_dir user_home group wants unit=sys-setup-tailscale-login.service
    local -a args
    archlinux_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    group=$(id -gn "$INSTALL_USER")
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"

    install -Dm755 "$archlinux_dir/scripts/tailscale-login.sh" /usr/local/bin/sys-setup-tailscale-login
    read -ra args <<<"$TAILSCALE_UP_ARGS"
    install -d /etc/sys-setup
    {
        printf 'TAILSCALE_UP_ARGS=('
        ((${#args[@]} == 0)) || printf ' %q' "${args[@]}"
        printf ' )\n'
    } >/etc/sys-setup/tailscale-login.conf
    install -d /etc/systemd/user
    # Runs at each login until the script marks success.
    cat >"/etc/systemd/user/$unit" <<'EOF'
[Unit]
Description=Connect Tailscale on the first desktop login
After=graphical-session.target
PartOf=graphical-session.target
ConditionPathExists=!%S/sys-setup/tailscale-login.done

[Service]
Type=exec
ExecStart=/usr/local/bin/sys-setup-tailscale-login

[Install]
WantedBy=graphical-session.target
EOF
    wants="$user_home/.config/systemd/user/graphical-session.target.wants"
    install_user_dirs "$user_home" "$group" "$wants"
    link_user_unit "$user_home" "$unit" graphical-session.target /etc/systemd/user
    chown -h "$INSTALL_USER:$group" "$wants/$unit"
}
