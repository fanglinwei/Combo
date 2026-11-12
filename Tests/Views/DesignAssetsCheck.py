"""Check interface/icon exports, shared settings and the canonical AppIcon."""

from html.parser import HTMLParser
from pathlib import Path
import runpy
import struct
import json
import re

ROOT = Path(__file__).resolve().parents[2]
DESIGN = ROOT / "docs/design/liquid-glass"
exporter = runpy.run_path(str(DESIGN / "render.py"))


class Preview(HTMLParser):
    def handle_starttag(self, tag, attributes):
        if tag == "iframe":
            self.document = dict(attributes)["data-srcdoc"]


panel = (DESIGN / "sources/combo-panel-liquid-glass.html").read_text()
assert panel.count(exporter["SETTINGS_INCLUDE"]) == 1
settings = exporter["source"]("settings")
assert settings not in panel, "Edit only the shared settings source"
assert exporter["source"]("panel").count(settings) == 1
for name, (_, filename, _) in exporter["DESIGNS"].items():
    preview = Preview()
    preview.feed((DESIGN / filename).read_text())
    assert exporter["source"](name) in preview.document, f"Stale {name} export"

icons = DESIGN / "icons"
assert (icons / "combo-app-icon.svg").is_file()
icon = (icons / "combo-app-icon.png").read_bytes()
assert struct.unpack(">II", icon[16:24]) == (1024, 1024)
native = ROOT / "Combo/App/Media.xcassets/AppIcon.appiconset"
assert icon == (native / "icon_512x512@2x.png").read_bytes()
assert not list(icons.glob("combo-app-icon-*.png")), "Keep size variants in the native catalog"
for name, count in [("central", 49), ("audio", 39)]:
    fragment = exporter["source"](name)
    models = json.JSONDecoder().raw_decode(fragment[re.search(r"const models\s*=\s*", fragment).end():])[0]
    assert len(models) == count, f"Missing {name} designs"
    if name == "audio":
        charges = [item.get("charge") for model in models for item in model["items"]]
        assert "charging" in charges and "full" in charges
assert len(json.loads((icons / "central-symbols.json").read_text())) == 49
assert len(json.loads((icons / "audio-symbols.json").read_text())) == 25
print("PASS: shared settings, five current exports, AppIcon and central/audio/charging designs")
