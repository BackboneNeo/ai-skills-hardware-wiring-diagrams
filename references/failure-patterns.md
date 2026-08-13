# Failure patterns

## Wire disappears before the contact

Cause: the route is beneath a large component/card fill or ends before the terminal boundary. Route through a free corridor and finish exactly at the terminal edge. Keep only the terminal symbol above the endpoint.

## Wire covers the pin number

Cause: the route enters through the contact center. Attach to a free side or to the adjacent functional label block. Draw the terminal fill and number after the route.

## Two wires look like one

Cause: coincident or nearly coincident segments. Allocate independent channels with a fixed gap; do not rely on color to separate overlapping geometry.

## Correct number in the wrong orientation

Cause: the image was rotated but the callout was not transformed consistently. Rebuild the displayed order from the physical numbering and view direction; preserve pin identity.

## TX connected to TX

Cause: matching labels instead of signal directions. Normalize endpoints as roles and connect TX to RX.

## Contact callout drifts away from the real connector

Cause: the board was moved independently from the callout. Group the board, callout leader, and connector anchor or recompute their transforms together.

## Raster assets disappear after rendering

Cause: the renderer received SVG text/bytes and could not resolve relative image paths. Render from the SVG file path or resolve image references to absolute paths before rendering.
