---
name: ai-skills-hardware-wiring-diagrams
description: Create, revise, and validate clear hardware wiring and assembly diagrams from component photographs, datasheets, pinouts, connector drawings, existing SVGs, and Microsoft Visio files. Use for GPIO headers, UART, I2C, SPI, CAN, RS-485, power distribution, batteries, regulators, sensors, cameras, flight controllers, callout pinouts, soldering instructions, A4/A3 layouts, native editable VSDX, Visio COM automation, SVG/PNG/PDF exports, or any diagram where electrical correctness, pin numbering, readable labels, non-overlapping routes, visible connection endpoints, and native editability must be proven.
---

# Hardware wiring diagram workflow

Treat datasheets and connector drawings as the electrical source of truth. Treat component photographs as placement evidence only unless their pad labels are legible and orientation is unambiguous.

## 1. Establish the connection contract

1. Inventory every component, connector, pin, signal, voltage domain, orientation, and requested output format.
2. Record the authoritative source and revision for each pinout. Do not infer a pin assignment from a product photo when a datasheet or schematic exists.
3. Normalize every connection in a machine-readable netlist before drawing. Use physical pin numbers and signal names together.
4. Mark unknown, optional, reserved, no-connect, and power-source pins explicitly. Stop before routing if a safety-critical pinout or voltage is unresolved.
5. Distinguish a mounting/wiring diagram from a principle schematic. Keep them synchronized through the same netlist even when only one is shown to the user.

Read [source-truth-and-orientation.md](references/source-truth-and-orientation.md) before interpreting rotated boards, mirrored views, underside photographs, or connector mating faces. Read [electrical-rules.md](references/electrical-rules.md) for signal and power checks.

## 2. Plan the sheet before routing

1. Select A4 or A3 and reserve zones for title, components, pinout callouts, notes, and legend.
2. Place the main controller near the visual center. Put peripherals near the controller side they connect to.
3. Rotate the component image and its callout together. Keep each callout close to the corresponding physical connector.
4. Use a compact pinout callout when a board header is too dense. Preserve the exact physical ordering after rotation or mirroring.
5. Move labels to a free side before routing. Never route through photographs, labels, pin numbers, or adjacent contact symbols.

Read [layout-and-callouts.md](references/layout-and-callouts.md) for the A3 composition, GPIO callout, and component-card patterns.

## 3. Route connections deterministically

1. Route orthogonally unless the project explicitly requires another style.
2. Connect from the boundary of a labeled terminal or pad to the boundary of its destination. Do not stop short, disappear under a card, or cross through the contact center.
3. Reserve one channel per wire. Never place two connection segments on the same geometric segment.
4. Avoid crossings. If a crossing is unavoidable, keep it at 90 degrees, use a visible separation convention, and never imply a junction.
5. Draw routes beneath terminal symbols, then redraw terminal fills, numbers, and labels above the routes. Preserve a visible endpoint at the contact edge.
6. Keep parallel routes separated by at least the configured channel gap, including their halos.
7. Apply the stable color mapping in [visual-language.md](references/visual-language.md); always pair color with a signal label.

Use `scripts/validate_wiring.py` after every material routing change. Treat any overlap, unintended intersection, dangling endpoint, obscured label, or invalid electrical connection as a failed candidate.

## 4. Build from reusable SVG primitives

1. Start from [wiring-a3-template.svg](assets/wiring-a3-template.svg) when no project-native template exists.
2. Keep component photos in `assets/` or the project asset directory and reference them by relative path.
3. Give routes, terminals, labels, components, and keep-out regions stable IDs and semantic `data-*` attributes. Follow [svg-annotation-contract.md](references/svg-annotation-contract.md).
4. Place routes in a dedicated layer below terminals and text. Use a halo only to separate routes from the background; do not use it to conceal another route.
5. Preserve editable SVG as the source. Render PNG/PDF only as derived review artifacts.

When the user requests Microsoft Visio, read [visio-workflow.md](references/visio-workflow.md), [visio-spec-schema.md](references/visio-spec-schema.md), and [visio-native-connectors.md](references/visio-native-connectors.md). Generate a native editable `.vsdx` with `scripts/New-HardwareWiringVisio.ps1`; never satisfy the request by placing the complete SVG or screenshot as one flat image. For electrical wiring, create exactly one built-in `Dynamic Connector` master per declared connection, glue both ends, and store every intentional bend as a Geometry row inside that connector. Do not substitute `DrawPolyline`, a raster/vector wire image, or a chain of connector segments when the user requires independently editable Visio connectors.

## 5. Validate in layers

1. Run structural SVG parsing and the wiring validator.
2. Verify every netlist endpoint exists exactly once and each route terminates at both declared endpoints.
3. Verify power direction, voltage compatibility, common ground, UART crossover, and bus-specific requirements.
4. Verify physical numbering against the actual displayed orientation, including pin 1 indicators and odd/even rows.
5. Render the complete sheet and close-up crops of every modified connector.
6. Inspect at intended print size. Pin numbers, signal names, wire identity, endpoint contact, and warnings must remain legible.
7. Re-render after every SVG edit; never report success from source inspection alone.

Use `scripts/render_svg.py`. In Codex Desktop, load workspace dependencies when available; the renderer also auto-detects the bundled Node.js and Sharp runtime for PNG output.

For Visio output, run `scripts/Test-VisioEnvironment.ps1` first. Use `scripts/Find-VisioMasters.ps1` when a stencil or built-in master is preferable. Then generate, export a PNG/PDF preview, and inspect native shapes and glued connectors with `scripts/Inspect-HardwareWiringVisio.ps1`. Keep the netlist as the shared source of electrical truth for both SVG and VSDX outputs.

Read [validation-gates.md](references/validation-gates.md) before declaring completion. Read [failure-patterns.md](references/failure-patterns.md) when repairing an existing diagram.

## 6. Deliver truthfully

- Deliver the editable SVG or native editable VSDX, plus a rendered PNG and PDF when requested.
- State the exact pin-to-pin mapping for newly added or changed connections.
- State which pinouts were source-verified and which assumptions remain.
- Report `completed` only when structural, electrical, routing, and visual gates pass.
- Report `blocked` when an authoritative pinout, voltage rating, connector orientation, or mating-face interpretation cannot be established.
- Never claim that a visually plausible route proves electrical correctness.
- Never claim native Visio editability if the page is only a full-sheet imported image.
