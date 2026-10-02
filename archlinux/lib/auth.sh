#!/usr/bin/env bash

patch_system_auth_file() {
    local file=$1
    local origin=${2:-pam://${HOSTNAME}} rendered
    rendered=$(mktemp)
    # Replace only the password authentication line. Account/password/session
    # pam_systemd_home and pam_unix lines must not add extra authentication steps.
    if ! awk -v origin="$origin" '
        /^[[:space:]]*-?auth[[:space:]].*pam_u2f\.so.*authfile=\/etc\/Yubico\/u2f_mappings/ { next }
        /^[[:space:]]*(#[[:space:]]*)?-?auth[[:space:]].*pam_unix\.so/ {
            if (!inserted++) {
                print "auth       [success=1 default=bad]     pam_u2f.so           authfile=/etc/Yubico/u2f_mappings cue pin=1 origin=" origin " appid=" origin
            }
            if ($0 !~ /^[[:space:]]*#/) printf "# "
        }
        { print }
        END { if (!inserted) exit 1 }
    ' "$file" >"$rendered"; then
        rm -f "$rendered"
        die "cannot locate pam_unix authentication in $file; PAM was left unchanged"
    fi
    cat "$rendered" >"$file"
    rm -f "$rendered"
}

enroll_yubikey_user() {
    local user=$1

    printf 'Enroll YubiKey for %s. Insert the key, provide PIN/touch when prompted, then press Enter.\n' "$user" >&2
    read -r
    # -u selects the mapping user; root can access FIDO without a seat session.
    pamu2fcfg -N -u "$user" -o "pam://$HOSTNAME" -i "pam://$HOSTNAME"
}

configure_yubikey_system_auth() {
    [[ ${YUBIKEY_SYSTEM_AUTH:-1} == 1 ]] || {
        warn "system-wide YubiKey PAM auth disabled"
        return 0
    }

    section "Configuring YubiKey system authentication"
    local mappings mapping user
    mappings=$(mktemp)
    for user in "$INSTALL_USER" root; do
        if ! mapping=$(enroll_yubikey_user "$user"); then
            rm -f "$mappings"
            die "YubiKey enrollment failed for $user; PAM was left unchanged"
        fi
        [[ $mapping == "$user:"* && $mapping != *$'\n'* ]] || {
            rm -f "$mappings"
            die "invalid YubiKey mapping for $user; PAM was left unchanged"
        }
        printf '%s\n' "$mapping" >>"$mappings"
    done
    mkdir -p /etc/Yubico
    install -m0644 "$mappings" /etc/Yubico/u2f_mappings
    rm -f "$mappings"
    patch_system_auth_file /etc/pam.d/system-auth "pam://$HOSTNAME"
}
