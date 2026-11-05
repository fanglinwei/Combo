"""Check CLI validation without accessing the desktop or requesting permission."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class MenuDiagnosticsTests(unittest.TestCase):
    def test_help_and_invalid_arguments_do_not_scan(self):
        source = Path(__file__).with_name("MenuDiagnostics.swift")
        environment = dict(os.environ)
        environment["DEVELOPER_DIR"] = environment.get(
            "COMBO_DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"
        )
        with tempfile.TemporaryDirectory(prefix="combo-menu-diagnostics-") as directory:
            executable = Path(directory) / "menu-diagnostics"
            subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", str(source), "-o", str(executable)],
                env=environment, check=True, capture_output=True, text=True, timeout=60,
            )
            for arguments, expected in [(["--help"], 0), (["--unknown"], 64), (["--help", "extra"], 64)]:
                with self.subTest(arguments=arguments):
                    result = subprocess.run(
                        [str(executable), *arguments], capture_output=True, text=True, timeout=5,
                    )
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertTrue((result.stdout if expected == 0 else result.stderr).startswith("Usage:"))
                    self.assertEqual(result.stderr if expected == 0 else result.stdout, "")


if __name__ == "__main__":
    unittest.main()
