"""Read-only by default; --write explicitly tests transitions and restores settings."""
import argparse
import json
import os
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("app", type=Path)
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
helpers = args.app.resolve() / "Contents/Helpers"
environment = dict(os.environ, DYLD_INSERT_LIBRARIES=str(helpers / "ComboAirPodsContext.dylib"))


def run(*arguments):
    result = subprocess.run([str(helpers / "ComboAirPodsHelper"), *arguments],
                            env=environment, capture_output=True, timeout=6, check=True)
    reply = json.loads(result.stdout)
    for field in ("available", "canSetMode", "canSetConversation", "attempted", "verified"):
        assert isinstance(reply[field], bool), f"Invalid boolean wire type: {field}"
    assert not any("tracking" in key.lower() or "spatial" in key.lower() for key in reply), "Spatial monitoring must stay removed"
    return reply


original = run("--status")
assert original["available"], "Connect a supported Bluetooth audio output first"
assert original["mode"] in original["modes"]
assert isinstance(original.get("conversation"), bool)
print("PASS: connected output, listening modes and conversation state")
if not args.write:
    raise SystemExit(0)

target = (str(original["deviceID"]), original["target"])
stale = run("--conversation", "on", target[0], "0" * 64)
assert not stale["attempted"] and stale["error"] == "device_changed"
print("PASS: stale device token rejected before writing")
commands = [("--mode", "mode", value) for value in original["modes"] if value != original["mode"] and value != "off"]
commands += [("--conversation", "conversation", not original["conversation"])]
print("Spatial audio is not monitored; Off listening mode is not exposed by this panel")


def encoded(value):
    return ("on" if value else "off") if isinstance(value, bool) else value


failures = []
for command, field, desired in commands:
    try:
        before = run("--status")
        assert (str(before["deviceID"]), before["target"]) == target, "Output changed; test stopped"
        assert before[field] == original[field], "Settings changed externally; test stopped"
        try:
            result = run(command, encoded(desired), *target)
            fresh = run("--status")
            confirmed = result["attempted"] and result["verified"] and not result.get("error") and fresh.get(field) == desired
            print(f'{"PASS" if confirmed else "UNCONFIRMED"}: {field} -> {desired}')
            if not confirmed:
                failures.append(field + ":" + str(desired))
        finally:
            restored = run(command, encoded(original[field]), *target)
            fresh = run("--status")
            assert restored["verified"] and fresh.get(field) == original[field], f"RESTORE FAILED: {field}; inspect system Sound settings"
            print(f"PASS: restored {field}")
    except BaseException:
        print("Stopped: inspect current output and settings before another test.")
        raise
if failures:
    raise SystemExit("Unconfirmed transitions: " + ", ".join(failures))
print("PASS: all tested transitions confirmed by a fresh process; original settings restored")
