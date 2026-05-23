#!/usr/bin/env bash

render_static_network() {
    local interface=$1
    local address=$2
    local gateway=$3
    local dns=$4

    cat <<EOF
[Match]
Name=$interface

[Network]
Address=$address
Gateway=$gateway
DNS=$dns
LinkLocalAddressing=ipv6

[Link]
RequiredForOnline=yes
EOF
}

configure_static_network() {
    section "Configuring systemd-networkd"
    mkdir -p /etc/systemd/network
    render_static_network "$NETWORK_INTERFACE" "$NETWORK_ADDRESS" "$NETWORK_GATEWAY" "$NETWORK_DNS" >/etc/systemd/network/20-static.network
    ln -sfn /run/systemd/resolve/resolv.conf /etc/resolv.conf
}
