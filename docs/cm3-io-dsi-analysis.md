# Radxa CM3 IO Board DSI 接口分析

## 1. 资料来源

- `docs/radxa-cm3-io-board-v1360/radxa_cm3_io_board_v1360_schematic.pdf`
- `docs/radxa-cm3-io-board-v1360/radxa_cm3_io_board_v1360.asc`
- `docs/radxa_cm3_v1.3_pinout.xlsx`

本分析基于 Radxa CM3 IO Board V1.36 原理图/netlist 与 Radxa CM3 V1.3 pinout 表。

## 2. 关键结论

Radxa CM3 IO Board V1.36 确实引出了 MIPI DSI 显示接口，不是只有 HDMI/eDP。

板上主要有两组 MIPI LCD 相关接口：

- `LCD1`：31pin FPC，连接 `MIPI_DSI_TX0`，4-lane DSI。
- `U90074`：39pin LCD 接口，连接 `MIPI_DSI_TX1`，4-lane DSI，并带触摸 I2C、触摸复位/中断、背光相关引脚。

对当前项目而言，`LCD1` 和 `U90074` 都不是树莓派标准 15pin DSI 连接器形态。已补充的 Waveshare `4inch DSI LCD` 资料显示该屏为 15pin、2-lane DSI、480 x 800 竖屏，因此大概率不能直接插到 CM3 IO Board，但可通过 `U90074 -> 15pin DSI` 转接板适配。

## 3. LCD1：MIPI_DSI_TX0 31pin FPC

`LCD1` 封装为 `FH35C_31P_0_6SHW_LCD`，从 netlist 看是 31pin LCD FPC。

| LCD1 Pin | Signal |
| --- | --- |
| 1 | VCC_LEDA1 |
| 2 | VCC_LEDA1 |
| 3 | VCC_LEDA1 |
| 4 | NC / 未连接 |
| 5 | VCC_LEDK1 |
| 6 | VCC_LEDK1 |
| 7 | VCC_LEDK1 |
| 8 | VCC_LEDK1 |
| 9 | GND |
| 10 | GND |
| 11 | MIPI_DSI_TX0_D2P / LVDS_TX0_D2P |
| 12 | MIPI_DSI_TX0_D2N / LVDS_TX0_D2N |
| 13 | GND |
| 14 | MIPI_DSI_TX0_D1P / LVDS_TX0_D1P |
| 15 | MIPI_DSI_TX0_D1N / LVDS_TX0_D1N |
| 16 | GND |
| 17 | MIPI_DSI_TX0_CLKP / LVDS_TX0_CLKP |
| 18 | MIPI_DSI_TX0_CLKN / LVDS_TX0_CLKN |
| 19 | GND |
| 20 | MIPI_DSI_TX0_D0P / LVDS_TX0_D0P |
| 21 | MIPI_DSI_TX0_D0N / LVDS_TX0_D0N |
| 22 | GND |
| 23 | MIPI_DSI_TX0_D3P / LVDS_TX0_D3P |
| 24 | MIPI_DSI_TX0_D3N / LVDS_TX0_D3N |
| 25 | GND |
| 26 | NC / 未连接 |
| 27 | N17923941 |
| 28 | GND |
| 29 | VCC_1V8_1 |
| 30 | VCC_LCD_MIPI |
| 31 | VCC_LCD_MIPI |

观察：

- `LCD1` 具备完整 4-lane DSI TX0。
- 触摸 I2C、TP_INT、TP_RST 没有直接出现在 `LCD1` 31pin 上。
- `LCD1` 有 LEDA/LEDK 背光电源脚，说明更像裸屏/模组 FPC，而不是树莓派生态的 15pin DSI 屏接口。

## 4. U90074：MIPI_DSI_TX1 39pin LCD 接口

`U90074` 是另一组 LCD 接口，netlist 中显示其承载 `MIPI_DSI_TX1`。

| U90074 Pin | Signal |
| --- | --- |
| 1 | VCC_LCD_MIPI_2 |
| 2 | N18131469 |
| 3 | NC / 未连接 |
| 4 | N17929077 |
| 5 | NC / 未连接 |
| 6 | GND |
| 7 | MIPI_DSI_TX1_D0N |
| 8 | MIPI_DSI_TX1_D0P |
| 9 | GND |
| 10 | MIPI_DSI_TX1_D1N |
| 11 | MIPI_DSI_TX1_D1P |
| 12 | GND |
| 13 | MIPI_DSI_TX1_CLKN |
| 14 | MIPI_DSI_TX1_CLKP |
| 15 | GND |
| 16 | MIPI_DSI_TX1_D2N |
| 17 | MIPI_DSI_TX1_D2P |
| 18 | GND |
| 19 | MIPI_DSI_TX1_D3N |
| 20 | MIPI_DSI_TX1_D3P |
| 21 | GND |
| 22 | GND |
| 23 | TP_RST_LCD |
| 24 | VCC_TP |
| 25 | TP_INT_LCD |
| 26 | I2C2_SDA_LCD |
| 27 | I2C2_SCL_LCD |
| 28 | GND |
| 29 | GND |
| 30 | VCC_LCD_MIPI_2 |
| 31 | VCC_LCD_MIPI_2 |
| 32 | GND |
| 33 | GND |
| 34 | VCC_LEDK2 |
| 35 | VCC_LEDK2 |
| 36 | NC / 未连接 |
| 37 | NC / 未连接 |
| 38 | VCC_LEDA2 |
| 39 | VCC_LEDA2 |

