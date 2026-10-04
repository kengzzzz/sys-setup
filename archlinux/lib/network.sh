#!/usr/bin/env bash

render_static_network() {
    local interface=$1
    local address=$2
    local gateway=$3
    local dns=$4

    cat <<EOF
[connection]
id=static-$interface
type=ethernet
interface-name=$interface
autoconnect=true

[ipv4]
method=manual
address1=$address,$gateway
dns=$dns;

[ipv6]
method=link-local
EOF
}

configure_static_network() {
    local output=${1:-/etc/NetworkManager/system-connections/static-${NETWORK_INTERFACE}.nmconnection}
    local rendered

    section "Configuring NetworkManager"
    rendered=$(mktemp)
    render_static_network "$NETWORK_INTERFACE" "$NETWORK_ADDRESS" "$NETWORK_GATEWAY" "$NETWORK_DNS" >"$rendered"
    install -d -m700 "$(dirname -- "$output")"
    install -m600 "$rendered" "$output"
    rm -f "$rendered"
}

configure_resolver_link() {
    # arch-chroot bind-mounts resolv.conf. Replace it only after chroot exits.
    ln -sfn /run/systemd/resolve/resolv.conf "${1:-/mnt/etc/resolv.conf}"
}
