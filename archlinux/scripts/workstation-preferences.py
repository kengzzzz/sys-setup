#!/usr/bin/env python3
"""Save desktop preferences in private Git and link ordinary files with Stow."""

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile


PACKAGE = "workstation"
EXPORTS = Path(".config/workstation")
QALCULATE = Path(".config/qalculate/qalculate-gtk.cfg")
PUBLIC_REPO = Path(__file__).resolve().parents[2]
HOME_PATHS = (
    ".config/cava", ".config/xfce4/xfconf/xfce-perchannel-xml/thunar.xml",
    ".config/pavucontrol.ini", ".config/qalculate/qalculate-gtk.cfg",
    ".config/mimeapps.list", ".config/user-dirs.dirs", ".config/user-dirs.locale",
    ".config/git/ignore", ".gtkrc-2.0", ".themes", ".icons",
    ".local/share/themes", ".local/share/fonts", ".local/share/icons",
    ".local/share/qalculate/definitions", ".local/state/wireplumber", ".local/state/hypr",
)
CACHE_DIRS = {"__pycache__", ".cache", "cache", ".tmp"}
QALCULATE_HISTORY_KEYS = {
    "expression_history", "history", "history_old", "history_expression",
    "history_expression*", "history_transformation", "history_result",
    "history_result_approximate", "history_parse", "history_parse_withequals",
    "history_parse_approximate", "history_register_moved", "history_register_moved*",
    "history_rpn_operation", "history_rpn_operation*", "history_warning",
    "history_message", "history_error", "history_bookmark", "history_continued",
    "history_time", "recent_functions", "recent_variables", "recent_units",
}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def git_files(dotfiles):
    result = run("git", "-C", str(dotfiles), "ls-files", "--cached", "--others", "--exclude-standard", "-z",
                 capture_output=True)
    paths = {Path(os.fsdecode(p)) for p in result.stdout.split(b"\0") if p}
    return {dotfiles / p for p in paths if "__pycache__" not in p.parts}


def excluded(path):
    name = path.name
    if name in CACHE_DIRS or name in {"icon-theme.cache", "qalc.history", "qalculate-gtk.history"}:
        return True
    if path.parts[-5:-3] == ("icons", "hicolor") and path.parent.name == "apps":
        if re.fullmatch(r"steam_icon_[0-9]+\.png|[0-9a-fA-F]{4}_.+\.[0-9]+\.(png|svg|xpm)", name):
            return True
    return ".bak" in name or ".pre-" in name or name.endswith((".pyc", ".pid", ".lock"))


def qalculate_preferences(data):
    history_keys = {key.encode() for key in QALCULATE_HISTORY_KEYS}
    return b"".join(line for line in data.splitlines(keepends=True)
                    if line.partition(b"=")[0].strip() not in history_keys)


def copy_path(source, target, tracked, *, ancestors=(), allowed_roots=()):
    """Copy selected preferences, skipping other Stow packages and generated data."""
    if not source.exists() or excluded(source):
        return
    resolved = source.resolve()
    if resolved in tracked:
        return
    if source.is_symlink() and allowed_roots and not any(resolved.is_relative_to(p) for p in allowed_roots):
        return
    mode = source.stat().st_mode
    if stat.S_ISDIR(mode):
        if resolved in ancestors:
            raise ValueError(f"directory symlink cycle: {source}")
        target.mkdir(parents=True, exist_ok=True)
        for child in sorted(source.iterdir()):
            copy_path(child, target / child.name, tracked,
                      ancestors=(*ancestors, resolved), allowed_roots=allowed_roots)
        shutil.copystat(source, target)
    elif stat.S_ISREG(mode):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if source.parent.parts[-2:] == (".config", "qalculate") and source.name in {"qalc.cfg", "qalculate-gtk.cfg"}:
            data = target.read_bytes()
            clean = qalculate_preferences(data)
            if clean != data:
                target.write_bytes(clean)
                shutil.copystat(source, target)


def desktop_dconf(text):
    lines = []
    selected = False
    for line in text.splitlines(keepends=True):
        if line.startswith("[") and line.rstrip().endswith("]"):
            selected = line.strip()[1:-1].startswith("org/gnome/desktop/")
        if selected:
            lines.append(line)
    return "".join(lines)


def environment(home):
    return dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"))