观察：

- `U90074` 具备完整 4-lane DSI TX1。
- `U90074` 同时引出触摸相关信号：`I2C2_SCL_LCD`、`I2C2_SDA_LCD`、`TP_INT_LCD`、`TP_RST_LCD`、`VCC_TP`。
- 这一路更像适合一体式 LCD + CTP 模组，但连接器不是 Raspberry Pi 15pin DSI 标准形态。

## 5. J24：CM3 高速连接器侧相关信号

`J24` 为 CM3 侧高速连接器，相关信号如下：

| J24 Pin | Signal |
| --- | --- |
| 3 | MIPI_DSI_TX0_D2N / LVDS_TX0_D2N |
| 4 | LCD1_PWREN_H |
| 5 | MIPI_DSI_TX0_D2P / LVDS_TX0_D2P |
| 6 | TP_RST_L |
| 8 | TP_INT_L |
| 9 | MIPI_DSI_TX0_D3N / LVDS_TX0_D3N |
| 11 | MIPI_DSI_TX0_D3P / LVDS_TX0_D3P |
| 18 | MIPI_LCD_EN_1 |
| 20 | MIPI_LCD_EN_2 |
| 24 | TP_PWR_DET |
| 36 | MIPI_LCD_BL_1 |
| 44 | I2C3_SCL_TP |
| 46 | I2C3_SDA_TP |
| 75 | LCD0_BL_EN |
| 77 | MIPI_BL_EN_2 |
| 79 | MIPI_RESET_2 |
| 81 | TP_DET_1 |
| 83 | MIPI_RESET_1 |
| 85 | MIPI_BL_EN_1 |
| 87 | TP_INT_1 |
| 89 | TP_RST_1 |
| 93 | MIPI_LCD_BL_2 |
| 95 | LCD0_BL_PWM5 |

结合 CM3 pinout，TX0 的 D0/D1/CLK 从 200pin 侧出来，TX0 的 D2/D3 从 `J24` 侧出来；TX1 主要从 200pin 侧出来。

## 6. 对微雪树莓派 DSI 屏的影响

当前微雪屏如果是 Raspberry Pi 生态 DSI 屏，需要重点确认以下点：

1. 屏幕接口是 15pin 还是 22pin DSI FPC。
2. 屏幕使用 2-lane 还是 4-lane DSI。
3. DSI lane 顺序与 P/N 极性。
4. 屏幕板上是否自带供电、背光驱动和触摸控制器。
5. 触摸是走 I2C、USB，还是通过屏幕转接板特殊处理。
6. Linux 设备树是否已有对应 panel/bridge/touch 配置可移植。

工程判断：

- 可以继续使用 CM3 IO Board 作为 DSI 验证平台。
- 不建议假设微雪树莓派 DSI 屏能直连。
- 若目标是最少硬件改动，优先找与 `LCD1` 31pin 或 `U90074` 39pin pinout 匹配的 LCD 模组。
- 若坚持使用微雪树莓派 DSI 屏，建议画一块 `U90074 39pin -> 15pin DSI` 转接板，并在转接板上处理 lane 映射、触摸 I2C 和 3.3V 供电。

## 7. 下一步建议

1. 确认微雪屏的准确型号，并获取其 DSI FPC pinout。
2. 对比微雪屏 pinout 与 `LCD1`/`U90074` pinout。
3. 优先选择 `U90074` 作为一体屏验证接口，因为它已经包含触摸 I2C 和 TP 控制信号。
4. 若微雪屏是树莓派 15pin DSI，设计 `U90074 39pin -> Raspberry Pi DSI 15pin` 转接板前，先确认屏幕供电和背光是否能由屏幕转接板自行处理。
5. 在系统侧准备设备树 overlay：DSI host、panel、backlight、touch controller、reset/enable GPIO。

详见：[Waveshare 4inch DSI LCD 适配分析](waveshare-4inch-dsi-lcd-analysis.md)。
