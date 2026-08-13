# SVG annotation contract

The validator recognizes semantic attributes on SVG elements.

## Terminals

Annotate the visible terminal shape, not only its surrounding group:

```xml
<rect id="pi-pin-8" data-terminal="pi:8" data-signal="UART0_TX" data-voltage="3.3" x="..." y="..." width="..." height="..."/>
```

Required:

- unique `data-terminal` in `component:physical-pin` form;
- `data-signal` using a stable logical name.

Optional:

- `data-voltage` in volts;
- `data-direction`: `in`, `out`, `bidirectional`, `power-in`, `power-out`, or `ground`.

## Routes

```xml
<path id="net-uart0-tx" data-net="uart0-tx" data-from="pi:8" data-to="imu:5" data-signal="UART_TX" d="..."/>
```

Each route must declare one source and one destination. Use separate route elements for branches.

## Keep-outs

Annotate text, images, and regions that routes must not cover:

```xml
<rect data-keepout="label:pi-pin-8" x="..." y="..." width="..." height="..." fill="none"/>
```

The simple validator supports axis-aligned `M/H/V/L/Z` paths and SVG transforms containing `translate(...)`. Flatten more complex transforms before validation.
