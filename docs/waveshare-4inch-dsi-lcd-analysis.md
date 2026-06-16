# Waveshare 4inch DSI LCD 适配分析

## 1. 资料来源

- `docs/4inch DSI LCD/4inch DSI LCD - Waveshare Wiki.html`
- `docs/4inch DSI LCD/4inch-dsi-lcd_SKU21687.stp`
- `docs/cm3-io-dsi-analysis.md`

屏幕资料对应 Waveshare `4inch DSI LCD`，本地机械文件名为 `4inch-dsi-lcd_SKU21687`。

## 2. 屏幕关键信息

- 尺寸：4 英寸。
- 显示接口：MIPI DSI。
- 触摸：电容式五点触摸。
- 面板：IPS。
- 硬件分辨率：480 x 800。
- 刷新率：官方资料标注 Raspberry Pi DSI 驱动下可达 60Hz。
- 树莓派支持：Pi5/CM5/4B/CM4/3B+/3A+/3B/CM3+/CM3。
- 背光：支持软件调节。
- 默认连接：通信和供电都通过 DSI 排线完成，不需要额外接顶针。

注意：该屏硬件分辨率是 `480 x 800` 竖屏，不是原先选型文档中泛称的 `800 x 480` 横屏。用于掌机横屏时，需要在显示栈中旋转为横向显示。

## 3. 屏幕 15pin DSI 接口定义

| Pin | Signal |
| --- | --- |
| 1 | GND |
| 2 | DSI1_DN1 |
| 3 | DSI1_DP1 |
| 4 | GND |
| 5 | DSI1_CN |
| 6 | DSI1_CP |
| 7 | GND |
| 8 | DSI1_DN0 |
| 9 | DSI1_DP0 |
| 10 | GND |
| 11 | SCL0 |
| 12 | SDA0 |
| 13 | GND |
| 14 | 3V3 |
| 15 | 3V3 |

从接口定义看，该屏只使用 DSI `D0`、`D1` 和 `CLK`，因此是 2-lane DSI 屏。`D2/D3` 不需要连接。

## 4. 与 CM3 IO Board 的接口匹配

CM3 IO Board V1.36 上有两组 MIPI LCD 接口：

- `LCD1`：31pin，`MIPI_DSI_TX0`，4-lane，但不直接带屏幕 15pin 所需的 I2C 触摸信号。
- `U90074`：39pin，`MIPI_DSI_TX1`，4-lane，并带 `I2C2_SCL_LCD`、`I2C2_SDA_LCD`、`TP_INT_LCD`、`TP_RST_LCD`、3.3V LCD 电源。

对这块 Waveshare 4inch DSI LCD，优先推荐从 `U90074` 转接，而不是从 `LCD1` 转接。原因：

- `U90074` 的 DSI TX1 lane 排列完整，直接包含 D0/D1/CLK。
- `U90074` 已经引出触摸 I2C：`I2C2_SCL_LCD` / `I2C2_SDA_LCD`。
- `U90074` 已经有 LCD 侧 3.3V 电源网络 `VCC_LCD_MIPI_2`。
- 屏幕 15pin 不需要 LEDA/LEDK 裸背光输入，`LCD1` 的 LEDA/LEDK 对它帮助不大。

## 5. 推荐转接映射：U90074 -> Waveshare 15pin

| Waveshare 15pin | Waveshare Signal | CM3 IO U90074 Pin | CM3 IO Signal |
| --- | --- | --- | --- |
| 1 | GND | 6/9/12/15/18/21/22/28/29/32/33 | GND |
| 2 | DSI1_DN1 | 10 | MIPI_DSI_TX1_D1N |
| 3 | DSI1_DP1 | 11 | MIPI_DSI_TX1_D1P |
| 4 | GND | 6/9/12/15/18/21/22/28/29/32/33 | GND |
| 5 | DSI1_CN | 13 | MIPI_DSI_TX1_CLKN |
| 6 | DSI1_CP | 14 | MIPI_DSI_TX1_CLKP |
| 7 | GND | 6/9/12/15/18/21/22/28/29/32/33 | GND |
| 8 | DSI1_DN0 | 7 | MIPI_DSI_TX1_D0N |
| 9 | DSI1_DP0 | 8 | MIPI_DSI_TX1_D0P |
| 10 | GND | 6/9/12/15/18/21/22/28/29/32/33 | GND |
| 11 | SCL0 | 27 | I2C2_SCL_LCD |
| 12 | SDA0 | 26 | I2C2_SDA_LCD |
| 13 | GND | 6/9/12/15/18/21/22/28/29/32/33 | GND |
| 14 | 3V3 | 30/31 | VCC_LCD_MIPI_2 |
| 15 | 3V3 | 30/31 | VCC_LCD_MIPI_2 |

