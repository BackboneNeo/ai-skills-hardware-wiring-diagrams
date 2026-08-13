# Source truth and orientation

## Source priority

Use sources in this order:

1. manufacturer schematic or connector specification;
2. manufacturer datasheet/manual for the exact hardware revision;
3. manufacturer product drawing with legible labels;
4. repository-owned verified pinout;
5. high-resolution board photograph;
6. reseller diagram or community image.

Record the URL or local path, hardware revision, page, view direction, and access date. Do not silently combine pinouts from different revisions.

## Orientation record

For each component record:

- view: top, bottom, connector face, or mating face;
- rotation in degrees clockwise;
- mirrored: yes or no;
- pin-1 marker location;
- connector key or latch direction;
- numbering direction and odd/even row placement.

Apply the same transform to the component photograph, pin symbols, contact callout, and connection anchors. A 180-degree board rotation changes visual order but never changes physical pin numbers.

## Connector-face trap

A plug wiring view and a receptacle mating-face view are often mirror images. Label the view explicitly. When the source does not say which face is shown, treat the orientation as unresolved.

## Source verification record

Store each verified source in the project netlist:

```json
{
  "component": "controller",
  "revision": "v1.0",
  "source": "https://manufacturer.example/pinout.pdf",
  "view": "top",
  "rotation": 180,
  "mirrored": false,
  "pin1_marker": "upper-right after rotation"
}
```
