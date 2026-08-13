#!/usr/bin/env python3
"""Validate a hardware-wiring Visio drawing specification against its netlist."""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class Box:
    identifier: str
    x1: float
    y1: float
    x2: float
    y2: float

    @property
    def center(self) -> Point:
        return Point((self.x1 + self.x2) / 2, (self.y1 + self.y2) / 2)


@dataclass(frozen=True)
class Segment:
    a: Point
    b: Point
    route: str

    @property
    def horizontal(self) -> bool:
        return math.isclose(self.a.y, self.b.y, abs_tol=1e-9)

    @property
    def vertical(self) -> bool:
        return math.isclose(self.a.x, self.b.x, abs_tol=1e-9)


def get_pin(netlist: dict, endpoint: str) -> dict | None:
    if ":" not in endpoint:
        return None
    component, pin = endpoint.split(":", 1)
    return netlist.get("components", {}).get(component, {}).get("pins", {}).get(pin)


def to_box(item: dict) -> Box:
    x, y = float(item["x"]), float(item["y"])
    width, height = float(item["width"]), float(item["height"])
    return Box(str(item["id"]), x, y, x + width, y + height)


def closest_boundary_point(box: Box, toward: Point) -> Point:
    center = box.center
    dx, dy = toward.x - center.x, toward.y - center.y
    if math.isclose(dx, 0.0) and math.isclose(dy, 0.0):
        return center
    scale_x = (box.x2 - box.x1) / 2 / abs(dx) if not math.isclose(dx, 0.0) else math.inf
    scale_y = (box.y2 - box.y1) / 2 / abs(dy) if not math.isclose(dy, 0.0) else math.inf
    scale = min(scale_x, scale_y)
    return Point(center.x + dx * scale, center.y + dy * scale)


def route_segments(route: dict, terminals: dict[str, Box]) -> list[Segment]:
    waypoints = [Point(float(point[0]), float(point[1])) for point in route.get("waypoints", [])]
    source = terminals[route["from"]]
    destination = terminals[route["to"]]
    if waypoints:
        start = closest_boundary_point(source, waypoints[0])
        end = closest_boundary_point(destination, waypoints[-1])
        points = [start, *waypoints, end]
    else:
        start = closest_boundary_point(source, destination.center)
        end = closest_boundary_point(destination, source.center)
        points = [start, end]
    return [Segment(a, b, route["id"]) for a, b in zip(points, points[1:]) if a != b]


def boxes_overlap(first: Box, second: Box, clearance: float) -> bool:
    return first.x1 < second.x2 + clearance and first.x2 + clearance > second.x1 and first.y1 < second.y2 + clearance and first.y2 + clearance > second.y1


def overlap(first: Segment, second: Segment, tolerance: float) -> bool:
    if first.horizontal and second.horizontal and abs(first.a.y - second.a.y) <= tolerance:
        return min(max(first.a.x, first.b.x), max(second.a.x, second.b.x)) - max(min(first.a.x, first.b.x), min(second.a.x, second.b.x)) > tolerance
    if first.vertical and second.vertical and abs(first.a.x - second.a.x) <= tolerance:
        return min(max(first.a.y, first.b.y), max(second.a.y, second.b.y)) - max(min(first.a.y, first.b.y), min(second.a.y, second.b.y)) > tolerance
    return False


def crossing(first: Segment, second: Segment, tolerance: float) -> Point | None:
    horizontal, vertical = (first, second) if first.horizontal and second.vertical else (second, first) if second.horizontal and first.vertical else (None, None)
    if horizontal is None:
        return None
    x, y = vertical.a.x, horizontal.a.y
    hx1, hx2 = sorted((horizontal.a.x, horizontal.b.x))
    vy1, vy2 = sorted((vertical.a.y, vertical.b.y))
    if hx1 + tolerance < x < hx2 - tolerance and vy1 + tolerance < y < vy2 - tolerance:
        return Point(x, y)
    return None


def segment_hits_box(segment: Segment, box: Box, tolerance: float) -> bool:
    if segment.horizontal:
        return box.y1 + tolerance < segment.a.y < box.y2 - tolerance and max(min(segment.a.x, segment.b.x), box.x1) < min(max(segment.a.x, segment.b.x), box.x2)
    if segment.vertical:
        return box.x1 + tolerance < segment.a.x < box.x2 - tolerance and max(min(segment.a.y, segment.b.y), box.y1) < min(max(segment.a.y, segment.b.y), box.y2)
    return True


