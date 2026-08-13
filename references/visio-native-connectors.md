# Native Visio connectors

Use this reference when every electrical connection must be independently selectable and configurable in Microsoft Visio.

## Required object model

- Create one shape per complete electrical connection with `Page.Drop(Application.ConnectorToolDataObject, 0, 0)`.
- Require `Master.NameU = "Dynamic connector"`, `OneD = -1`, and `ObjType = 2` after saving and reopening.
- Glue `BeginX` and `EndX` directly to terminal shapes with `GlueToPos`; require two resulting `Connects` relationships.
- Store `ConnectionId`, `NetId`, `From`, and `To` as Shape Data and use a stable `NameU` such as `wire__uart_tx`.
- Put all wires on a dedicated layer, one connector shape per net.

Do not represent a complete connection with `DrawPolyline`, SVG/PNG artwork, or multiple joined line/connector shapes. Multiple MoveTo/LineTo rows inside one connector's Geometry section are editable vertices of that single object and are valid.

## Stable explicit routing

1. Glue both ends before editing the path.
2. Set `ConFixedCode = 2` and temporarily set `ObjType = 0` so the route engine does not replace Geometry rows.
3. Delete old rows after the Geometry section header.
4. Convert declared page coordinates into the connector's local coordinates with `Shape.XYFromPage`.
5. Add one MoveTo row for the first point and LineTo rows for every following waypoint and endpoint.
6. Restore `ObjType = 2`, keep `ConFixedCode = 2`, and set `Page.LayoutRoutePassive = true`.

This preserves intentional orthogonal corridors while keeping the route a real Dynamic Connector.

## Component images

- Declare each critical board photograph in the specification `images` array even when an imported SVG already references it.
- Resolve its path relative to the drawing specification and import it as its own Visio image shape.
- Assign `DiagramId`, `Role = component-image`, and `SourcePath` Shape Data.
- Do not assume an SVG `<image>` survives Visio import and ungrouping; verify the photograph in the exported PNG/PDF.
- Keep connector terminals, names, pin numbers, and wires as native shapes above or around the photograph.

## Reopen audit

After generating and exporting, close the document and inspect the saved `.vsdx` in a fresh Visio instance. Require:

- connector count equals declared connection count;
- every connection ID occurs exactly once;
- every wire uses the `Dynamic connector` master;
- every wire is visible and glued at both ends;
- `ObjType = 2`, `GlueType = 2`, and `ConFixedCode = 2`;
- Geometry has at least a MoveTo and LineTo row;
- expected component-image IDs are present;
- no page-sized raster substitutes for the complete diagram;
- full-sheet PNG/PDF preview visibly contains every critical component.

Structural inspection does not replace visual review. A connector can be native and glued while still hiding a contact label or using a poor route.
