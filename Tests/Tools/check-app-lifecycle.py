"""Exercise the production SwiftUI entrypoint inside a temporary, isolated Debug app."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", required=True, type=Path, help="Built Debug Combo.app")
args = parser.parse_args()
source = args.app.resolve()
products = source.parent
library = source / "Contents/MacOS/Combo.debug.dylib"
if not library.is_file():
    parser.error("--app must point to a Debug app with Combo.debug.dylib")
environment = {**os.environ, "DEVELOPER_DIR": os.environ.get("COMBO_DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")}

with tempfile.TemporaryDirectory(prefix="Combo-Lifecycle-") as directory:
    app = Path(directory) / "Combo.app"
    shutil.copytree(source, app, symlinks=True)
    plist = app / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info["CFBundleIdentifier"] = "local.combo.lifecycle-check." + uuid.uuid4().hex
    info["CFBundleExecutable"] = "AppLifecycleCheck"
    plist.write_bytes(plistlib.dumps(info))
    executable = app / "Contents/MacOS/AppLifecycleCheck"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-I", str(products), "-F", str(products),
        str(Path(__file__).with_name("AppLifecycleCheck.swift")), str(library),
        "-Xlinker", "-rpath", "-Xlinker", "@executable_path", "-o", str(executable),
    ], env=environment, check=True, timeout=60)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True, timeout=30)
    for arguments in ([], ["--fresh"], ["--settings"]):
        result = subprocess.run([str(executable), *arguments], capture_output=True, text=True, timeout=60)
        print("STARTUP:", arguments or "completed installation")
        print(result.stdout, end="")
        if result.returncode != 0 or "SwiftUI lifecycle checks passed" not in result.stdout:
            raise RuntimeError(f"Lifecycle check failed ({result.returncode}): {result.stderr}")
