"""Check the test entrypoint without launching Xcode or an AppKit host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]

with tempfile.TemporaryDirectory(prefix="combo-test-runner-") as directory:
    work = Path(directory)
    runner = work / "xcodebuild"
    runner.write_text("""#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
work = Path(os.environ['TMPDIR'])
active = work / 'active'
active.mkdir()  # A second runner entering concurrently must fail.
try:
    (work / 'arguments.json').write_text(json.dumps(sys.argv[1:]))
    time.sleep(float(os.environ.get('CHECK_DURATION', '.3')))
finally:
    active.rmdir()
sys.exit(int(os.environ.get('CHECK_EXIT', '0')))
""")
    runner.chmod(0o755)
    environment = {**os.environ, "TMPDIR": directory, "PATH": f"{directory}:{os.environ['PATH']}"}
    command = [str(ROOT / "Tests/run.sh"), "-only-testing:ComboIntegrationTests/IntegrationTests/ApplicationMenuTests"]
    runs = []
    try:
        for _ in range(2):
            runs.append(subprocess.Popen(command, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE))
        for run in runs:
            output, errors = run.communicate(timeout=10)
            assert run.returncode == 0, errors.decode()
        arguments = json.loads((work / "arguments.json").read_text())
        assert arguments[0] == "test" and arguments[-1] == command[-1], arguments

        failed = subprocess.run(command, env={**environment, "CHECK_EXIT": "65"}, capture_output=True, timeout=10)
        assert failed.returncode == 65, failed.stderr.decode()
        run = subprocess.Popen(command, env={**environment, "CHECK_DURATION": "30"},
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        runs.append(run)
        deadline = time.monotonic() + 5
        while not (work / "active").exists() and run.poll() is None and time.monotonic() < deadline:
            time.sleep(.01)
        assert (work / "active").exists(), "Runner did not start after the failed run"
        run.terminate()
        run.communicate(timeout=5)
        assert run.returncode != 0
        after = subprocess.run(command, env=environment, capture_output=True, timeout=5)
        assert after.returncode == 0, after.stderr.decode()
    finally:
        for run in runs:
            if run.poll() is None:
                run.kill()
                run.communicate(timeout=5)

print("Test runner checks passed: serialization, arguments, failure status, cancellation and lock release")
