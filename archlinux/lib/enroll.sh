#!/usr/bin/env bash

# Everything that needs a person at the keyboard, run before the unattended part.

yubikeys_dir() {
    printf '%s/yubikeys\n' "$STATE_DIR"
}

enrolled_keys() {
    local dir
    for dir in "$(yubikeys_dir)"/*/; do
        [[ -d $dir ]] && printf '%s\n' "${dir%/}"
    done
    return 0
}

enrolled_key_count() {
    enrolled_keys | grep -c . || true
}

dotfiles_repo_uses_ssh() {
    [[ $DOTFILES_REPO == ssh://* ]] || [[ $DOTFILES_REPO != *://* && $DOTFILES_REPO == *@*:* ]]
}

dotfiles_repo_host() {
    local repo=${DOTFILES_REPO#ssh://}
    repo=${repo#*@}
    printf '%s\n' "${repo%%[:/]*}"
}

yubikeys_needed() {
    [[ $YUBIKEY_SYSTEM_AUTH == 1 ]] || { [[ $ENABLE_DOTFILES == 1 ]] && dotfiles_repo_uses_ssh; }
}

describe_enrolled_key() {
    local dir=$1
    local -a uses=()
    [[ ! -f $dir/u2f ]] || uses+=("sudo/login")
    [[ ! -f $dir/ssh_name ]] || uses+=("ssh key $(<"$dir/ssh_name")")
    printf '%s %s: %s' "${dir##*/}" "$(<"$dir/label")" "${uses[*]:-nothing}"
}

list_enrolled_keys() {
    local dir i=0
    while IFS= read -r dir; do
        i=$((i + 1))
        printf '  %d) %s\n' "$i" "$(describe_enrolled_key "$dir")"
    done < <(enrolled_keys)
}

fido_device_count() {
    fido2-token -L 2>/dev/null | grep -c . || true
}

plugged_yubikey_serial() {
    ykman list --serials 2>/dev/null | head -n1 || true
}

plugged_key_label() {
    local serial=$1 label=''
    [[ -z $serial ]] || label=$(ykman --device "$serial" info 2>/dev/null | sed -n 's/^Device type: //p' || true)
    [[ -n $label ]] || label=$(fido2-token -L 2>/dev/null | sed -n '1s/.*(\(.*\)).*/\1/p' || true)
    printf '%s\n' "${label:-security key}"
}

start_pcscd() {
    # ykman reads serials through pcscd.
    systemctl start pcscd.socket >/dev/null 2>&1 || true
}

u2f_origin() {
    local file
    file="$(yubikeys_dir)/origin"
    # Credentials are bound to it, so later hostname edits must not change it.
    if [[ ! -s $file ]]; then
        mkdir -p "${file%/*}"
        printf 'pam://%s\n' "$HOSTNAME" >"$file"
    fi
    cat "$file"
}

attempt() {
    local what=$1 answer
    shift
    while true; do
        drain_input
        if "$@"; then
            return 0
        fi
        warn "$what failed"
        [[ -z ${ATTEMPT_HINT:-} ]] || printf '%s\n' "$ATTEMPT_HINT"
        ask answer "Press Enter to try again, or type s to skip:"
        [[ $answer != [sS] ]] || return 1
    done
}

fido_attempt() {
    ATTEMPT_HINT="Three wrong PINs in a row block PIN entry until the key is unplugged and plugged in again." \
        attempt "$@"
}

