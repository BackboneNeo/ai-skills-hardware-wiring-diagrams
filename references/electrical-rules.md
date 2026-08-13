# Electrical rules

## Universal checks

- Connect every signal within a compatible voltage domain.
- Establish a common signal ground unless the interface is intentionally isolated or differential.
- Never join independent power outputs without explicit load-sharing support.
- Verify regulator input range, output voltage, continuous current, peak current, polarity, and thermal margin.
- Mark high-voltage wiring separately from logic wiring.
- Do not infer that a pin named `5V` is an input; verify direction.

## UART

- Connect controller TX to peripheral RX.
- Connect controller RX to peripheral TX.
- Connect ground.
- Verify logic level, baud rate, inversion, flow control, and whether a Linux console or bootloader occupies the port.
- Never join two TX outputs or two RX inputs and call it a complete UART link.

## I2C

- Connect SDA to SDA, SCL to SCL, and ground.
- Verify the bus voltage and pull-up ownership.
- Check address conflicts and cable length.

## SPI

- Connect SCLK and ground; connect controller MOSI to peripheral SDI and peripheral SDO to controller MISO.
- Give each peripheral an independent chip select unless the devices support daisy chaining.
- Verify mode and voltage.

## CAN and RS-485

- Preserve polarity: CAN_H/CAN_L or A/B according to the exact vendor convention.
- Show termination and biasing where relevant.
- Do not replace a differential pair with a single-ended UART connection.

## Power notation

Use `VBAT`, `VIN`, `VOUT`, `5V`, `3V3`, and `GND` consistently. Add nominal voltage and current near converters. Include a pre-power checklist when the source exceeds the controller's safe input voltage.
