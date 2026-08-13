# Microsoft Visio workflow

Use this workflow on Windows when Microsoft Visio is installed and the user requests a real editable `.vsdx`.

## Core rules

- Treat the JSON netlist as the electrical source of truth.
- Treat a Visio drawing specification as the layout source of truth.
- Create each component, functional pin label, physical pin number, note, and legend entry as a native Visio shape.
- Create each complete wire as exactly one built-in `Dynamic Connector` master and glue both ends to terminal shapes.
- Store explicit bends as MoveTo/LineTo rows in that connector's Geometry section. These rows are vertices of one connector object, not separate line shapes.
- Do not use `DrawPolyline`, imported SVG/PNG wire graphics, or multiple joined connector shapes for a connection that must remain independently configurable.
- Use orthogonal routing by default. Keep explicit waypoints when the diagram requires stable separate channels.
- Keep functional labels and physical pin numbers editable. Do not rasterize dense GPIO callouts.
- Never use a full-page SVG, PNG, or screenshot as the final Visio diagram.

These rules incorporate useful patterns from the MIT-licensed Visio automation skills listed in [upstream-visio-sources.md](upstream-visio-sources.md).

## Workflow

1. Run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/Test-VisioEnvironment.ps1
   ```

2. Build or update the electrical netlist and validate its source pinouts.
   If a native Visio master is useful, discover its locale-independent `NameU` first:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/Find-VisioMasters.ps1 `
     -BuiltIn Callouts -Pattern '*callout*'
   ```

   For a local `.vss`, `.vssx`, or `.vssm`, use `-StencilPath` instead of `-BuiltIn`.
3. Create a Visio drawing specification following [visio-spec-schema.md](visio-spec-schema.md).
4. Validate the specification before launching Visio:

   ```text
   python scripts/validate_visio_spec.py diagram.visio.json --netlist wiring-netlist.json
   ```

5. Generate the document:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/New-HardwareWiringVisio.ps1 `
     -SpecPath diagram.visio.json -NetlistPath wiring-netlist.json -OutputPath diagram.vsdx `
     -PreviewPng diagram.png -PreviewPdf diagram.pdf
   ```

6. Inspect native editability and connector glue:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/Inspect-HardwareWiringVisio.ps1 `
     -VsdxPath diagram.vsdx -SpecPath diagram.visio.json -ReportPath diagram.visio-report.json
   ```

7. Open the PNG/PDF preview and visually review the full sheet and connector close-ups.

## Visio COM conventions

- Use inches for page coordinates.
- Store spec coordinates from the top-left; convert to Visio's bottom-left coordinate system.
- Store stable IDs in `Prop.DiagramId` and terminal identities in `Prop.TerminalId`.
- Use `NameU` and ShapeSheet cells rather than localized UI names where possible.
- Search the installed stencil rather than assuming that localized stencil/master names exist.
- Use `Page.Drop(Application.ConnectorToolDataObject, ...)` for native connectors when available.
- Glue `BeginX` and `EndX` to connection points or position cells. Verify glue formulas after saving and reopening.
- For stable manual routing, temporarily suspend routing ownership, replace the connector's Geometry rows with the declared waypoints, restore `ObjType=2`, and set `ConFixedCode=2`. Leave `LayoutRoutePassive` enabled so page layout does not overwrite those bends.
- Keep Visio hidden for automated validation and visible only when the user asks to watch or manually refine the page.
- Create a backup before editing an existing `.vsdx`.

## Output verification

Require:

- a non-empty `.vsdx` that reopens;
- expected native 2-D shape and 1-D connector counts;
- exactly one shape with master `Dynamic connector` for every declared connection ID;
- every connector with glued begin and end formulas;
- no single page-sized raster image acting as the complete diagram;
- a non-blank exported preview;
- the same connection IDs in netlist, drawing spec, and Visio shape data.
