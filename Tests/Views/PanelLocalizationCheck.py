"""Every literal used by the panel/detail views must exist in both string tables."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIEWS = ["PanelView", "BatterySections", "WiFiSections", "SoundSections", "Theme"]


def literal(source, start):
    parts = []
    index = start + 1
    while index < len(source):
        if source[index] == '"':
            return "".join(parts)
        if source.startswith("\\(", index):
            depth = 1
            index += 2
            while depth and index < len(source):
                if source[index] == '"':
                    index = skip_string(source, index)
                    continue
                if source[index] == "(":
                    depth += 1
                elif source[index] == ")":
                    depth -= 1
                index += 1
            parts.append("<argument>")
        elif source[index] == "\\":
            escaped = source[index + 1]
            parts.append({"n": "\n", "t": "\t", "r": "\r"}.get(escaped, escaped))
            index += 2
        else:
            parts.append(source[index])
            index += 1
    raise AssertionError("Unclosed Swift string")


def skip_string(source, start):
    index = start + 1
    while index < len(source):
        if source[index] == "\\":
            index += 2
        elif source[index] == '"':
            return index + 1
        else:
            index += 1
    raise AssertionError("Unclosed interpolation string")


def template(key):
    return re.sub(r"%(?:lld|ld|d|@)", "<argument>", key).replace("%%", "%")


for language in ("zh-Hans", "en"):
    table = (ROOT / "Combo" / "Localization" / f"{language}.lproj" / "Localizable.strings").read_text()
    keys = {template(json.loads(match.group(1))) for match in re.finditer(r'("(?:\\.|[^"\\])*")\s*=', table)}
    missing = []
    for view in VIEWS:
        source = (ROOT / "Combo" / "Views" / f"{view}.swift").read_text()
        for match in re.finditer(r'\bL\("', source):
            key = literal(source, match.end() - 1)
            if key not in keys:
                missing.append(f"{view}: {key}")
    assert not missing, f"Missing {language} translations:\n" + "\n".join(sorted(set(missing)))
print("PASS: panel and detail source literals exist in both localization tables")