`U90074` 的 D2/D3、TP_RST_LCD、TP_INT_LCD、VCC_TP、LEDA/LEDK 不需要接到该 15pin 屏幕接口。不要在转接板上随意把 `VCC_TP` 和 `VCC_LCD_MIPI_2` 短接，除非后续从原理图确认两路电源就是同一受控 3.3V rail。

## 6. 结论：硬件上是否对得上

硬件信号层面基本对得上，但需要转接板。

可以确认的匹配点：

- DSI lane 数匹配：屏幕需要 2-lane，`U90074` 可提供 4-lane，其中 D0/D1/CLK 可用。
- 触摸 I2C 有对应信号：屏幕 `SCL0/SDA0` 可接 `I2C2_SCL_LCD/I2C2_SDA_LCD`。
- 供电方向匹配：屏幕需要 `3V3`，`U90074` 有 `VCC_LCD_MIPI_2`，原理图页标注为 3.3V。
- 背光无需单独接 LEDA/LEDK：官方 FAQ 说明默认通信和供电都通过 DSI 排线完成。

仍需确认的点：

- 转接板连接器规格：屏幕侧 15pin FPC 间距和接触方向，`U90074` 侧 39pin 接口规格。
- DSI P/N 极性和 lane 顺序，转接板必须严格按屏幕定义走线。
- `VCC_LCD_MIPI_2` 的供电能力是否满足屏幕和背光峰值电流。
- 屏幕 I2C 触摸地址和驱动匹配情况。

## 7. 软件适配影响

树莓派 Bookworm/Trixie 推荐 overlay：

```text
dtoverlay=vc4-kms-v3d
dtoverlay=vc4-kms-dsi-waveshare-panel,4_0_inch
```

Bullseye/Buster 旧驱动示例：

```text
dtoverlay=WS_xinchDSI_Screen,SCREEN_type=1,I2C_bus=10
dtoverlay=WS_xinchDSI_Touch,invertedx,swappedxy,I2C_bus=10
```

这些 overlay 是 Raspberry Pi VC4/KMS 生态，不会直接用于 RK3566。对 RK3566 需要做的工作是：

- 找到或移植 `4_0_inch` Waveshare DSI panel 的初始化序列和 timing。
- 在 RK3566 设备树中启用对应 DSI host，建议优先试 `MIPI_DSI_TX1`。
- 配置 2-lane DSI、480x800 timing、panel reset/enable/backlight 逻辑。
- 触摸侧按 Goodix 电容触摸适配，Wiki 截图中出现 `10-0014 Goodix Capacitive TouchScreen`，可优先按 I2C 地址 `0x14` 排查。
- 掌机横屏显示需要旋转：目标 UI/模拟器输出按 800x480 使用，底层面板仍是 480x800。

## 8. 对 GBA 掌机方案的影响

这块屏适合继续用于当前验证方案，但文档中的屏幕描述应从“800x480 DSI 屏”修正为“480x800 竖屏，横屏使用时旋转为 800x480”。

GBA 原生 240x160，横屏后仍可按 3 倍整数缩放到 720x480，左右各 40 像素黑边。也就是说显示效果判断不变，只是底层屏幕方向和设备树 timing 要按竖屏处理。

## 9. 下一步

1. 画 `U90074 39pin -> Waveshare 15pin DSI` 转接板。
2. 转接板只接 D0/D1/CLK、I2C、3.3V、GND，D2/D3 和 LEDA/LEDK 暂不接。
3. 上电前先测 `VCC_LCD_MIPI_2` 是否为稳定 3.3V。
4. 用示波器或逻辑分析手段确认 I2C 上是否能扫到 Goodix 地址，优先查 `0x14`。
5. 软件侧准备 RK3566 DSI panel 设备树，先点亮显示，再适配触摸。
