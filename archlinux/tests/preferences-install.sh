#!/usr/bin/env bash
# Exercise Stow and the real preference installer in a disposable HOME.
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_DIR=$ROOT_DIR
source "$ROOT_DIR/../lib/common.sh"
source "$ROOT_DIR/lib/dotfiles.sh"

DOTFILES_SOURCE=${1:-/home/$(id -un)/dotfiles}
PREFERENCES_TEST_DIR=$(mktemp -d /tmp/preferences-install-XXXXXX)
trap 'rm -rf "$PREFERENCES_TEST_DIR"' EXIT
TEST_USER_HOME="$PREFERENCES_TEST_DIR/home"
INSTALL_USER=$(id -un)
DOTFILES_DIR="$TEST_USER_HOME/dotfiles"
mkdir -p "$DOTFILES_DIR"

python - "$ROOT_DIR" "$DOTFILES_SOURCE" "$DOTFILES_DIR" <<'PY'
import importlib.util
from pathlib import Path
import shutil
import sys
root, source, dotfiles = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('preferences', root / 'scripts/workstation-preferences.py')
preferences = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preferences)
for path in preferences.git_files(source):
    if not path.exists() and not path.is_symlink(): continue
    target = dotfiles / path.relative_to(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target, follow_symlinks=False)
exports = dotfiles / 'workstation/.config/workstation'
exports.mkdir(parents=True, exist_ok=True)
if not (exports / 'dconf.ini').exists():
    (exports / 'dconf.ini').write_text("[org/gnome/desktop/interface]\ngtk-theme='test-current-theme'\n")
if not (exports / 'qalculate-gtk.cfg').exists():
    (exports / 'qalculate-gtk.cfg').write_text('[General]\nprecision=24\n')
PY

printf 'current Git revision\n' >"$DOTFILES_DIR/hypr/.config/hypr/revision-test.conf"
git -C "$DOTFILES_DIR" init -q
git -C "$DOTFILES_DIR" config user.name Test
git -C "$DOTFILES_DIR" config user.email test@example.invalid
git -C "$DOTFILES_DIR" add .
git -C "$DOTFILES_DIR" commit -qm 'current configuration'
CURRENT_HEAD=$(git -C "$DOTFILES_DIR" rev-parse HEAD)

# Resolve this account to the disposable HOME, without touching the real user.
getent() {
    if [[ $1 == passwd && $2 == "$INSTALL_USER" ]]; then
        printf '%s:x:%s:%s::%s:/bin/bash\n' "$INSTALL_USER" "$(id -u)" "$(id -g)" "$TEST_USER_HOME"
    else
        command getent "$@"
    fi
}
runuser() {
    [[ $1 == -u && $2 == "$INSTALL_USER" && $3 == -- ]]
    shift 3
    "$@"
}

mkdir -p "$TEST_USER_HOME/.local/share/icons" "$TEST_USER_HOME/.config/qalculate"
stow -n -d "$DOTFILES_DIR" -t "$TEST_USER_HOME" "${ARCH_STOW_PACKAGES[@]}"
stow -R -d "$DOTFILES_DIR" -t "$TEST_USER_HOME" "${ARCH_STOW_PACKAGES[@]}"
stow -n --no-folding -d "$DOTFILES_DIR" -t "$TEST_USER_HOME" workstation
stow -R --no-folding -d "$DOTFILES_DIR" -t "$TEST_USER_HOME" workstation
apply_workstation_preferences

[[ $(git -C "$DOTFILES_DIR" rev-parse HEAD) == "$CURRENT_HEAD" ]]
[[ -z $(git -C "$DOTFILES_DIR" status --porcelain) ]]
[[ $(<"$TEST_USER_HOME/.config/hypr/revision-test.conf") == 'current Git revision' ]]
[[ $(realpath -e "$TEST_USER_HOME/.config/mpv/mpv.conf") == "$DOTFILES_DIR/mpv/.config/mpv/mpv.conf" ]]
[[ -e $TEST_USER_HOME/.config/desktop/assets/wallpaper.png ]]
cmp "$TEST_USER_HOME/.config/qalculate/qalculate-gtk.cfg" \
    "$DOTFILES_DIR/workstation/.config/workstation/qalculate-gtk.cfg"

env HOME="$TEST_USER_HOME" XDG_CONFIG_HOME="$TEST_USER_HOME/.config" \
    dconf dump / >"$PREFERENCES_TEST_DIR/dconf.ini"
python - "$DOTFILES_DIR/workstation/.config/workstation/dconf.ini" "$PREFERENCES_TEST_DIR/dconf.ini" <<'PY'
import configparser
import sys
settings = []
for filename in sys.argv[1:]:
    parser = configparser.RawConfigParser()
    parser.read(filename)
    settings.append({section: dict(parser.items(section)) for section in parser.sections()})
assert settings[0] == settings[1], 'dconf settings differ from their Git export'
PY
printf 'plain preferences, Stow, current Git configuration, and dconf checks passed\n'