register_pam_credential() {
    local dir=$1 origin line
    origin=$(u2f_origin)
    printf '\n[sudo/login] Enter the YubiKey PIN, then touch the key when it blinks.\n'
    line=$(pamu2fcfg -N -u "$INSTALL_USER" -o "$origin" -i "$origin") || return 1
    line=${line#*:}
    valid_u2f_credential "$line" || {
        warn "unexpected pamu2fcfg output"
        return 1
    }
    printf '%s\n' "$line" >"$dir/u2f"
}

download_ssh_key() {
    local dir=$1 work key choice i
    local -a keys=()
    work=$(mktemp -d) || return 1
    printf '\n[SSH] Enter the YubiKey PIN again to copy its SSH key (touch it if it blinks).\n'
    # -N '' avoids two passphrase prompts per key.
    if ! (cd "$work" && ssh-keygen -K -N ''); then
        rm -rf "$work"
        return 1
    fi
    for key in "$work"/id_*_sk_rk*; do
        [[ $key == *.pub || ! -f $key ]] || keys+=("$key")
    done
    if ((${#keys[@]} == 0)); then
        warn "this YubiKey holds no resident SSH key"
        rm -rf "$work"
        return 0
    fi
    key=${keys[0]}
    if ((${#keys[@]} > 1)); then
        printf 'This YubiKey holds several SSH keys:\n'
        for i in "${!keys[@]}"; do
            printf '  %d) %s\n' $((i + 1)) "$(ssh-keygen -lf "${keys[i]}.pub")"
        done
        while true; do
            ask choice "Key to use [1]:"
            choice=${choice:-1}
            if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#keys[@]})); then
                break
            fi
        done
        key=${keys[choice - 1]}
    fi
    mkdir -p "$dir/ssh"
    if ! install -m600 "$key" "$dir/ssh/key" || ! install -m644 "$key.pub" "$dir/ssh/key.pub"; then
        rm -rf "$work"
        return 1
    fi
    printf '%s\n' "${key##*/}" >"$dir/ssh/downloaded-name"
    rm -rf "$work"
}

ssh_key_already_enrolled() {
    local public_key=$1 other
    for other in "$(yubikeys_dir)"/*/ssh/key.pub; do
        [[ -f $other ]] || continue
        [[ $(cut -d' ' -f1,2 "$other") != "$(cut -d' ' -f1,2 "$public_key")" ]] || return 0
    done
    return 1
}

dotfiles_source() {
    printf '%s %s\n' "$DOTFILES_REPO" "$DOTFILES_BRANCH"
}

dotfiles_clone_needed() {
    [[ $ENABLE_DOTFILES == 1 ]] || return 1
    [[ -d $STATE_DIR/dotfiles/.git && -f $STATE_DIR/dotfiles.source ]] || return 0
    [[ $(<"$STATE_DIR/dotfiles.source") != "$(dotfiles_source)" ]]
}

clone_dotfiles() {
    local key=${1:-} target=$STATE_DIR/dotfiles host ssh_command
    local -a ssh=(ssh -F /dev/null -o IdentityAgent=none -o IdentitiesOnly=yes
        -o "UserKnownHostsFile=$STATE_DIR/known_hosts")
    if dotfiles_repo_uses_ssh; then
        [[ -n $key ]] || {
            warn "an SSH key is needed for $DOTFILES_REPO"
            return 1
        }
        host=$(dotfiles_repo_host)
        if ! ssh-keygen -F "$host" -f "$STATE_DIR/known_hosts" >/dev/null 2>&1; then
            ssh-keyscan -H "$host" >>"$STATE_DIR/known_hosts" 2>/dev/null || {
                warn "cannot reach $host"
                return 1
            }
        fi
        ssh+=(-i "$key")
        printf '\n[dotfiles] Touch the YubiKey when it blinks to clone %s.\n' "$DOTFILES_REPO"
    fi
    printf -v ssh_command '%q ' "${ssh[@]}"
    rm -rf "$target.new"
    GIT_SSH_COMMAND=$ssh_command git clone --branch "$DOTFILES_BRANCH" -- "$DOTFILES_REPO" "$target.new" || {
        rm -rf "$target.new"
        return 1
    }
    rm -rf "$target"
    mv "$target.new" "$target"
    dotfiles_source >"$STATE_DIR/dotfiles.source"
}

# Let the dotfiles' SSH config name the file; its Match exec checks the plugged-in serial.
ssh_config_identity_name() {
    local config=$STATE_DIR/dotfiles/ssh/.ssh/config host
    [[ -f $config ]] && grep -qi '^[[:space:]]*IdentityFile' "$config" || return 0
    host=$(dotfiles_repo_host)
    ssh -G -F "$config" "${host:-github.com}" </dev/null 2>/dev/null \
        | awk '$1 == "identityfile" { sub(".*/", "", $2); print $2; exit }' || true
}

ssh_key_name_taken() {
    local name=$1 file
    for file in "$(yubikeys_dir)"/*/ssh_name; do
        [[ -f $file && $(<"$file") == "$name" ]] && return 0
    done
    return 1
}

choose_ssh_key_name() {
    local dir=$1 id=$2 base name
    base=$(sed 's/_rk.*//' "$dir/ssh/downloaded-name")
    name=$(ssh_config_identity_name)
    [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || name=$base
    if ssh_key_name_taken "$name"; then
        warn "SSH key name $name already belongs to another YubiKey; using ${base}_$id"
        name=${base}_$id
    fi
    printf '%s\n' "$name" >"$dir/ssh_name"
}

enroll_plugged_yubikey() {
    local devices serial label id work
    devices=$(fido_device_count)
    if ((devices == 0)); then
        warn "no security key found; plug it in and wait a second"
        return 1
    fi
    if ((devices > 1)); then
        warn "$devices security keys are plugged in; leave only the one to enroll"
        return 1
    fi
    serial=$(plugged_yubikey_serial)
    if [[ -n $serial && -d $(yubikeys_dir)/$serial ]]; then
        warn "YubiKey $serial is already enrolled; plug in a different key"
        return 1
    fi
    label=$(plugged_key_label "$serial")
    id=${serial:-key$(($(enrolled_key_count) + 1))}
    mkdir -p "$(yubikeys_dir)"
    work=$(mktemp -d "$(yubikeys_dir)/.new.XXXXXX") || return 1
    printf '%s\n' "$label" >"$work/label"
    section "Enrolling $id ($label)"

    if [[ $YUBIKEY_SYSTEM_AUTH == 1 ]]; then
        fido_attempt "registering for sudo and login" register_pam_credential "$work" \
            || warn "this YubiKey will not unlock sudo or login"
    fi
    fido_attempt "copying the SSH key" download_ssh_key "$work" \
        || warn "continuing without an SSH key from this YubiKey"
    if [[ -f $work/ssh/key.pub ]] && ssh_key_already_enrolled "$work/ssh/key.pub"; then
        warn "this key is already enrolled"
        rm -rf "$work"
        return 1
    fi
    if [[ ! -f $work/u2f && ! -f $work/ssh/key ]]; then
        warn "nothing was enrolled from this key"
        rm -rf "$work"
        return 1
    fi
    if [[ -f $work/ssh/key ]] && dotfiles_clone_needed; then
        fido_attempt "cloning the dotfiles" clone_dotfiles "$work/ssh/key" \
            || warn "dotfiles are not cloned yet; another YubiKey can try"
    fi
    [[ ! -f $work/ssh/key ]] || choose_ssh_key_name "$work" "$id"
    mv "$work" "$(yubikeys_dir)/$id"
    log "enrolled $(describe_enrolled_key "$(yubikeys_dir)/$id")"
}

enroll_yubikeys() {
    local answer count
    section "YubiKeys"
    printf 'Enroll every YubiKey you use, one at a time. Each one is registered for\n'
    printf 'sudo/login and its SSH key is copied. Expect two PIN prompts per key.\n'
    start_pcscd
    while true; do
        count=$(enrolled_key_count)
        if ((count > 0)); then
            printf '\nEnrolled:\n'
            list_enrolled_keys
            ask answer "Plug in another YubiKey and press Enter, or type done to finish:"
        else
            ask answer "Plug in your first YubiKey (only one at a time) and press Enter:"
        fi
        case ${answer,,} in
            '')
                enroll_plugged_yubikey || true
                ;;
            done | d)
                if ((count > 0)); then
                    break
                fi
                warn "enroll at least one YubiKey"
                ;;
            *)
                warn "press Enter to enroll the plugged-in key, or type done"
                ;;
        esac
    done
    ((count > 1)) || warn "only one YubiKey enrolled; if it is lost, regaining sudo needs the live ISO"
}

remove_enrolled_key() {
    local -a keys
    local answer
    mapfile -t keys < <(enrolled_keys)
    ((${#keys[@]} > 0)) || return 0
    list_enrolled_keys
    ask answer "Number to remove (Enter keeps all):"
    if [[ $answer =~ ^[0-9]+$ ]] && ((answer >= 1 && answer <= ${#keys[@]})); then
        rm -rf "${keys[answer - 1]}"
        log "removed ${keys[answer - 1]##*/}"
    fi
}

plugged_ssh_key() {
    local serial dir
    local -a keys=()
    serial=$(plugged_yubikey_serial)
    if [[ -n $serial && -f $(yubikeys_dir)/$serial/ssh/key ]]; then
        printf '%s\n' "$(yubikeys_dir)/$serial/ssh/key"
        return 0
    fi
    while IFS= read -r dir; do
        [[ ! -f $dir/ssh/key ]] || keys+=("$dir/ssh/key")
    done < <(enrolled_keys)
    ((${#keys[@]} != 1)) || printf '%s\n' "${keys[0]}"
}

ensure_dotfiles_clone() {
    local key answer
    dotfiles_clone_needed || return 0
    section "Cloning dotfiles"
    if ! dotfiles_repo_uses_ssh; then
        attempt "cloning the dotfiles" clone_dotfiles
        return
    fi
    start_pcscd
    while true; do
        ask answer "Plug in a YubiKey that can access $DOTFILES_REPO and press Enter, or type s to skip:"
        [[ $answer != [sS] ]] || return 1
        key=$(plugged_ssh_key)
        if [[ -z $key ]]; then
            warn "the plugged-in key has no enrolled SSH key; enroll it first with k"
            continue
        fi
        if fido_attempt "cloning the dotfiles" clone_dotfiles "$key"; then
            return 0
        fi
    done
}

ask_user_password() {
    local first second
    section "Password for $INSTALL_USER"
    printf 'YubiKey login is off, so %s needs a password for login and sudo.\n' "$INSTALL_USER"
    while true; do
        drain_input
        read -rs -p "New password: " first || die "input closed"
        printf '\n'
        if [[ -z $first ]]; then
            warn "the password cannot be empty"
            continue
        fi
        read -rs -p "Repeat it: " second || die "input closed"
        printf '\n'
        [[ $first != "$second" ]] || break
        warn "the passwords differ; try again"
    done
    mkdir -p "$STATE_DIR"
    (
        umask 077
        openssl passwd -6 -stdin <<<"$first" >"$STATE_DIR/user-password.hash"
    )
}

# "error:" lines block the installation.
dotfiles_problems() {
    local dir=$STATE_DIR/dotfiles package file
    [[ $ENABLE_DOTFILES == 1 && -d $dir ]] || return 0
    for package in "${ARCH_STOW_PACKAGES[@]}"; do
        [[ -d $dir/$package ]] || echo "warning: dotfiles have no '$package' Stow package; it will be skipped"
    done
    for file in etc/greetd/config.toml etc/tuigreet/config.toml; do
        [[ -f $dir/$file ]] || echo "error: dotfiles lack $file"
    done
    [[ -d $dir/usr/share/wayland-sessions ]] || echo "error: dotfiles lack usr/share/wayland-sessions"
    if [[ $RESTORE_LACT_CONFIG == 1 ]]; then
        if [[ ! -f $dir/etc/lact/config.yaml ]]; then
            echo "error: dotfiles have no LACT snapshot at etc/lact/config.yaml"
        elif ! (validate_lact_hardware "$dir/etc/lact/config.yaml") >/dev/null 2>&1; then
            echo "error: the LACT snapshot was saved for a different GPU"
        fi
    fi
}

credential_problems() {
    if [[ $YUBIKEY_SYSTEM_AUTH == 1 ]]; then
        u2f_credentials "$(yubikeys_dir)" >/dev/null 2>&1 \
            || echo "error: no YubiKey is registered for sudo/login (k to enroll)"
    elif [[ ! -s $STATE_DIR/user-password.hash ]]; then
        echo "error: $INSTALL_USER has no password yet"
    fi
    if dotfiles_clone_needed; then
        echo "error: dotfiles are not cloned yet"
    fi
}

collect_credentials() {
    if yubikeys_needed && (($(enrolled_key_count) == 0)); then
        enroll_yubikeys
    fi
    if [[ $YUBIKEY_SYSTEM_AUTH != 1 && ! -s $STATE_DIR/user-password.hash ]]; then
        ask_user_password
    fi
    ensure_dotfiles_clone || warn "dotfiles are not cloned; turn them off or clone them from the plan"
}