def validate_electrical(connection: dict, source: dict, destination: dict, errors: list[str], voltage_tolerance: float = 0.15) -> None:
    identifier = connection.get("id", "<unnamed>")
    source_voltage, destination_voltage = source.get("voltage"), destination.get("voltage")
    if source_voltage is not None and destination_voltage is not None and abs(float(source_voltage) - float(destination_voltage)) > voltage_tolerance:
        errors.append(f"{identifier}: voltage mismatch {source_voltage} V vs {destination_voltage} V")
    source_direction, destination_direction = source.get("direction"), destination.get("direction")
    if source_direction == destination_direction == "out":
        errors.append(f"{identifier}: two outputs are connected")
    if source_direction == destination_direction == "power-out":
        errors.append(f"{identifier}: two power outputs are connected")
    protocol = str(connection.get("protocol", "")).lower()
    source_signal, destination_signal = str(source.get("signal", "")).upper(), str(destination.get("signal", "")).upper()
    if protocol == "uart":
        source_role = "TX" if "TX" in source_signal else "RX" if "RX" in source_signal else source_signal
        destination_role = "TX" if "TX" in destination_signal else "RX" if "RX" in destination_signal else destination_signal
        if {source_role, destination_role} != {"TX", "RX"}:
            errors.append(f"{identifier}: UART must connect TX to RX")
        if {source_direction, destination_direction} != {"in", "out"}:
            errors.append(f"{identifier}: UART directions must be one output and one input")
    if protocol == "ground" and not (source_direction == destination_direction == "ground"):
        errors.append(f"{identifier}: ground net must connect ground terminals")


