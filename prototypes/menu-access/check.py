"""Run after building MenuProbe; no AX queries or permission prompts."""
from pathlib import Path
import subprocess
binary = Path(__file__).parent / 'MenuProbe'
assert binary.exists(), 'Build MenuProbe first'
for args, expected in [([], 0), (['--help'], 0), (['--press'], 64), (['--press', ''], 64), (['--list', 'extra'], 64), (['--unknown'], 64), (['--self-test'], 0)]:
    result = subprocess.run([str(binary.resolve()), *args], capture_output=True, text=True)
    assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
print('PASS: command guards and target-selection checks; no live AX calls')
