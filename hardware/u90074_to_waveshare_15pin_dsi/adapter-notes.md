# Adapter Notes

## Connector Assumptions

`J1` is the CM3 IO Board side. It is currently represented as a 39-pin FPC placeholder matching the `U90074` logical pinout from the Radxa CM3 IO Board schematic/netlist.

`J2` is the Waveshare side. It is currently represented as a 15-pin 1.0 mm FPC placeholder matching the Raspberry Pi DSI 15-pin pinout published in the local Waveshare wiki copy.

The footprints in the KiCad PCB are placeholders. Before fabrication, replace them with verified footprints from the exact connectors and confirm the cable insertion direction.

## Electrical Mapping

The adapter intentionally uses only the Waveshare panel's 2-lane DSI subset:

- `D0N/D0P`
- `D1N/D1P`
- `CLKN/CLKP`
- `I2C_SCL/I2C_SDA`
- `3V3`
- `GND`

The CM3 IO Board's `D2/D3`, `TP_RST_LCD`, `TP_INT_LCD`, `VCC_TP`, `VCC_LEDA2`, and `VCC_LEDK2` pins are left unconnected in this revision.

## PCB Constraints

- Keep DSI differential pairs short and visually matched.
- Route each pair together with constant spacing.
- Avoid stubs, vias, and layer changes on DSI pairs in the first prototype if the mechanical layout allows it.
- Keep a continuous ground reference under all DSI pairs.
- Place ground stitching vias near connector ground pins and beside the DSI escape area.
- Keep I2C away from the DSI pair escape if possible.
- Put at least one local decoupling capacitor near the Waveshare 3.3 V pins in the production layout.

## Bring-up Checklist

1. With no panel connected, check `VCC_3V3_LCD` to GND for shorts.
2. Power the CM3 IO Board and verify `VCC_3V3_LCD` is around 3.3 V.
3. Connect the panel and check whether I2C sees the touch controller. The Waveshare wiki references a Goodix touch device, commonly at `0x14`.
4. Add the RK3566 device-tree panel/touch nodes after electrical continuity is confirmed.
5. Rotate the display in software to use the 480x800 portrait panel as an 800x480 landscape GBA screen.

