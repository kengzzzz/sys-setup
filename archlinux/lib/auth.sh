#!/usr/bin/env bash

patch_system_auth_file() {
    local file=$1

    if ! grep -q 'pam_u2f.so.*authfile=/etc/Yubico/u2f_mappings' "$file"; then
        if grep -q 'pam_systemd_home.so' "$file"; then
            sed -i '/pam_systemd_home.so/a auth       [success=1 default=bad]     pam_u2f.so           authfile=/etc/Yubico/u2f_mappings cue pin=1' "$file"
        else
            sed -i '/pam_unix\.so/i auth       [success=1 default=bad]     pam_u2f.so           authfile=/etc/Yubico/u2f_mappings cue pin=1' "$file"
        fi
    fi

    sed -i '/^[[:space:]]*-*auth[[:space:]].*pam_unix\.so/s/^/# /' "$file"
}

enroll_yubikey_user() {
    local user=$1

    printf 'Enroll YubiKey for %s. Insert the key, provide PIN/touch when prompted, then press Enter.\n' "$user" >&2
    read -r
    if [[ $user == root ]]; then
        pamu2fcfg -N -u root
    else
        runuser -u "$user" -- pamu2fcfg -N -u "$user"
    fi
}

configure_yubikey_system_auth() {
    [[ ${YUBIKEY_SYSTEM_AUTH:-1} == 1 ]] || {
        warn "system-wide YubiKey PAM auth disabled"
        return 0
    }

    section "Configuring YubiKey system authentication"
    mkdir -p /etc/Yubico
    enroll_yubikey_user "$INSTALL_USER" >/etc/Yubico/u2f_mappings
    enroll_yubikey_user root >>/etc/Yubico/u2f_mappings
    chmod 0644 /etc/Yubico/u2f_mappings
    patch_system_auth_file /etc/pam.d/system-auth
}
