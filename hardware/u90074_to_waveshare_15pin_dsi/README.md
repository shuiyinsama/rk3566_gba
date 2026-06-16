# U90074 to Waveshare 15-pin DSI Adapter

本目录是 RK3566 GBA 掌机项目的第一版 DSI 屏转接小板草案，用于把 Radxa CM3 IO Board 的 `U90074` 39-pin MIPI LCD 接口转到 Waveshare 4inch DSI LCD 的 Raspberry Pi 15-pin DSI 接口。

## 当前状态

- 状态：电气映射和布局草案，暂不建议直接投板。
- 输入接口：Radxa CM3 IO Board `U90074`，按原理图/netlist 中的 39-pin LCD 接口整理。
- 输出接口：Waveshare 4inch DSI LCD 的 15-pin Raspberry Pi DSI 接口。
- 屏幕只使用 2-lane DSI：`D0`、`D1`、`CLK`、`I2C`、`3V3`、`GND`。
- `U90074` 的 `D2/D3`、背光 LED、触摸复位/中断等信号本版不接出。

## 文件说明

- `pin-map.csv`：转接关系表，优先审查这个文件。
- `adapter-notes.md`：电气和 PCB 约束说明。
- `u90074-to-waveshare-15pin-dsi.kicad_pcb`：KiCad PCB 草案，含板框、占位 FPC 焊盘、网络名和测试点。
- `u90074-to-waveshare-15pin-dsi.kicad_pro`：KiCad 工程占位文件。
- `board-outline.svg`：布局和走线意图示意图。

## 需要二次确认

1. `U90074` 连接器的精确型号、pitch、接触面方向、翻盖方向和 pin 1 位置。
2. Waveshare 15-pin DSI FPC 的精确 pitch、接触面方向和 pin 1 位置。
3. `U90074` 是否存在额外 shield/mechanical GND pin。netlist 里出现过 40/41 接地信息，但原理图接口按 39-pin 使用。
4. `VCC_LCD_MIPI_2` 已在 CM3 IO Board 图纸中标注为 3.3V；投板前仍建议实测空载/带载电压。
5. Waveshare 屏触摸 I2C 默认使用 Pi 的 `I2C-0`，本适配板将其接到 CM3 IO Board 的 `I2C2_SCL_LCD/I2C2_SDA_LCD`，后续设备树需要匹配。

## 建议首版板子

- 2 层板即可做验证版，但 DSI 差分对需要尽量短、等长、连续参考地。
- 板宽按 40 mm 草案放置，后续按核心板、屏幕排线和外壳空间收缩。
- 保留 `3V3/GND/SCL/SDA` 测试点，方便点亮阶段排查。
- 不在本板做电平转换；如果后续确认触摸 I2C 电平不是 3.3V，再加器件。

