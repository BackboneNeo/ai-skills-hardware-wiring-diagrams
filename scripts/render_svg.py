#!/usr/bin/env python3
"""Render an SVG to PNG or PDF using CairoSVG or Inkscape."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("svg", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--dpi", type=int, default=150)
    args = parser.parse_args()
    suffix = args.output.suffix.lower()
    if suffix not in {".png", ".pdf"}:
        parser.error("output must end in .png or .pdf")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        import cairosvg  # type: ignore

        if suffix == ".png":
            cairosvg.svg2png(url=str(args.svg.resolve()), write_to=str(args.output.resolve()), dpi=args.dpi)
        else:
            cairosvg.svg2pdf(url=str(args.svg.resolve()), write_to=str(args.output.resolve()), dpi=args.dpi)
        print(args.output)
        return 0
    except ImportError:
        pass
    inkscape = shutil.which("inkscape")
    if inkscape:
        subprocess.run(
            [inkscape, str(args.svg.resolve()), f"--export-filename={args.output.resolve()}", f"--export-dpi={args.dpi}"],
            check=True,
        )
        print(args.output)
        return 0

    if suffix == ".png":
        node = shutil.which("node")
        node_modules = os.environ.get("NODE_PATH")
        bundled_node_root = Path.home() / ".cache" / "codex-runtimes" / "codex-primary-runtime" / "dependencies" / "node"
        if not node:
            for candidate in (bundled_node_root / "bin" / "node.exe", bundled_node_root / "bin" / "node"):
                if candidate.exists():
                    node = str(candidate)
                    break
        if not node_modules and (bundled_node_root / "node_modules").is_dir():
            node_modules = str(bundled_node_root / "node_modules")
        if node and node_modules:
            script = """const sharp=require('sharp');
const [input,output,dpi]=process.argv.slice(2);
sharp(input,{density:Number(dpi)}).png().toFile(output).catch(error=>{console.error(error);process.exit(1)});
"""
            with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as handle:
                handle.write(script)
                script_path = Path(handle.name)
            try:
                environment = dict(os.environ)
                environment["NODE_PATH"] = node_modules
                subprocess.run([node, str(script_path), str(args.svg.resolve()), str(args.output.resolve()), str(args.dpi)], check=True, env=environment)
                print(args.output)
                return 0
            finally:
                script_path.unlink(missing_ok=True)
    raise SystemExit("Install CairoSVG or Inkscape; PNG output also supports Node.js plus sharp through NODE_PATH")


if __name__ == "__main__":
    raise SystemExit(main())
