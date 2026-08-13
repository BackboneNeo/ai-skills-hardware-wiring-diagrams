# Upstream Visio sources

The Visio extension was informed by the following public projects. Keep this list for provenance and future comparison.

## MIT-licensed sources

- [`renzo1031/visio-automation-skill`](https://github.com/renzo1031/visio-automation-skill) — native stencils/masters, Dynamic Connectors, endpoint glue, ShapeSheet verification, and master discovery.
- [`ywq177995212697-droid/visio-scientific-figures`](https://github.com/ywq177995212697-droid/visio-scientific-figures) — structured specs, COM environment checking, multi-format export, and automated quality review.
- [`zxc-heu/visio-template-drawing-skill`](https://github.com/zxc-heu/visio-template-drawing-skill) — drawing-plan preflight, reserved routing corridors, native editable shapes, and connector-to-boundary guidance.
- [`pengjunchi0/codex-visio-paper-figure-skill`](https://github.com/pengjunchi0/codex-visio-paper-figure-skill) — screenshot reconstruction, calibrated panel coordinates, backups, package inspection, and format export discipline.

## Reviewed but not copied

- [`deermiya/visio-skill`](https://github.com/deermiya/visio-skill) — useful COM and JSON-spec workflow, but no detected license at review time.
- [`uigiuf/codex-visio-replica-workflow`](https://github.com/uigiuf/codex-visio-replica-workflow) — native image reconstruction ideas, but no detected license at review time.
- [`0Antique/Auto-Visio-Helper`](https://github.com/0Antique/Auto-Visio-Helper) — Visio helper workflow, but no detected license at review time.

Our implementation is purpose-built for hardware wiring diagrams and uses the existing electrical netlist, terminal visibility, non-overlap, and route validation contracts from this repository.

## Microsoft Visio API references

- [`Application.ConnectorToolDataObject`](https://learn.microsoft.com/en-us/office/vba/api/visio.application.connectortooldataobject)
- [`Cell.GlueToPos`](https://learn.microsoft.com/en-us/office/vba/api/visio.cell.gluetopos)
- [`Shape.AddNamedRow`](https://learn.microsoft.com/en-us/office/vba/api/visio.shape.addnamedrow)
- [`Document.ExportAsFixedFormat`](https://learn.microsoft.com/en-us/office/vba/api/visio.document.exportasfixedformat)
- [`Documents.OpenEx`](https://learn.microsoft.com/en-us/office/vba/api/visio.documents.openex)
- [`LineJumpStyle`](https://learn.microsoft.com/en-us/office/client-developer/visio/linejumpstyle-cell-page-layout-section) and [`LineJumpCode`](https://learn.microsoft.com/en-us/office/client-developer/visio/linejumpcode-cell-page-layout-section)