def validate(spec_path: Path, netlist_path: Path, tolerance: float = 0.01) -> dict:
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    netlist = json.loads(netlist_path.read_text(encoding="utf-8"))
    errors: list[str] = []
    warnings: list[str] = []
    page = spec.get("page", {})
    page_width = float(page.get("width_in", 0))
    page_height = float(page.get("height_in", 0))
    crossing_policy = str(page.get("crossing_policy", "forbid"))
    if page_width <= 0 or page_height <= 0:
        errors.append("page width_in and height_in must be positive")
    if crossing_policy not in {"forbid", "gap", "arc"}:
        errors.append("page crossing_policy must be forbid, gap, or arc")

    terminals: dict[str, Box] = {}
    terminal_identifiers: list[str] = []
    for item in spec.get("terminals", []):
        identifier = str(item.get("id", ""))
        terminal_identifiers.append(identifier)
        if not identifier:
            errors.append("terminal without id")
            continue
        if identifier in terminals:
            errors.append(f"duplicate terminal id: {identifier}")
        try:
            box = to_box(item)
        except (KeyError, TypeError, ValueError):
            errors.append(f"terminal {identifier}: invalid bounds")
            continue
        terminals[identifier] = box
        if get_pin(netlist, identifier) is None:
            errors.append(f"terminal {identifier}: absent from netlist")
        if box.x1 < 0 or box.y1 < 0 or box.x2 > page_width or box.y2 > page_height:
            errors.append(f"terminal {identifier}: outside page")
    duplicate_terminal_ids = sorted({identifier for identifier in terminal_identifiers if identifier and terminal_identifiers.count(identifier) > 1})
    for identifier in duplicate_terminal_ids:
        errors.append(f"duplicate terminal id: {identifier}")

    labels: list[Box] = []
    for item in spec.get("labels", []):
        try:
            box = to_box(item)
        except (KeyError, TypeError, ValueError):
            errors.append(f"label {item.get('id', '<unnamed>')}: invalid bounds")
            continue
        labels.append(box)
        if box.x1 < 0 or box.y1 < 0 or box.x2 > page_width or box.y2 > page_height:
            errors.append(f"label {box.identifier}: outside page")

    images: list[Box] = []
    for item in spec.get("images", []):
        try:
            box = to_box(item)
        except (KeyError, TypeError, ValueError):
            errors.append(f"image {item.get('id', '<unnamed>')}: invalid bounds")
            continue
        images.append(box)
        if box.x1 < 0 or box.y1 < 0 or box.x2 > page_width or box.y2 > page_height:
            errors.append(f"image {box.identifier}: outside page")
        source = item.get("path")
        if not source:
            errors.append(f"image {box.identifier}: missing path")
        else:
            source_path = Path(source)
            if not source_path.is_absolute():
                source_path = spec_path.parent / source_path
            if not source_path.exists():
                errors.append(f"image {box.identifier}: source file not found: {source}")

    connection_by_id = {connection.get("id"): connection for connection in netlist.get("connections", []) if connection.get("id")}
    referenced_endpoints = {
        endpoint
        for connection in connection_by_id.values()
        for endpoint in (connection.get("from"), connection.get("to"))
        if endpoint
    }
    extra_terminals = sorted(set(terminals) - referenced_endpoints)
    missing_terminals = sorted(referenced_endpoints - set(terminals))
    for identifier in extra_terminals:
        errors.append(f"terminal {identifier}: not referenced by any netlist connection")
    for identifier in missing_terminals:
        errors.append(f"netlist endpoint {identifier}: missing terminal shape")
    route_ids: set[str] = set()
    all_segments: list[Segment] = []
    routes = spec.get("routes", [])
    for route in routes:
        identifier = str(route.get("id", ""))
        if not identifier:
            errors.append("route without id")
            continue
        if identifier in route_ids:
            errors.append(f"duplicate route id: {identifier}")
        route_ids.add(identifier)
        connection = connection_by_id.get(identifier)
        if connection is None:
            errors.append(f"route {identifier}: absent from netlist")
            continue
        source_pin = get_pin(netlist, str(connection.get("from", "")))
        destination_pin = get_pin(netlist, str(connection.get("to", "")))
        if source_pin is None or destination_pin is None:
            errors.append(f"route {identifier}: netlist contains an unknown endpoint")
        else:
            validate_electrical(connection, source_pin, destination_pin, errors)
        if route.get("from") != connection.get("from") or route.get("to") != connection.get("to"):
            errors.append(f"route {identifier}: endpoints do not match netlist")
        if route.get("from") not in terminals or route.get("to") not in terminals:
            errors.append(f"route {identifier}: missing terminal shape")
            continue
        segments = route_segments(route, terminals)
        if not segments:
            errors.append(f"route {identifier}: no geometry")
        for segment in segments:
            if not (segment.horizontal or segment.vertical):
                errors.append(f"route {identifier}: segment is not orthogonal")
        all_segments.extend(segments)

    missing_routes = sorted(set(connection_by_id) - route_ids)
    for identifier in missing_routes:
        errors.append(f"netlist connection {identifier}: absent from Visio spec")

    for index, first in enumerate(all_segments):
        for second in all_segments[index + 1 :]:
            if first.route == second.route:
                continue
            if overlap(first, second, tolerance):
                errors.append(f"routes {first.route} and {second.route} overlap")
            point = crossing(first, second, tolerance)
            if point:
                message = f"routes {first.route} and {second.route} cross at {point.x:g},{point.y:g}"
                if crossing_policy == "forbid":
                    errors.append(message)
                else:
                    warnings.append(f"{message}; rendered with {crossing_policy} crossing style")

    keepouts = []
    for item in spec.get("keepouts", []):
        try:
            keepouts.append(to_box(item))
        except (KeyError, TypeError, ValueError):
            errors.append(f"keepout {item.get('id', '<unnamed>')}: invalid bounds")
    terminal_boxes = list(terminals.values())
    for index, first in enumerate(terminal_boxes):
        for second in terminal_boxes[index + 1 :]:
            if boxes_overlap(first, second, 0.0):
                errors.append(f"terminals {first.identifier} and {second.identifier} overlap")
    for segment in all_segments:
        for box in [*keepouts, *labels]:
            if segment_hits_box(segment, box, tolerance):
                errors.append(f"route {segment.route} enters protected region {box.identifier}")

    errors = sorted(set(errors))
    return {
        "status": "passed" if not errors else "failed",
        "spec": str(spec_path),
        "netlist": str(netlist_path),
        "counts": {"terminals": len(terminals), "labels": len(labels), "images": len(images), "routes": len(routes), "segments": len(all_segments), "keepouts": len(keepouts)},
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path)
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    report = validate(args.spec.resolve(), args.netlist.resolve())
    output = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.write_text(output + "\n", encoding="utf-8")
    print(output)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
