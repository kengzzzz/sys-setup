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
    fstrim.timer
    xfs_scrub_all.timer
    accounts-daemon.service
)

enable_system_services() {
    section "Enabling services"
    systemctl enable "${SYSTEM_SERVICES[@]}"
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
    local user_home group ssh_wants keyboard_wants
    user_home=$(getent passwd "$INSTALL_USER" | cut -d: -f6)
    group=$(id -gn "$INSTALL_USER")
    [[ -n $user_home ]] || die "home directory not found for $INSTALL_USER"

    ssh_wants="$user_home/.config/systemd/user/sockets.target.wants"
    keyboard_wants="$user_home/.config/systemd/user/graphical-session.target.wants"
    install -d -o "$INSTALL_USER" -g "$group" \
        "$user_home/.config" \
        "$user_home/.config/systemd" \
        "$user_home/.config/systemd/user" \
        "$ssh_wants" \
        "$keyboard_wants"
    link_user_unit "$user_home" ssh-agent.socket sockets.target
    link_user_unit "$user_home" hypr-kblayoutd.service graphical-session.target
    chown -h "$INSTALL_USER:$group" "$ssh_wants/ssh-agent.socket" \
        "$keyboard_wants/hypr-kblayoutd.service"
}
