"""Install an EdDSA-signed DMG into a disposable, ad-hoc Combo copy.

Usage: python3 Tests/Tools/check-sparkle-install.py --app <Release/Combo.app>
       --sparkle <directory containing Sparkle.framework and bin/sign_update>
All update traffic stays on loopback; the real app and production feed are untouched.
"""
import argparse
import functools
import http.server
import importlib.util
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import threading
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--sparkle", type=Path, required=True)
    parser.add_argument("--invalid-signature", action="store_true", help="Verify that a mismatched signature is rejected")
    args = parser.parse_args()
    os.environ.setdefault("DEVELOPER_DIR", os.environ.get("COMBO_DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
    assert args.app.name == "Combo.app" and (args.app / "Contents/MacOS/Combo").is_file()
    framework = args.sparkle / "Sparkle.framework"
    assert framework.is_dir() and (args.sparkle / "bin/sign_update").is_file()
    with tempfile.TemporaryDirectory(prefix="sparkle-install-", dir=ROOT / "build") as directory:
        work = Path(directory)
        stage = work / "download"
        stage.mkdir()
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=stage)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            base = f"http://127.0.0.1:{server.server_port}"
            new_app = stage / "Combo.app"
            run("ditto", args.app, new_app)
            info_path = new_app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            assert info["SUPublicEDKey"] == (ROOT / "docs/updates/public-ed-key.txt").read_text().strip()
            info.update(CFBundleIdentifier="local.combo.update-fixture", CFBundleVersion="2",
                        CFBundleShortVersionString="1.0.2", SUFeedURL=base + "/appcast.xml",
                        SUEnableAutomaticChecks=False, NSAppTransportSecurity={"NSAllowsArbitraryLoads": True})
            info_path.write_bytes(plistlib.dumps(info))
            spec = importlib.util.spec_from_file_location("dmg_packager", ROOT / "Releases/packaging/dmg.py")
            packaging = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(packaging)
            packaging.prepare(stage, ROOT / "Releases/packaging", "fixture.dmg")
            installed = work / "installed/Combo.app"
            run("ditto", new_app, installed)
            old_info = dict(info, CFBundleVersion="1", CFBundleShortVersionString="1.0.1")
            (installed / "Contents/Info.plist").write_bytes(plistlib.dumps(old_info))
            run("codesign", "--force", "--sign", "-", installed)
            archive = work / "fixture.dmg"
            run("hdiutil", "create", "-srcfolder", stage, "-format", "UDZO", "-o", archive)
            signature_output = subprocess.check_output([
                str(args.sparkle / "bin/sign_update"), "--account", "combo-updates", str(archive)], text=True)
            signature = re.search(r'sparkle:edSignature="([^"]+)"', signature_output)
            assert signature, "No EdDSA signature returned"
            signature_value = signature.group(1)
            if args.invalid_signature:
                signature_value = ("A" if signature_value[0] != "A" else "B") + signature_value[1:]
            os.replace(archive, stage / "fixture.dmg")
            ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
            rss = ET.Element("rss", version="2.0")
            channel = ET.SubElement(rss, "channel")
            ET.SubElement(channel, "title").text = "Isolated Combo Fixture"
            item = ET.SubElement(channel, "item")
            ET.SubElement(item, "title").text = "Fixture 2"
            ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}version").text = "2"
            ET.SubElement(item, "{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString").text = "1.0.2"
            ET.SubElement(item, "enclosure", url=base + "/fixture.dmg", length=str((stage / "fixture.dmg").stat().st_size),
                          type="application/octet-stream", **{
                              "{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature": signature_value})
            ET.ElementTree(rss).write(stage / "appcast.xml", encoding="utf-8", xml_declaration=True)
            runner = work / "SparkleInstallCheck.app/Contents"
            (runner / "MacOS").mkdir(parents=True)
            (runner / "Frameworks").mkdir()
            run("ditto", framework, runner / "Frameworks/Sparkle.framework")
            runner_info = dict(info, CFBundleIdentifier="local.combo.sparkle-install-check", CFBundleExecutable="SparkleInstallCheck")
            (runner / "Info.plist").write_bytes(plistlib.dumps(runner_info))
            run("xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-F", args.sparkle,
                "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                ROOT / "Tests/Tools/SparkleInstallCheck.swift", "-o", runner / "MacOS/SparkleInstallCheck")
            run("codesign", "--force", "--sign", "-", runner.parent)
            result_process = subprocess.run([str(runner / "MacOS/SparkleInstallCheck"), str(installed)],
                                            capture_output=True, text=True, timeout=90)
            print(result_process.stdout, end="")
            print(result_process.stderr, end="")
            if args.invalid_signature:
                assert result_process.returncode != 0 and "Fixture update failed" in result_process.stderr
                assert "Code=3001" in result_process.stderr or "Code=3002" in result_process.stderr
                assert plistlib.loads((installed / "Contents/Info.plist").read_bytes())["CFBundleVersion"] == "1"
                print("PASS: mismatched EdDSA signature rejected; original fixture remains installed")
                return
            result_process.check_returncode()
            # Sparkle may terminate the updater process before its installer finishes.
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                result = plistlib.loads((installed / "Contents/Info.plist").read_bytes())
                if result["CFBundleVersion"] == "2":
                    break
                time.sleep(0.2)
            assert result["CFBundleVersion"] == "2", "Fixture was not replaced"
            run("codesign", "--verify", "--deep", "--strict", installed)
            print("PASS: actual Release Combo fixture upgraded from build 1 to 2; nested signatures remain valid")
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
