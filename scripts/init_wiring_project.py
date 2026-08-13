#!/usr/bin/env python3
"""Create an editable A3 SVG and starter netlist from the bundled assets."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--title", default="Hardware wiring diagram")
    args = parser.parse_args()
    skill_root = Path(__file__).resolve().parent.parent
    args.output.mkdir(parents=True, exist_ok=True)
    svg_destination = args.output / "wiring-diagram.svg"
    netlist_destination = args.output / "wiring-netlist.json"
    svg_text = (skill_root / "assets" / "wiring-a3-template.svg").read_text(encoding="utf-8")
    svg_text = svg_text.replace("PROJECT · Hardware wiring diagram", args.title)
    svg_destination.write_text(svg_text, encoding="utf-8")
    shutil.copy2(skill_root / "assets" / "example-netlist.json", netlist_destination)
    print(json.dumps({"svg": str(svg_destination), "netlist": str(netlist_destination)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
