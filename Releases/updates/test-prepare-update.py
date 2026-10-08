"""Version guards protect against republishing and downgrading update feeds."""

import importlib.util
from argparse import Namespace
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("prepare_update", Path(__file__).with_name("prepare-update.py"))
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class UpdatePreparationTests(unittest.TestCase):
    def feed(self, build="100", display="1.0.0", legacy=False):
        root = ET.fromstring('<rss><channel><title>Combo</title></channel></rss>')
        item = ET.SubElement(root.find("channel"), "item")
        enclosure = ET.SubElement(item, "enclosure")
        if legacy:
            enclosure.set(update.SPARKLE + "version", build)
            enclosure.set(update.SPARKLE + "shortVersionString", display)
        else:
            ET.SubElement(item, update.SPARKLE + "version").text = build
            ET.SubElement(item, update.SPARKLE + "shortVersionString").text = display
        return root

    def test_empty_feed_and_legacy_build_can_migrate_to_numeric_build(self):
        update.validate_history(ET.fromstring("<rss><channel/></rss>"), "1.1.0", "101")
        update.validate_history(self.feed("1.0.0", legacy=True), "1.1.0", "101")

    def test_equal_or_lower_build_is_rejected(self):
        for build in ("99", "100"):
            with self.subTest(build=build), self.assertRaisesRegex(ValueError, "构建号必须大于"):
                update.validate_history(self.feed(), "1.1.0", build)

    def test_equal_or_lower_display_version_is_rejected(self):
        for display in ("0.9.0", "1.0.0", "1.0.0.0"):
            with self.subTest(display=display), self.assertRaisesRegex(ValueError, "发行版本必须大于"):
                update.validate_history(self.feed(), display, "101")

    def test_independent_build_must_be_positive_integer(self):
        for build in ("0", "-1", "1.1.0", "101-beta", ""):
            with self.subTest(build=build), self.assertRaisesRegex(ValueError, "独立的正整数"):
                update.validate_history(self.feed(), "1.1.0", build)

    def test_unknown_or_missing_history_version_fails_closed(self):
        for build in ("beta", ""):
            with self.subTest(build=build), self.assertRaises(ValueError):
                update.validate_history(self.feed(build), "1.1.0", "101")

    def test_existing_output_release_and_wrong_key_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            dmg = root / "Combo-1.1.0-arm64.dmg"
            dmg.touch()
            notes = root / "notes.html"
            notes.write_text("<html><body>Reviewed notes</body></html>")
            for name in ("generate_keys", "generate_appcast", "sign_update"):
                (root / "bin").mkdir(exist_ok=True)
                (root / "bin" / name).touch()
            args = Namespace(dmg=dmg, sparkle_tools=root, output=root / "output",
                             version="1.1.0", build="101", tag="1.1.0", notes=notes)
            args.output.mkdir()
            with self.assertRaisesRegex(ValueError, "目录已存在"):
                update.prepare(args)
            args.output.rmdir()
            with patch.object(update, "download", return_value=b"<rss><channel/></rss>"), \
                    patch.object(update.subprocess, "run") as remote, \
                    patch.object(update, "run", return_value="wrong public key") as tool:
                remote.return_value = subprocess.CompletedProcess([], 0)
                with self.assertRaisesRegex(ValueError, "该标签已有 Release"):
                    update.prepare(args)
                tool.assert_not_called()
                remote.return_value = subprocess.CompletedProcess([], 1, stderr="HTTP 403")
                with self.assertRaisesRegex(ValueError, "无法核对远端"):
                    update.prepare(args)
                remote.return_value = subprocess.CompletedProcess([], 1, stderr="HTTP 404")
                with self.assertRaisesRegex(ValueError, "公钥不一致"):
                    update.prepare(args)
                self.assertFalse(args.output.exists())


if __name__ == "__main__":
    unittest.main()
