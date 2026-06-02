#!/usr/bin/env bash
set -euo pipefail

readonly CACHYOS_KEY_ID="F3B607488DB35A47"
readonly CACHYOS_KEY_FINGERPRINT="882DCFE48E2051D48E2562ABF3B607488DB35A47"
readonly CACHYOS_MIRROR_URL="https://mirror.cachyos.org/repo/x86_64/cachyos"

key_path="${1:-/usr/local/share/cachyos-signing-key.asc}"
repo_flavor="${CACHYOS_REPO_FLAVOR:-auto}"

msg() {
  printf '==> %s\n' "$*" >&2
}

verify_key_asset() (
  local gnupg_home actual_fingerprint

  gnupg_home="$(mktemp -d)"
  chmod 700 "${gnupg_home}"
  trap 'rm -rf "${gnupg_home}"' EXIT

  gpg --batch --homedir "${gnupg_home}" --import "${key_path}" >/dev/null
  actual_fingerprint="$(
    gpg --batch --homedir "${gnupg_home}" --with-colons --fingerprint "${CACHYOS_KEY_ID}" |
      awk -F: '$1 == "fpr" { print $10; exit }'
  )"

  if [[ "${actual_fingerprint}" != "${CACHYOS_KEY_FINGERPRINT}" ]]; then
    printf 'Unexpected CachyOS key fingerprint: %s\n' "${actual_fingerprint:-<missing>}" >&2
    exit 1
  fi
)

detect_repo_flavor() {
  local native_march

  native_march="$(gcc -march=native -Q --help=target 2>/dev/null | awk '$1 == "-march=" { print $2; exit }')"
  if [[ "${native_march}" =~ ^znver[45]$ ]]; then
    printf 'znver4\n'
    return
  fi

  if /lib/ld-linux-x86-64.so.2 --help | grep -q 'x86-64-v4 (supported, searched)'; then
    printf 'v4\n'
    return
  fi

  if /lib/ld-linux-x86-64.so.2 --help | grep -q 'x86-64-v3 (supported, searched)'; then
    printf 'v3\n'
    return
  fi

  printf 'generic\n'
}

repo_block_for_flavor() {
  local flavor="$1"

  case "${flavor}" in
    znver4)
      cat <<'EOF'
[cachyos-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

EOF
      ;;
    v4)
      cat <<'EOF'
[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

EOF
      ;;
    v3)
      cat <<'EOF'
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

EOF
      ;;
    generic)
      cat <<'EOF'
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

EOF
      ;;
    *)
      printf 'Unsupported CACHYOS_REPO_FLAVOR: %s\n' "${flavor}" >&2
      exit 1
      ;;
  esac
}

arch_for_flavor() {
  case "$1" in
    znver4|v4)    printf 'x86_64 x86_64_v3 x86_64_v4\n' ;;
    v3)           printf 'x86_64 x86_64_v3\n' ;;
    generic)      printf 'x86_64\n' ;;
  esac
}

configure_pacman() {
  local flavor="$1"
  local pacman_conf="/etc/pacman.conf"
  local pacman_conf_new="/etc/pacman.conf.cachyos"
  local arch="$(arch_for_flavor "${flavor}")"

  awk -v arch="${arch}" '
    /^[[:space:]]*Architecture[[:space:]]*=/ {
      print "Architecture = " arch
      next
    }
    /^\[[^][]+\]/ && $0 != "[options]" && !inserted {
      while ((getline line < block) > 0) print line
      close(block)
      inserted = 1
    }
    { print }
  ' block=<(repo_block_for_flavor "${flavor}") "${pacman_conf}" > "${pacman_conf_new}"

  install -m 0644 "${pacman_conf_new}" "${pacman_conf}"
  rm -f "${pacman_conf_new}"
}

install_bootstrap_packages() (
  local bootstrap_conf

  bootstrap_conf="$(mktemp)"
  trap 'rm -f "${bootstrap_conf}"' EXIT

  cat > "${bootstrap_conf}" <<EOF
[options]
Architecture = x86_64
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[cachyos]
Server = ${CACHYOS_MIRROR_URL}
EOF

  pacman --config "${bootstrap_conf}" -Sy --noconfirm --needed \
    cachyos-keyring \
    cachyos-mirrorlist \
    cachyos-v3-mirrorlist \
    cachyos-v4-mirrorlist \
    pacman
)

if [[ ! -f "${key_path}" ]]; then
  printf 'CachyOS signing key not found: %s\n' "${key_path}" >&2
  exit 1
fi

verify_key_asset

msg "Importing vendored CachyOS signing key"
pacman-key --add "${key_path}"
pacman-key --lsign-key "${CACHYOS_KEY_ID}"

msg "Installing latest CachyOS bootstrap packages"
install_bootstrap_packages

if [[ "${repo_flavor}" == "auto" ]]; then
  repo_flavor="$(detect_repo_flavor)"
fi

msg "Configuring CachyOS ${repo_flavor} repository"
configure_pacman "${repo_flavor}"

msg "Clearing bootstrap sync databases"
rm -f /var/lib/pacman/sync/*.db /var/lib/pacman/sync/*.db.sig
