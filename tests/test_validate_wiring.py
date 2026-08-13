from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from validate_wiring import validate  # noqa: E402


class WiringValidatorTests(unittest.TestCase):
    def test_bundled_example_passes(self) -> None:
        report = validate(ROOT / "assets" / "annotated-example.svg", ROOT / "assets" / "example-netlist.json", 1.5, 0.1, 0.15)
        self.assertEqual("passed", report["status"], report["errors"])

    def test_overlap_and_keepout_fail(self) -> None:
        svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
          <rect data-terminal="a:1" x="0" y="10" width="10" height="20"/>
          <rect data-terminal="b:1" x="100" y="10" width="10" height="20"/>
          <rect data-terminal="c:1" x="0" y="10" width="10" height="20"/>
          <rect data-terminal="d:1" x="100" y="10" width="10" height="20"/>
          <rect data-keepout="label" x="45" y="15" width="20" height="10"/>
          <path data-net="one" data-from="a:1" data-to="b:1" d="M10 20 H100"/>
          <path data-net="two" data-from="c:1" data-to="d:1" d="M10 20 H100"/>
        </svg>"""
        netlist = {
            "schema_version": 1,
            "components": {
                name: {"pins": {"1": {"signal": "GPIO", "direction": "bidirectional", "voltage": 3.3}}}
                for name in ("a", "b", "c", "d")
            },
            "connections": [
                {"id": "one", "from": "a:1", "to": "b:1", "protocol": "gpio"},
                {"id": "two", "from": "c:1", "to": "d:1", "protocol": "gpio"},
            ],
        }
        report = self._validate_text(svg, netlist)
        self.assertEqual("failed", report["status"])
        self.assertTrue(any("overlap" in error for error in report["errors"]))
        self.assertTrue(any("keep-out" in error for error in report["errors"]))

    def test_uart_tx_to_tx_fails(self) -> None:
        svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
          <rect data-terminal="a:1" x="0" y="10" width="10" height="20"/>
          <rect data-terminal="b:1" x="100" y="10" width="10" height="20"/>
          <path data-net="uart" data-from="a:1" data-to="b:1" d="M10 20 H100"/>
        </svg>"""
        netlist = {
            "schema_version": 1,
            "components": {
                "a": {"pins": {"1": {"signal": "UART_TX", "direction": "out", "voltage": 3.3}}},
                "b": {"pins": {"1": {"signal": "UART_TX", "direction": "out", "voltage": 3.3}}},
            },
            "connections": [{"id": "uart", "from": "a:1", "to": "b:1", "protocol": "uart"}],
        }
        report = self._validate_text(svg, netlist)
        self.assertEqual("failed", report["status"])
        self.assertTrue(any("UART must connect TX to RX" in error for error in report["errors"]))
        self.assertTrue(any("two outputs" in error for error in report["errors"]))

    def test_dangling_endpoint_fails(self) -> None:
        svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
          <rect data-terminal="a:1" x="0" y="10" width="10" height="20"/>
          <rect data-terminal="b:1" x="100" y="10" width="10" height="20"/>
          <path data-net="wire" data-from="a:1" data-to="b:1" d="M10 20 H80"/>
        </svg>"""
        netlist = {
            "schema_version": 1,
            "components": {
                "a": {"pins": {"1": {"signal": "GPIO", "direction": "out", "voltage": 3.3}}},
                "b": {"pins": {"1": {"signal": "GPIO", "direction": "in", "voltage": 3.3}}},
            },
            "connections": [{"id": "wire", "from": "a:1", "to": "b:1", "protocol": "gpio"}],
        }
        report = self._validate_text(svg, netlist)
        self.assertTrue(any("do not touch" in error for error in report["errors"]))

    def _validate_text(self, svg_text: str, netlist: dict) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            svg_path = directory_path / "diagram.svg"
            netlist_path = directory_path / "netlist.json"
            svg_path.write_text(svg_text, encoding="utf-8")
            netlist_path.write_text(json.dumps(netlist), encoding="utf-8")
            return validate(svg_path, netlist_path, 1.5, 0.1, 0.15)


if __name__ == "__main__":
    unittest.main()
