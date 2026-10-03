#!/usr/bin/env python3
"""Exercise plain preference capture, Stow links and history-free exports."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/workstation-preferences.py"
spec = importlib.util.spec_from_file_location("preferences", SCRIPT)
preferences = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preferences)


class PreferencesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="preferences test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.repo = self.home / "dotfiles"
        self.repo.mkdir(parents=True)
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.put(self.repo / "hypr/.config/hypr/config", "portable config\n")
        self.put(self.repo / "hypr/.config/hypr/deleted", "old setting\n")
        self.put(self.repo / "cava/.config/cava/config", "Git-owned Cava settings\n")
        self.put(self.repo / ".gitignore", "hypr/.config/hypr/private-token\n")
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        self.git("rm", "-q", "hypr/.config/hypr/deleted")
        self.put(self.repo / "hypr/.config/hypr/config", "local config edit\n")
        self.put(self.repo / "hypr/.config/hypr/private-token", "PRIVATE-TOKEN")
        self.put(self.home / ".config/cava/shaders/custom.frag", "custom shader\n")
        (self.home / ".config/cava/config").symlink_to(self.repo / "cava/.config/cava/config")
        self.put(self.home / ".config/BraveSoftware/History", "PRIVATE-BROWSER-HISTORY")
        self.put(self.home / ".config/vesktop/Local Storage/data", "PRIVATE-SESSION")
        self.put(self.home / ".local/share/keyrings/login.keyring", "PRIVATE-KEYRING")
        self.put(self.home / ".local/share/fonts/custom.ttf", b"\x00\xffbinary font\x00")
        (self.home / ".local/share/fonts/custom.ttf").chmod(0o644)
        self.settings = (
            "[General]\nprecision=24\nhistory_expression_type=2\nhistory_height=240\n"
            "clear_history_on_exit=0\nsave_history_separately=0\nshow_history=1\n"
            "[Mode]\nangle_unit=1\n"
        )
        self.history = (
            "expression_history=PRIVATE-CALCULATION\nhistory_time=123456\n"
            "history_expression*=PRIVATE-PROTECTED\nhistory_result_approximate=PRIVATE-RESULT\n"
            "history_parse_withequals=PRIVATE-PARSE\nhistory_bookmark=PRIVATE-BOOKMARK\n"
            "history_continued=PRIVATE-MULTILINE\nhistory_error=PRIVATE-ERROR\n"
            "history_rpn_operation*=PRIVATE-RPN\nhistory=PRIVATE-OLD-FORMAT\n"
            "recent_functions=PRIVATE-FUNCTION\nrecent_variables=PRIVATE-VARIABLE\nrecent_units=PRIVATE-UNIT\n"
        )
        self.put(self.home / preferences.QALCULATE, self.settings + self.history)
        self.put(self.home / ".config/qalculate/qalc.history", "PRIVATE-CLI-HISTORY")
        self.put(self.home / ".config/qalculate/qalculate-gtk.history", "PRIVATE-GUI-HISTORY")
        self.generated = (
            ".local/share/icons/hicolor/32x32/apps/steam_icon_123456.png",
            ".local/share/icons/hicolor/48x48/apps/ABCD_uninstall.0.png",
            ".local/share/icons/custom-theme/icon-theme.cache",
        )
        self.custom = (
            ".local/share/icons/hicolor/32x32/apps/custom-app.png",
            ".local/share/icons/custom-theme/32x32/apps/steam_icon_123456.png",
        )
        for relative in self.generated:
            self.put(self.home / relative, b"generated clutter")
        for relative in self.custom:
            self.put(self.home / relative, b"custom icon")
        self.args = SimpleNamespace(home=self.home, dotfiles=self.repo)
        self.package = self.repo / preferences.PACKAGE

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args])

    def put(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value if isinstance(value, bytes) else value.encode())

    def fake_dconf(self, *args, **kwargs):
        if args[:2] == ("dconf", "dump"):
            return subprocess.CompletedProcess(args, 0,
                "[org/gnome/desktop/interface]\ncolor-scheme='prefer-dark'\n\n"
                "[apps/seahorse]\nlast-selected='PRIVATE-APP-HISTORY'\n")
        return subprocess.run(args, check=True, **kwargs)

    def save(self):
        with patch.object(preferences, "run", self.fake_dconf):
            preferences.save(self.args)

    def test_scope_stow_and_existing_git_edits(self):
        edits, index = self.git("diff", "--binary", "HEAD"), self.git("diff", "--cached", "--binary")
        self.save()
        self.assertEqual(edits, self.git("diff", "--binary", "HEAD"))
        self.assertEqual(index, self.git("diff", "--cached", "--binary"))
        self.assertFalse((self.package / ".config/cava/config").exists())
        self.assertEqual((self.home / ".config/cava/config").resolve(), self.repo / "cava/.config/cava/config")
        font = self.home / ".local/share/fonts/custom.ttf"
        self.assertTrue(font.is_symlink())
        self.assertFalse(font.parent.is_symlink())
        self.assertEqual(font.read_bytes(), b"\x00\xffbinary font\x00")
        self.assertEqual(font.stat().st_mode & 0o777, 0o644)
        for relative in self.generated:
            self.assertFalse((self.package / relative).exists())
        for relative in self.custom:
            self.assertEqual((self.package / relative).read_bytes(), b"custom icon")
        self.assertFalse((self.home / preferences.QALCULATE).is_symlink())
        self.assertEqual((self.home / preferences.QALCULATE).read_text(), self.settings + self.history)
        self.assertEqual((self.package / preferences.EXPORTS / "qalculate-gtk.cfg").read_text(), self.settings)
        saved = b"".join(p.read_bytes() for p in self.package.rglob("*") if p.is_file())
        self.assertNotIn(b"PRIVATE-", saved)

    def test_history_only_changes_do_not_change_git_exports(self):
        self.save()
        self.git("add", "workstation")
        self.git("commit", "-qm", "preferences")
        live = self.home / preferences.QALCULATE
        live.write_text(live.read_text() + "history_expression=ANOTHER-PRIVATE-CALCULATION\n")
        self.save()
        self.assertEqual(b"", self.git("diff", "--", "workstation"))

    def test_apply_keeps_live_history_and_git_configuration(self):
        self.save()
        edits, head = self.git("diff", "--binary", "HEAD"), self.git("rev-parse", "HEAD")
        exported = self.package / preferences.EXPORTS / "qalculate-gtk.cfg"
        exported.write_text(self.settings.replace("precision=24", "precision=42"))
        with patch.object(preferences, "run") as dconf:
            preferences.apply(self.args)
        self.assertIn("prefer-dark", dconf.call_args.kwargs["input"])
        self.assertNotIn("seahorse", dconf.call_args.kwargs["input"])
        self.assertEqual((self.home / preferences.QALCULATE).read_text(),
                         self.settings.replace("precision=24", "precision=42") + self.history)
        self.assertEqual(edits, self.git("diff", "--binary", "HEAD"))
        self.assertEqual(head, self.git("rev-parse", "HEAD"))

    def test_fresh_home_apply_omits_history(self):
        self.save()
        fresh = self.root / "fresh home"
        fresh.mkdir()
        preferences.link(fresh, self.repo)
        with patch.object(preferences, "run"):
            preferences.apply(SimpleNamespace(home=fresh, dotfiles=self.repo))
        self.assertEqual((fresh / preferences.QALCULATE).read_text(), self.settings)
        self.assertEqual((fresh / ".local/share/fonts/custom.ttf").read_bytes(), b"\x00\xffbinary font\x00")

    def test_external_links_and_directory_cycle(self):
        self.put(self.root / "outside", "PRIVATE-EXTERNAL")
        (self.home / ".themes").mkdir()
        (self.home / ".themes/outside").symlink_to(self.root / "outside")
        target = self.root / "themes"
        preferences.copy_path(self.home / ".themes", target, set(), allowed_roots=(self.home,))
        self.assertFalse((target / "outside").exists())
        (self.home / ".themes/cycle").symlink_to(self.home / ".themes")
        with self.assertRaisesRegex(ValueError, "cycle"):
            preferences.copy_path(self.home / ".themes", self.root / "cycle", set(), allowed_roots=(self.home,))

    def test_link_refuses_to_adopt_different_live_content(self):
        self.save()
        font = self.home / ".local/share/fonts/custom.ttf"
        font.unlink()
        font.write_bytes(b"new local font")
        with self.assertRaisesRegex(ValueError, "differs"):
            preferences.link(self.home, self.repo)
        self.assertEqual(font.read_bytes(), b"new local font")
        self.assertEqual((self.package / ".local/share/fonts/custom.ttf").read_bytes(), b"\x00\xffbinary font\x00")


if __name__ == "__main__":
    unittest.main()
