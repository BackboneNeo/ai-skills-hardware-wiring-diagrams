# Validation gates

| Gate | Minimum evidence |
| --- | --- |
| Source truth | exact component revisions and authoritative pinout sources recorded |
| Orientation | view, rotation, mirror state, and pin-1 marker verified |
| Netlist | every drawn route maps to a declared source and destination |
| Electrical | voltage, direction, ground, and protocol rules pass |
| Endpoints | every route visibly terminates at both intended contact boundaries |
| Routing | no coincident segments; no unintended intersections; required separation preserved |
| Visibility | routes do not cover contact numbers, signal labels, or warnings |
| Layout | component and callout correspondence is unambiguous |
| Rendering | SVG renders without missing relative assets |
| Print review | full sheet and connector close-ups remain legible at output size |
| Visio connector structure | one built-in `Dynamic Connector` shape per connection; both ends glued; no polylines, imported wire graphics, or segment chains |
| Visio component images | every critical photograph is an explicit component-image shape and is visibly present in the exported preview |

Run `scripts/validate_wiring.py --svg <diagram.svg> --netlist <netlist.json> --report <report.json>`. A clean report is necessary but not sufficient; finish with rendered visual review.
