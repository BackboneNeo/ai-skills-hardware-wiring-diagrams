# Netlist schema

Use this minimal JSON structure:

```json
{
  "schema_version": 1,
  "components": {
    "controller": {
      "revision": "v1",
      "pins": {
        "8": {"signal": "UART_TX", "direction": "out", "voltage": 3.3},
        "10": {"signal": "UART_RX", "direction": "in", "voltage": 3.3},
        "6": {"signal": "GND", "direction": "ground"}
      }
    }
  },
  "connections": [
    {"id": "uart-tx", "from": "controller:8", "to": "imu:5", "protocol": "uart"}
  ]
}
```

Use string pin identifiers so connector names such as `J13-1` remain valid. The validator checks endpoint existence, duplicate connection IDs, voltage compatibility, direction conflicts, UART crossover, and route/netlist consistency.
