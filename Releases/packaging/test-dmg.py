"""macOS regression checks: permissions, release rollback, and owned mount cleanup."""

import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import dmg


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="combo-dmg-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def invalid_app(self):
        app = self.root / "Combo.app"
        main = app / "Contents/MacOS/Combo"
        main.parent.mkdir(parents=True)
        main.write_bytes(b"unchanged executable content")
        main.chmod(0o644)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Combo"}))
        return app

    def test_prepare_rejects_non_executable_main(self):
        self.invalid_app()
        with self.assertRaisesRegex(RuntimeError, "主程序没有执行权限"):
            dmg.prepare(self.root, self.root, "Combo-test-arm64.dmg")

    def test_verify_rejects_non_executable_main(self):
        app = self.invalid_app()
        (self.root / "Applications").symlink_to("/Applications")
        for name in dmg.HELPERS:
            (self.root / name).touch()
        manifest = self.root / ".manifest.json"
        manifest.write_text(json.dumps({"app": dmg.app_files(app)}))
        with self.assertRaisesRegex(RuntimeError, "主程序没有执行权限"):
            dmg.verify(self.root, manifest)

    def releases(self, existing=True):
        output = self.root / "Combo-test-arm64.dmg"
        guide = self.root / "安装指南.html"
        if existing:
            output.write_bytes(b"old image")
            guide.write_bytes(b"old guide")
            subprocess.run(["/usr/bin/xattr", "-wx", "com.apple.ResourceFork",
                            b"old metadata".hex(), str(guide)], check=True)
        image_source = self.root / "input.dmg"
        guide_source = self.root / "input.html"
        image_source.write_bytes(b"new image")
        guide_source.write_bytes(b"new guide")
        return image_source, guide_source, output, guide

    def test_locked_guide_leaves_both_old_files(self):
        image, source, output, guide = self.releases()
        os.chflags(guide, stat.UF_IMMUTABLE)
        try:
            with self.assertRaisesRegex(RuntimeError, "已锁定"):
                dmg.publish(image, source, output)
            self.assertEqual(output.read_bytes(), b"old image")
            self.assertEqual(guide.read_bytes(), b"old guide")
        finally:
            os.chflags(guide, 0)

    def rollback_check(self, existing=True, interrupt=False):
        image, source, output, guide = self.releases(existing)
        original_replace = os.replace

        def fail_second(old, new):
            if Path(old).name == "new-1":
                if interrupt:
                    os.kill(os.getpid(), signal.SIGTERM)
                raise PermissionError("injected second replacement failure")
            original_replace(old, new)

        with patch.object(dmg.os, "replace", side_effect=fail_second):
            with self.assertRaises((PermissionError, RuntimeError)):
                dmg.publish(image, source, output)
        if existing:
            self.assertEqual(output.read_bytes(), b"old image")
            self.assertEqual(guide.read_bytes(), b"old guide")
            self.assertEqual(dmg.attribute(guide, "com.apple.ResourceFork"), b"old metadata")
        else:
            self.assertFalse(output.exists())
            self.assertFalse(guide.exists())
        self.assertFalse(list(self.root.glob(".combo-publish-*")))

    def test_second_replace_failure_restores_data_and_metadata(self):
        self.rollback_check()

    def test_failed_first_release_removes_partial_output(self):
        self.rollback_check(existing=False)

    def test_termination_during_publish_rolls_back(self):
        self.rollback_check(interrupt=True)

    def mount_failure_check(self, parser_failure):
        resources = Path(__file__).resolve().parent
        entry = (resources.parent / "package-dmg.sh").read_text()
        cleanup = entry[entry.index("cleanup() {"):entry.index("trap 'cleanup $?' EXIT")]
        functions = entry[entry.index("attach_image() {"):entry.index("hdiutil create -srcfolder")]
        work = self.root / "work"
        work.mkdir()
        lock = self.root / "lock"
        lock.mkdir()
        image = work / "writable.dmg"
        subprocess.run(["hdiutil", "create", "-size", "8m", "-fs", "HFS+", "-volname",
                        "Combo regression", str(image)], check=True, capture_output=True)
        environment = os.environ.copy()
        if not parser_failure:
            shim = self.root / "bin"
            shim.mkdir()
            diskutil = shim / "diskutil"
            diskutil.write_text('#!/bin/zsh\nif [[ ! -e "$COMBO_TEST_FAILED" ]]; then\n'
                                '  touch "$COMBO_TEST_FAILED"\n  exit 1\nfi\n'
                                'exec /usr/sbin/diskutil "$@"\n')
            diskutil.chmod(0o755)
            environment["PATH"] = f"{shim}:{environment['PATH']}"
            environment["COMBO_TEST_FAILED"] = str(self.root / "failed-once")
        attach_call = next(line for line in entry.splitlines() if line.startswith('attach_image "$dmg_work/writable'))
        eject_call = next(line for line in entry.splitlines() if line.startswith("eject_image ||"))
        probe = self.root / "probe.zsh"
        probe.write_text('set -euo pipefail\ndmg_work="$1"\ndmg_lock="$2"\n'
                         'dmg_resources="$3"\ndmg_python="$4"\ndmg_device=""\n'
                         + cleanup + "trap 'cleanup $?' EXIT\n" + functions + attach_call + "\n"
                         + ("" if parser_failure else eject_call + "\n"))
        try:
            result = subprocess.run(["/bin/zsh", str(probe), str(work), str(lock), str(resources),
                                     "/usr/bin/false" if parser_failure else sys.executable],
                                    env=environment, capture_output=True, text=True, timeout=60)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            devices = io.StringIO()
            with contextlib.redirect_stdout(devices):
                dmg.owned_devices(work)
            self.assertEqual(devices.getvalue(), "", result.stderr)
            self.assertFalse(work.exists(), result.stderr)
            self.assertFalse(lock.exists(), result.stderr)
        finally:
            # A regression must not leave this test's image mounted.
            devices = io.StringIO()
            with contextlib.redirect_stdout(devices):
                dmg.owned_devices(work)
            for device in devices.getvalue().splitlines():
                subprocess.run(["/usr/sbin/diskutil", "eject", device], check=True, capture_output=True)

    def test_attach_parser_failure_cleans_up_mount_and_lock(self):
        self.mount_failure_check(parser_failure=True)

    def test_eject_failure_retries_owned_mount_in_cleanup(self):
        self.mount_failure_check(parser_failure=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
