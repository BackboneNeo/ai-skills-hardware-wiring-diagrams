# Visio drawing specification

Use JSON with page dimensions in inches and top-left coordinates.

```json
{
  "schema_version": 1,
  "page": {"name": "Wiring", "width_in": 16.54, "height_in": 11.69, "crossing_policy": "forbid"},
  "title": "Hardware wiring diagram",
  "terminals": [
    {
      "id": "controller:8",
      "x": 2.0,
      "y": 2.0,
      "width": 1.0,
      "height": 0.5,
      "text": "8 · TX",
      "fill": "#3276ca",
      "text_color": "#ffffff"
    }
  ],
  "labels": [
    {"id": "controller-title", "x": 1.0, "y": 0.8, "width": 2.4, "height": 0.4, "text": "Controller"}
  ],
  "images": [
    {"id": "controller-photo", "path": "images/controller.png", "x": 0.8, "y": 1.4, "width": 3.0, "height": 2.1}
  ],
  "keepouts": [
    {"id": "controller-title", "x": 1.0, "y": 0.8, "width": 2.4, "height": 0.4}
  ],
  "routes": [
    {
      "id": "uart-controller-to-imu",
      "from": "controller:8",
      "to": "imu:5",
      "color": "#3276ca",
      "waypoints": [[4.0, 2.25], [10.0, 2.25]],
      "arrow": false,
      "allow_label_overlap": false
    }
  ]
}
```

## Requirements

- Match every terminal `id` to `component:pin` in the electrical netlist.
- Match every route `id`, `from`, and `to` to one netlist connection.
- Use unique stable IDs.
- Keep all shapes inside the page.
- Put a terminal at the exact displayed physical ordering required by the component orientation.
- Use `labels` for editable component names, notes, warnings, and pinout captions.
- Use `images` only for individual component photographs. Keep terminals, labels, routes, and callouts native and editable. Resolve relative image paths from the specification directory.
- Use `keepouts` to reserve label, photo, and contact-number space.
- Use explicit `waypoints` for hardware wiring. This prevents Visio auto-routing from merging parallel routes or crossing a dense header.
- Put the first and last waypoints in the intended exit channel. The generator glues connector endpoints to the nearest terminal boundary.
- Keep `crossing_policy` as `forbid` by default. Use `gap` or `arc` only when a right-angle crossing is unavoidable. Collinear overlap remains invalid under every policy.
- Keep `allow_label_overlap` false or omit it. Set it to true only for a deliberately reviewed route whose unavoidable segment passes behind a non-critical component title/card; never use it to excuse an obscured terminal, pin number, warning, or contact label. Visually inspect every such exception after export.

Run `scripts/validate_visio_spec.py` before Visio COM automation. The validator checks the netlist mapping, page bounds, shape overlap, route overlap/crossing, keep-outs, and endpoint proximity.
