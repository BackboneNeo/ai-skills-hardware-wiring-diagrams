import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "assets" / "annotated-example.visio.json"
NETLIST_PATH = ROOT / "assets" / "example-netlist.json"
MODULE_PATH = ROOT / "scripts" / "validate_visio_spec.py"

module_spec = importlib.util.spec_from_file_location("validate_visio_spec", MODULE_PATH)
validator = importlib.util.module_from_spec(module_spec)
assert module_spec.loader is not None
sys.modules[module_spec.name] = validator
module_spec.loader.exec_module(validator)


class VisioSpecValidationTests(unittest.TestCase):
    def test_bundled_example_passes(self):
        report = validator.validate(SPEC_PATH, NETLIST_PATH)
        self.assertEqual("passed", report["status"], report["errors"])
        self.assertEqual(3, report["counts"]["routes"])

    def test_overlapping_routes_fail(self):
        drawing = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        drawing["routes"][1]["waypoints"] = [[9.75, 1.86], [3.25, 1.86]]
        drawing["images"] = []
        with tempfile.TemporaryDirectory() as temp_dir:
            changed = Path(temp_dir) / "overlap.json"
            changed.write_text(json.dumps(drawing), encoding="utf-8")
            report = validator.validate(changed, NETLIST_PATH)
        self.assertEqual("failed", report["status"])
        self.assertTrue(any("overlap" in error for error in report["errors"]))

    def test_missing_netlist_route_fails(self):
        drawing = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        drawing["routes"] = drawing["routes"][:-1]
        drawing["images"] = []
        with tempfile.TemporaryDirectory() as temp_dir:
            changed = Path(temp_dir) / "missing.json"
            changed.write_text(json.dumps(drawing), encoding="utf-8")
            report = validator.validate(changed, NETLIST_PATH)
        self.assertEqual("failed", report["status"])
        self.assertTrue(any("absent from Visio spec" in error for error in report["errors"]))

    def test_missing_terminal_fails(self):
        drawing = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        drawing["terminals"] = [terminal for terminal in drawing["terminals"] if terminal["id"] != "imu:3"]
        drawing["images"] = []
        with tempfile.TemporaryDirectory() as temp_dir:
            changed = Path(temp_dir) / "missing-terminal.json"
            changed.write_text(json.dumps(drawing), encoding="utf-8")
            report = validator.validate(changed, NETLIST_PATH)
        self.assertEqual("failed", report["status"])
        self.assertTrue(any("missing terminal shape" in error for error in report["errors"]))

    def test_explicit_gap_crossing_is_warning_not_error(self):
        drawing = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        drawing["page"]["crossing_policy"] = "gap"
        drawing["images"] = []
        drawing["routes"][1]["waypoints"] = [
            [9.75, 3.31],
            [6.5, 3.31],
            [6.5, 1.2],
            [3.25, 1.2],
            [3.25, 3.31],
        ]
        with tempfile.TemporaryDirectory() as temp_dir:
            changed = Path(temp_dir) / "crossing.json"
            changed.write_text(json.dumps(drawing), encoding="utf-8")
            report = validator.validate(changed, NETLIST_PATH)
        self.assertEqual("passed", report["status"], report["errors"])
        self.assertTrue(any("rendered with gap" in warning for warning in report["warnings"]))

    def test_uart_tx_to_tx_fails(self):
        netlist = json.loads(NETLIST_PATH.read_text(encoding="utf-8"))
        netlist["components"]["imu"]["pins"]["5"] = {"signal": "UART_TX", "direction": "out", "voltage": 3.3}
        with tempfile.TemporaryDirectory() as temp_dir:
            changed = Path(temp_dir) / "bad-netlist.json"
            changed.write_text(json.dumps(netlist), encoding="utf-8")
            report = validator.validate(SPEC_PATH, changed)
        self.assertEqual("failed", report["status"])
        self.assertTrue(any("UART must connect TX to RX" in error for error in report["errors"]))


if __name__ == "__main__":
    unittest.main()