def link(home, dotfiles):
    package = dotfiles / PACKAGE
    # --adopt is safe only after checking that every existing regular file is
    # identical to its saved copy. Never adopt edits over another Stow package.
    for saved in package.rglob("*"):
        if not saved.is_file():
            continue
        live = home / saved.relative_to(package)
        if live.is_symlink() or not live.exists():
            continue  # Stow's dry run checks conflicting links/directories.
        if not live.is_file() or live.read_bytes() != saved.read_bytes():
            raise ValueError(f"live file differs from saved preferences; save it first: {live}")
    (home / ".local/share/icons").mkdir(parents=True, exist_ok=True)
    command = ["stow", "--dir", str(dotfiles), "--target", str(home),
               "--no-folding", "--adopt", "--restow"]
    subprocess.run([*command, "--simulate", PACKAGE], check=True)
    subprocess.run([*command, PACKAGE], check=True)


def save(args):
    dotfiles, home = args.dotfiles, args.home
    if dotfiles.is_relative_to(PUBLIC_REPO) or not (dotfiles / ".git").exists():
        raise ValueError("--dotfiles must be a private Git checkout outside public sys-setup")
    package = dotfiles / PACKAGE
    if package.is_symlink():
        raise ValueError("workstation Stow package must be a real directory")
    portable = {p for p in git_files(dotfiles) if not p.is_relative_to(package)}
    tracked = portable | {p.resolve() for p in portable}
    with tempfile.TemporaryDirectory(prefix="workstation-preferences-") as directory:
        staging = Path(directory)
        for relative in HOME_PATHS:
            copy_path(home / relative, staging / relative, tracked, allowed_roots=(home, dotfiles))
        exports = staging / EXPORTS
        exports.mkdir(parents=True, exist_ok=True)
        if (staging / QALCULATE).exists():
            (staging / QALCULATE).replace(exports / "qalculate-gtk.cfg")
        result = run("dconf", "dump", "/", capture_output=True, text=True, env=environment(home))
        (exports / "dconf.ini").write_text(desktop_dconf(result.stdout))
        files = [p for p in staging.rglob("*") if p.is_file()]
        # Refuse repository symlinks that would turn saving into writes elsewhere.
        for source in files:
            target = package / source.relative_to(staging)
            if target.is_symlink() or not target.parent.resolve().is_relative_to(package.resolve()):
                raise ValueError(f"saved preference path escapes its Stow package: {target}")
        for source in files:
            target = package / source.relative_to(staging)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    # Keep application-generated Qalculate history outside the folded Stow tree.
    (home / ".config/qalculate").mkdir(parents=True, exist_ok=True)
    link(home, dotfiles)
    print(f"Saved preferences in {package}; ordinary files are now linked with Stow.")
    print("Review and commit in private dotfiles.")


def apply(args):
    home, dotfiles = args.home, args.dotfiles
    exports = dotfiles / PACKAGE / EXPORTS
    dconf = exports / "dconf.ini"
    if dconf.exists():
        run("dconf", "load", "/", input=desktop_dconf(dconf.read_text()), text=True, env=environment(home))
    qalculate = exports / "qalculate-gtk.cfg"
    if qalculate.exists():
        live = home / QALCULATE
        if live.is_symlink() or live.resolve().is_relative_to(dotfiles):
            print(f"Keeping Git-owned Qalculate configuration: {live}")
        else:
            preferences = qalculate_preferences(qalculate.read_bytes())
            # Reapplying preferences on a running workstation must not erase its
            # local calculation history. History is never copied into Git.
            history_keys = {key.encode() for key in QALCULATE_HISTORY_KEYS}
            history = b"".join(line for line in (live.read_bytes() if live.exists() else b"").splitlines(keepends=True)
                               if line.partition(b"=")[0].strip() in history_keys)
            if history and preferences and not preferences.endswith(b"\n"):
                preferences += b"\n"
            live.parent.mkdir(parents=True, exist_ok=True)
            live.write_bytes(preferences + history)
    print("Applied saved desktop preferences; current Git/Stow configuration remains authoritative.")


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("save", "apply"):
        child = commands.add_parser(name)
        child.add_argument("--home", type=Path, default=Path.home())
        child.add_argument("--dotfiles", type=Path)
    args = parser.parse_args()
    args.home = args.home.resolve()
    args.dotfiles = (args.dotfiles or args.home / "dotfiles").resolve()
    try:
        {"save": save, "apply": apply}[args.command](args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()
