#!/usr/bin/env python3
"""Validate annotated SVG wiring geometry against a JSON connection netlist."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
TOKEN_RE = re.compile(rf"[MmLlHhVvZz]|{NUMBER}")
TRANSLATE_RE = re.compile(rf"translate\s*\(\s*({NUMBER})(?:[ ,]+({NUMBER}))?\s*\)")


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class Segment:
    a: Point
    b: Point
    net: str

    @property
    def horizontal(self) -> bool:
        return math.isclose(self.a.y, self.b.y, abs_tol=1e-9)

    @property
    def vertical(self) -> bool:
        return math.isclose(self.a.x, self.b.x, abs_tol=1e-9)


@dataclass(frozen=True)
class Terminal:
    name: str
    shape: str
    bounds: tuple[float, float, float, float]
    center: Point
    radius: float | None
    signal: str | None


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def translate_value(value: str | None) -> tuple[float, float, list[str]]:
    if not value:
        return 0.0, 0.0, []
    warnings: list[str] = []
    matches = list(TRANSLATE_RE.finditer(value))
    stripped = TRANSLATE_RE.sub("", value).strip(" ,")
    if stripped:
        warnings.append(f"unsupported transform ignored: {value}")
    x = sum(float(match.group(1)) for match in matches)
    y = sum(float(match.group(2) or 0.0) for match in matches)
    return x, y, warnings


def parse_path(path_data: str, tx: float, ty: float, net: str) -> tuple[list[Segment], list[str]]:
    tokens = TOKEN_RE.findall(path_data.replace(",", " "))
    segments: list[Segment] = []
    errors: list[str] = []
    current = Point(0.0, 0.0)
    start = current
    command = ""
    index = 0

    def number() -> float:
        nonlocal index
        if index >= len(tokens) or re.fullmatch(r"[A-Za-z]", tokens[index]):
            raise ValueError("missing coordinate")
        result = float(tokens[index])
        index += 1
        return result

    try:
        while index < len(tokens):
            if re.fullmatch(r"[A-Za-z]", tokens[index]):
                command = tokens[index]
                index += 1
            if not command:
                raise ValueError("path does not start with a command")
            relative = command.islower()
            upper = command.upper()
            previous = current
            if upper in {"M", "L"}:
                x, y = number(), number()
                current = Point(previous.x + x, previous.y + y) if relative else Point(x, y)
                if upper == "M":
                    start = current
                    command = "l" if relative else "L"
                else:
                    segments.append(Segment(Point(previous.x + tx, previous.y + ty), Point(current.x + tx, current.y + ty), net))
            elif upper == "H":
                x = number()
                current = Point(previous.x + x if relative else x, previous.y)
                segments.append(Segment(Point(previous.x + tx, previous.y + ty), Point(current.x + tx, current.y + ty), net))
            elif upper == "V":
                y = number()
                current = Point(previous.x, previous.y + y if relative else y)
                segments.append(Segment(Point(previous.x + tx, previous.y + ty), Point(current.x + tx, current.y + ty), net))
            elif upper == "Z":
                current = start
                segments.append(Segment(Point(previous.x + tx, previous.y + ty), Point(current.x + tx, current.y + ty), net))
                command = ""
            else:
                raise ValueError(f"unsupported path command {command}")
    except ValueError as exc:
        errors.append(f"route {net}: {exc}")
    return [segment for segment in segments if segment.a != segment.b], errors


def terminal_from_element(element: ET.Element, tx: float, ty: float) -> Terminal | None:
    name = element.get("data-terminal")
    if not name:
        return None
    shape = local_name(element.tag)
    signal = element.get("data-signal")
    if shape == "rect":
        x = float(element.get("x", 0)) + tx
        y = float(element.get("y", 0)) + ty
        width = float(element.get("width", 0))
        height = float(element.get("height", 0))
        return Terminal(name, shape, (x, y, x + width, y + height), Point(x + width / 2, y + height / 2), None, signal)
    if shape == "circle":
        cx = float(element.get("cx", 0)) + tx
        cy = float(element.get("cy", 0)) + ty
        radius = float(element.get("r", 0))
        return Terminal(name, shape, (cx - radius, cy - radius, cx + radius, cy + radius), Point(cx, cy), radius, signal)
    return None


def endpoint_distance(point: Point, terminal: Terminal) -> float:
    if terminal.shape == "circle" and terminal.radius is not None:
        return abs(math.hypot(point.x - terminal.center.x, point.y - terminal.center.y) - terminal.radius)
    x1, y1, x2, y2 = terminal.bounds
    if x1 <= point.x <= x2 and y1 <= point.y <= y2:
        return min(point.x - x1, x2 - point.x, point.y - y1, y2 - point.y)
    dx = max(x1 - point.x, 0.0, point.x - x2)
    dy = max(y1 - point.y, 0.0, point.y - y2)
    return math.hypot(dx, dy)


def segment_overlap(first: Segment, second: Segment, tolerance: float) -> bool:
    if first.horizontal and second.horizontal and abs(first.a.y - second.a.y) <= tolerance:
        left = max(min(first.a.x, first.b.x), min(second.a.x, second.b.x))
        right = min(max(first.a.x, first.b.x), max(second.a.x, second.b.x))
        return right - left > tolerance
    if first.vertical and second.vertical and abs(first.a.x - second.a.x) <= tolerance:
        top = max(min(first.a.y, first.b.y), min(second.a.y, second.b.y))
        bottom = min(max(first.a.y, first.b.y), max(second.a.y, second.b.y))
        return bottom - top > tolerance
    return False


def strict_crossing(first: Segment, second: Segment, tolerance: float) -> Point | None:
    horizontal, vertical = (first, second) if first.horizontal and second.vertical else (second, first) if second.horizontal and first.vertical else (None, None)
    if horizontal is None:
        return None
    x = vertical.a.x
    y = horizontal.a.y
    h1, h2 = sorted((horizontal.a.x, horizontal.b.x))
    v1, v2 = sorted((vertical.a.y, vertical.b.y))
    if h1 + tolerance < x < h2 - tolerance and v1 + tolerance < y < v2 - tolerance:
        return Point(x, y)
    return None


def segment_hits_box(segment: Segment, box: tuple[float, float, float, float], tolerance: float) -> bool:
    x1, y1, x2, y2 = box
    if segment.horizontal:
        return y1 + tolerance < segment.a.y < y2 - tolerance and max(min(segment.a.x, segment.b.x), x1) < min(max(segment.a.x, segment.b.x), x2)
    if segment.vertical:
        return x1 + tolerance < segment.a.x < x2 - tolerance and max(min(segment.a.y, segment.b.y), y1) < min(max(segment.a.y, segment.b.y), y2)
    return True


def load_svg(svg_path: Path) -> tuple[dict[str, Terminal], dict[str, list[Segment]], dict[str, dict[str, str]], list[tuple[str, tuple[float, float, float, float]]], list[str], list[str]]:
    root = ET.parse(svg_path).getroot()
    terminals: dict[str, Terminal] = {}
    routes: dict[str, list[Segment]] = {}
    route_meta: dict[str, dict[str, str]] = {}
    keepouts: list[tuple[str, tuple[float, float, float, float]]] = []
    errors: list[str] = []
    warnings: list[str] = []

    def visit(element: ET.Element, parent_tx: float, parent_ty: float) -> None:
        local_tx, local_ty, transform_warnings = translate_value(element.get("transform"))
        warnings.extend(transform_warnings)
        tx, ty = parent_tx + local_tx, parent_ty + local_ty
        terminal = terminal_from_element(element, tx, ty)
        if terminal:
            if terminal.name in terminals:
                errors.append(f"duplicate SVG terminal: {terminal.name}")
            terminals[terminal.name] = terminal
        net = element.get("data-net")
        if net and local_name(element.tag) in {"path", "polyline"}:
            if net in routes:
                errors.append(f"duplicate SVG route: {net}")
            if local_name(element.tag) == "path":
                route_segments, route_errors = parse_path(element.get("d", ""), tx, ty, net)
            else:
                coordinates = [float(value) for value in re.findall(NUMBER, element.get("points", ""))]
                points = [Point(coordinates[i] + tx, coordinates[i + 1] + ty) for i in range(0, len(coordinates) - 1, 2)]
                route_segments = [Segment(a, b, net) for a, b in zip(points, points[1:])]
                route_errors = []
            routes[net] = route_segments
            route_meta[net] = {key: element.get(key, "") for key in ("data-from", "data-to", "data-signal", "data-crossing")}
            errors.extend(route_errors)
        keepout = element.get("data-keepout")
        if keepout and local_name(element.tag) == "rect":
            x = float(element.get("x", 0)) + tx
            y = float(element.get("y", 0)) + ty
            keepouts.append((keepout, (x, y, x + float(element.get("width", 0)), y + float(element.get("height", 0)))))
        for child in element:
            visit(child, tx, ty)

    visit(root, 0.0, 0.0)
    return terminals, routes, route_meta, keepouts, errors, warnings


def get_pin(netlist: dict, endpoint: str) -> dict | None:
    if ":" not in endpoint:
        return None
    component, pin = endpoint.split(":", 1)
    return netlist.get("components", {}).get(component, {}).get("pins", {}).get(pin)


def validate_electrical(connection: dict, source: dict, destination: dict, errors: list[str], tolerance: float) -> None:
    identifier = connection.get("id", "<unnamed>")
    source_voltage, destination_voltage = source.get("voltage"), destination.get("voltage")
    if source_voltage is not None and destination_voltage is not None and abs(float(source_voltage) - float(destination_voltage)) > tolerance:
        errors.append(f"{identifier}: voltage mismatch {source_voltage} V vs {destination_voltage} V")
    source_direction, destination_direction = source.get("direction"), destination.get("direction")
    if source_direction == destination_direction == "out":
        errors.append(f"{identifier}: two outputs are connected")
    if source_direction == destination_direction == "power-out":
        errors.append(f"{identifier}: two power outputs are connected")
    protocol = str(connection.get("protocol", "")).lower()
    source_signal, destination_signal = str(source.get("signal", "")).upper(), str(destination.get("signal", "")).upper()
    if protocol == "uart":
        signals = {"TX" if "TX" in source_signal else "RX" if "RX" in source_signal else source_signal,
                   "TX" if "TX" in destination_signal else "RX" if "RX" in destination_signal else destination_signal}
        if signals != {"TX", "RX"}:
            errors.append(f"{identifier}: UART must connect TX to RX")
        if {source_direction, destination_direction} != {"in", "out"}:
            errors.append(f"{identifier}: UART directions must be one output and one input")
    if protocol == "ground" and not (source_direction == destination_direction == "ground"):
        errors.append(f"{identifier}: ground net must connect ground terminals")


def validate(svg_path: Path, netlist_path: Path, endpoint_tolerance: float, geometry_tolerance: float, voltage_tolerance: float) -> dict:
    netlist = json.loads(netlist_path.read_text(encoding="utf-8"))
    terminals, routes, route_meta, keepouts, errors, warnings = load_svg(svg_path)
    connection_ids: set[str] = set()
    connections = netlist.get("connections", [])
    for connection in connections:
        identifier = connection.get("id")
        if not identifier:
            errors.append("netlist connection without id")
            continue
        if identifier in connection_ids:
            errors.append(f"duplicate netlist connection id: {identifier}")
        connection_ids.add(identifier)
        source_name, destination_name = connection.get("from", ""), connection.get("to", "")
        source, destination = get_pin(netlist, source_name), get_pin(netlist, destination_name)
        if source is None:
            errors.append(f"{identifier}: unknown netlist endpoint {source_name}")
        if destination is None:
            errors.append(f"{identifier}: unknown netlist endpoint {destination_name}")
        if source is not None and destination is not None:
            validate_electrical(connection, source, destination, errors, voltage_tolerance)
        if identifier not in routes:
            errors.append(f"{identifier}: no SVG route")
            continue
        meta = route_meta[identifier]
        if meta["data-from"] != source_name or meta["data-to"] != destination_name:
            errors.append(f"{identifier}: SVG endpoint metadata does not match netlist")
        if source_name not in terminals or destination_name not in terminals:
            missing = [name for name in (source_name, destination_name) if name not in terminals]
            errors.append(f"{identifier}: missing SVG terminal(s): {', '.join(missing)}")
            continue
        if not routes[identifier]:
            errors.append(f"{identifier}: SVG route has no segments")
            continue
        first, last = routes[identifier][0].a, routes[identifier][-1].b
        direct = endpoint_distance(first, terminals[source_name]) <= endpoint_tolerance and endpoint_distance(last, terminals[destination_name]) <= endpoint_tolerance
        reverse = endpoint_distance(first, terminals[destination_name]) <= endpoint_tolerance and endpoint_distance(last, terminals[source_name]) <= endpoint_tolerance
        if not (direct or reverse):
            errors.append(f"{identifier}: route endpoints do not touch both terminal boundaries")
    for net in sorted(set(routes) - connection_ids):
        errors.append(f"{net}: SVG route is absent from netlist")

    route_items = list(routes.items())
    for route_index, (first_net, first_segments) in enumerate(route_items):
        for second_net, second_segments in route_items[route_index + 1 :]:
            for first_segment in first_segments:
                for second_segment in second_segments:
                    if segment_overlap(first_segment, second_segment, geometry_tolerance):
                        errors.append(f"routes {first_net} and {second_net} overlap")
                    crossing = strict_crossing(first_segment, second_segment, geometry_tolerance)
                    allowed = route_meta[first_net].get("data-crossing") == "allowed" or route_meta[second_net].get("data-crossing") == "allowed"
                    if crossing and not allowed:
                        errors.append(f"routes {first_net} and {second_net} cross at {crossing.x:g},{crossing.y:g}")
    for net, segments in routes.items():
        for keepout_name, box in keepouts:
            if any(segment_hits_box(segment, box, geometry_tolerance) for segment in segments):
                errors.append(f"route {net} enters keep-out {keepout_name}")

    errors = sorted(set(errors))
    warnings = sorted(set(warnings))
    return {
        "status": "passed" if not errors else "failed",
        "svg": str(svg_path),
        "netlist": str(netlist_path),
        "counts": {"terminals": len(terminals), "routes": len(routes), "connections": len(connections), "keepouts": len(keepouts)},
        "errors": errors,
        "warnings": warnings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--svg", required=True, type=Path)
    parser.add_argument("--netlist", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--endpoint-tolerance", type=float, default=1.5)
    parser.add_argument("--geometry-tolerance", type=float, default=0.1)
    parser.add_argument("--voltage-tolerance", type=float, default=0.15)
    args = parser.parse_args()
    report = validate(args.svg.resolve(), args.netlist.resolve(), args.endpoint_tolerance, args.geometry_tolerance, args.voltage_tolerance)
    output = json.dumps(report, indent=2, ensure_ascii=False)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + "\n", encoding="utf-8")
    print(output)
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    sys.exit(main())
