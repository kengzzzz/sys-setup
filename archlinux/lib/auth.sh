#!/usr/bin/env bash

U2F_MAPPINGS=/etc/Yubico/u2f_mappings

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

valid_u2f_credential() {
    [[ $1 =~ ^[A-Za-z0-9+/=_-]+,[A-Za-z0-9+/=_-]+,(es256|eddsa|rs256),[+a-z]*$ ]]
}

u2f_credentials() {
    local keys_dir=$1 file credential joined=''
    for file in "$keys_dir"/*/u2f; do
        [[ -f $file ]] || continue
        credential=$(<"$file")
        valid_u2f_credential "$credential" || return 1
        joined+=${joined:+:}$credential
    done
    [[ -n $joined ]] || return 1
    printf '%s\n' "$joined"
}

# pam_u2f checks credentials against the origin, not the user, so accounts can share them.
render_u2f_mappings() {
    local credentials=$1 user
    shift
    for user in "$@"; do
        printf '%s:%s\n' "$user" "$credentials"
    done
}

configure_yubikey_system_auth() {
    [[ ${YUBIKEY_SYSTEM_AUTH:-1} == 1 ]] || {
        warn "system-wide YubiKey PAM auth disabled"
        return 0
    }

    section "Configuring YubiKey system authentication"
    local keys_dir=$INSTALL_STATE/yubikeys credentials rendered
    # No password fallback: an empty mapping would lock everyone out.
    credentials=$(u2f_credentials "$keys_dir") \
        || die "no valid YubiKey credentials were enrolled; PAM was left unchanged"
    rendered=$(mktemp)
    render_u2f_mappings "$credentials" "$INSTALL_USER" root >"$rendered"
    install -Dm644 "$rendered" "$U2F_MAPPINGS"
    rm -f "$rendered"
    patch_system_auth_file /etc/pam.d/system-auth "$(<"$keys_dir/origin")"
}

create_user() {
    if id "$INSTALL_USER" >/dev/null 2>&1; then
        warn "user already exists: $INSTALL_USER"
    else
        useradd -m -G wheel -s /bin/zsh "$INSTALL_USER"
    fi
}

configure_accounts() {
    section "Configuring accounts"
    create_user
    # No passwords; useradd already leaves the new user locked.
    passwd -l root
    if [[ $YUBIKEY_SYSTEM_AUTH != 1 ]]; then
        usermod -p "$(<"$INSTALL_STATE/user-password.hash")" "$INSTALL_USER"
    fi
}
