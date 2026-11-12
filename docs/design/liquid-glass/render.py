"""Export interface and icon designs with one shared settings source."""

import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
DESIGNS = {
    "panel": ("sources/combo-panel-liquid-glass.html", "combo-panel-liquid-glass.html", "Combo · 融合面板与详情设计"),
    "settings": ("sources/combo-settings-liquid-glass.html", "combo-settings-liquid-glass.html", "Combo · 设置页设计"),
    "onboarding": ("sources/combo-onboarding-liquid-glass.html", "combo-onboarding-liquid-glass.html", "Combo · 引导设计"),
    "central": ("icons/sources/central.html", "icons/central.html", "Combo · 中央图标设计"),
    "audio": ("icons/sources/audio.html", "icons/audio.html", "Combo · 音频图标与充电状态"),
}
SETTINGS_INCLUDE = "<!-- include: combo-settings-liquid-glass.html -->"


def source(name):
    fragment = (ROOT / DESIGNS[name][0]).read_text()
    return fragment.replace(SETTINGS_INCLUDE, source("settings")) if name == "panel" else fragment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("renderer", type=Path, help="path to visualize/scripts/render.py")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="combo-design-") as directory:
        for name, (_, filename, title) in DESIGNS.items():
            fragment = Path(directory) / Path(filename).name
            fragment.write_text(source(name))
            subprocess.run(
                [sys.executable, str(args.renderer), str(fragment), str(ROOT / filename),
                 "--title", title, "--force"],
                check=True,
            )


if __name__ == "__main__":
    main()
