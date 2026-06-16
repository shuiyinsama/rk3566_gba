# RK3566 + 800x480 DSI 屏 GBA 掌机选型文档

## 1. 项目背景

前期项目基于 ESP32-S3 + RGB LCD 实现 Game Boy 形态掌机验证。新方案希望切换到 RK3566 平台，使用 Linux 生态承载 GBA 模拟器，并以 800x480 DSI 电容触摸屏作为主要显示输出，目标是开发一台更接近可用掌机体验的 GBA 模拟设备。

当前验证阶段拟使用：

- 核心板：Radxa CM3 / RK3566 核心板
- 开发底板：Radxa CM3 IO Board
- 显示屏：Waveshare 4inch DSI LCD，480x800 竖屏，横屏使用时旋转为 800x480
- 模拟目标：Game Boy Advance

说明：用户口述的 “Radxa M3” 本文按 Radxa CM3 理解。正式采购和设计前需再次核对实际板卡丝印、料号、版本和接口定义。

## 2. 选型结论

推荐以 RK3566 + Linux + mGBA/RetroArch 作为 GBA 掌机主方案。RK3566 的 CPU/GPU/内存资源相较 ESP32-S3 有明显余量，适合运行成熟 GBA 模拟器、音视频同步、存档、菜单、手柄输入映射和后续 UI。

Waveshare 4inch DSI LCD 的硬件分辨率是 480x800 竖屏，横屏使用时可旋转为 800x480。这个横屏形态对 GBA 非常友好：GBA 原生分辨率为 240x160，按 3 倍整数缩放后为 720x480，刚好占满 480 垂直像素，左右各留 40 像素黑边，可获得清晰、无纵向拉伸的显示效果。

结合 CM3 IO Board V1.36 原理图和 CM3 V1.3 pinout，IO Board 已经引出两组 MIPI LCD 接口：`LCD1` 为 31pin FPC、连接 `MIPI_DSI_TX0`；`U90074` 为 39pin LCD 接口、连接 `MIPI_DSI_TX1` 并带触摸 I2C/TP 控制信号。但 Waveshare 树莓派 DSI 屏不一定能直接接到这两个接口上即用，仍需要确认屏幕 pinout、lane 数、供电、背光、触摸和设备树适配。

## 3. 核心需求

### 3.1 功能需求

- 稳定运行 GBA 模拟器，目标 60 FPS。
- 支持 800x480 屏幕输出，优先整数缩放。
- 支持方向键、A/B/L/R、Start、Select、Menu 等实体按键。
- 支持音频输出，后续支持扬声器和耳机。
- 支持游戏 ROM 选择、即时存档、普通存档、亮度/音量调节。
- 后续支持电池供电、电量检测、休眠/关机管理。

### 3.2 开发阶段需求

- 快速验证 RK3566 上的 GBA 模拟性能。
- 快速验证 800x480 屏幕显示链路。
- 快速验证输入、音频、存储和散热边界。
- 尽量复用成熟 Linux 软件栈，减少从底层重写模拟器和图形栈的风险。

## 4. 主控平台选型

### 4.1 推荐型号：RK3566

RK3566 是四核 Arm Cortex-A55 SoC，定位嵌入式 Linux 和多媒体应用，适合掌机类项目作为主控平台。相较 ESP32-S3，它的优势主要在：

- CPU 性能足以支撑成熟 GBA 模拟器。
- 可运行 Linux，方便使用 SDL2、DRM/KMS、ALSA、evdev、RetroArch 等生态。
- 支持 eMMC、SD、USB、MIPI DSI、eDP、HDMI、I2S、GPIO 等外设。
- 后续可扩展 Wi-Fi、蓝牙、前端 UI、文件管理和 OTA。

### 4.2 Radxa CM3 核心板适配性

Radxa CM3 使用 RK3566，提供不同内存/eMMC配置，并采用核心板 + 底板方式开发。它适合当前阶段原因如下：

- 开发门槛低于自研 RK3566 主板。
- 官方资料、镜像和社区经验较多。
- 可先在 IO Board 上验证系统、模拟器、输入、存储和音频。
- 后续可基于 CM3 连接器设计专用掌机底板。

### 4.3 风险与限制

- CM3 IO Board 已暴露 MIPI DSI，但接口不是树莓派标准 15pin DSI 形态，接 Waveshare 树莓派 DSI 屏大概率需要转接板。
- DSI 屏需要设备树、面板初始化序列、触摸 I2C、背光 PWM/GPIO 等适配。
- Linux 图形栈选择会影响启动速度、延迟和调试复杂度。
- RK3566 长时间满载运行需要关注散热。

## 5. 显示屏选型

### 5.1 推荐方向：480x800 DSI IPS 电容屏，横屏旋转使用

当前 Waveshare 4inch DSI LCD 是 480x800 竖屏。用于掌机时建议横屏安装或软件旋转为 800x480，这仍是本项目适配 GBA 的优选分辨率：

- GBA 原生 240x160，3 倍整数缩放为 720x480。
- 垂直方向正好铺满屏幕，无需非整数缩放。
- 左右黑边较小，画面观感接近掌机。
- 800x480 对 RK3566 压力很低，UI 和模拟器输出都容易处理。

### 5.2 Waveshare 树莓派 DSI 屏适配点

Waveshare 树莓派生态 DSI 屏通常集成：

- IPS LCD 面板。
- MIPI DSI 显示接口。
- 电容触摸，通常通过 I2C/USB 或屏幕配套方式接入。
- 背光控制。
- 面向 Raspberry Pi 的线缆和软件说明。

这些特性适合快速验证显示效果，但对非树莓派平台存在如下适配工作：

- 确认 DSI lane 数、供电电压、连接器 pinout。
- 确认触摸接口接入方式。
- 编写或移植 Linux panel/bridge 驱动配置。
- 修改设备树，添加 panel、backlight、touch、pinctrl、regulator。
- 验证开机阶段是否能点亮背光和输出图像。

### 5.3 当前开发组合的关键兼容性判断

当前组合 “Radxa CM3 + Radxa CM3 IO Board + Waveshare 4inch DSI LCD” 具备 DSI 验证基础，但不能直连，需要转接板。CM3 IO Board V1.36 的 DSI 相关接口如下：

- `LCD1`：31pin FPC，`MIPI_DSI_TX0`，4-lane DSI，带 LEDA/LEDK 和 LCD 电源，但未直接集成触摸 I2C/TP 控制脚。
- `U90074`：39pin LCD 接口，`MIPI_DSI_TX1`，4-lane DSI，带 `I2C2_SCL_LCD`、`I2C2_SDA_LCD`、`TP_INT_LCD`、`TP_RST_LCD` 和触摸电源。

建议按以下顺序确认：

1. Waveshare 屏幕为 15pin、2-lane DSI：D0/D1/CLK、I2C、3.3V、GND。
2. 优先规划 `U90074 39pin -> Waveshare 15pin DSI` 转接验证板。
3. 转接时只接 TX1 的 D0/D1/CLK、`I2C2_SCL_LCD`、`I2C2_SDA_LCD`、`VCC_LCD_MIPI_2` 和 GND。
4. `U90074` 的 D2/D3、TP_RST_LCD、TP_INT_LCD、VCC_TP、LEDA/LEDK 暂不接。
5. 软件侧同步准备 DSI panel、backlight、Goodix touch、显示旋转的设备树适配。

## 6. 软件方案选型

### 6.1 操作系统

推荐优先级：

1. Radxa 官方 Debian / Ubuntu 镜像：适合快速 bring-up 和调试。
2. Buildroot：适合后续做极简掌机系统，启动快、体积小。
3. Yocto：适合产品化和长期维护，但前期投入较高。

当前阶段建议使用官方 Debian/Ubuntu 镜像，先验证硬件链路和模拟器性能。待功能稳定后，再评估是否切到 Buildroot。

### 6.2 模拟器

推荐优先级：

1. mGBA：GBA 兼容性好，跨平台成熟，适合独立运行或集成前端。
2. RetroArch + mGBA core：配置、手柄映射、滤镜、菜单、存档体验完整。
3. gpSP：性能开销低，但兼容性和维护性通常不如 mGBA。

当前阶段建议先使用 RetroArch + mGBA core 快速验证体验；产品化阶段可再评估独立 mGBA + 自研轻量 UI。

### 6.3 图形输出

推荐路径：

- 开发验证：X11/Wayland 桌面环境下运行 RetroArch，便于调试。
- 掌机化：SDL2 + DRM/KMS 或 RetroArch KMS/DRM 输出，减少桌面环境开销。
- 最终目标：开机直接进入前端或模拟器菜单。

### 6.4 输入方案

开发阶段可使用 USB 手柄或键盘验证按键映射。掌机阶段建议使用实体按键接入 GPIO，并通过 Linux input 子系统上报为标准 evdev 事件。

推荐按键：

- D-Pad：上、下、左、右
- 操作键：A、B
- 肩键：L、R
- 系统键：Start、Select、Menu/Hotkey
- 可选：音量 + / -、亮度 + / -、电源键

### 6.5 音频方案

开发阶段优先使用 IO Board 现有音频输出或 USB 声卡。掌机阶段建议选择：

- I2S codec + 功放 + 扬声器
- 耳机检测和静音控制
- 音量按键映射到系统 mixer

## 7. 方案分阶段验证

### 7.1 阶段一：开发板 bring-up

目标：确认 RK3566 系统和模拟器性能。

验证项：

- Radxa 官方镜像启动。
- eMMC/SD 存储稳定。
- USB 键盘/手柄输入正常。
- HDMI/eDP 或可用显示输出正常。
- RetroArch + mGBA 能稳定运行 GBA ROM。
- 720x480 整数缩放显示模式可用。
- 音频输出无明显爆音和延迟。

### 7.2 阶段二：800x480 DSI 屏适配

目标：确认目标屏幕能作为主显示输出。

验证项：

- DSI 物理连接方案明确。
- 设备树中 panel、backlight、touch 配置完成。
- 内核能识别面板和触摸。
- 控制台或 DRM/KMS 能输出到 DSI。
- 背光可调。
- 触摸输入稳定。
- 横屏方向、刷新率、色彩和亮度符合预期。

### 7.3 阶段三：掌机输入和外设

目标：形成接近最终产品的交互体验。

验证项：

- GPIO 按键通过 input 子系统上报。
- RetroArch/mGBA 按键映射稳定。
- Menu/Hotkey 可进入存档、退出和设置。
- 音量和亮度可独立调整。
- 长时间运行温度可接受。

### 7.4 阶段四：专用底板设计

目标：从开发板组合转向掌机硬件形态。

建议专用底板包含：

- CM3 连接器。
- 800x480 DSI 屏接口。
- 触摸接口。
- 背光电源和 PWM 控制。
- 按键矩阵或 GPIO 按键。
- I2S codec、功放、扬声器、耳机接口。
- 电池充放电、电量计、5V/3.3V/1.8V 电源。
- USB-C 供电和调试。
- 散热结构固定点。

## 8. 初步 BOM

| 模块 | 推荐选型 | 当前用途 | 风险 |
| --- | --- | --- | --- |
| 主控 | Radxa CM3 / RK3566 | Linux + GBA 模拟器 | 需确认具体内存/eMMC版本 |
| 开发底板 | Radxa CM3 IO Board | 系统 bring-up、外设验证、DSI 接口验证 | 已引出 DSI，但连接器不是树莓派 DSI 标准形态 |
| 屏幕 | Waveshare 4inch DSI LCD，480x800 竖屏 | 目标显示验证 | 需转接到 U90074；RK3566 侧需移植 panel/Goodix 触摸设备树 |
| 输入 | USB 键盘/手柄，后续 GPIO 按键 | 开发和最终按键 | GPIO 去抖和键位映射 |
| 音频 | IO Board 音频/USB 声卡，后续 I2S codec | 声音验证 | 延迟、底噪、功放选型 |
| 存储 | eMMC 或 microSD | 系统和 ROM 存储 | 可靠性、读写寿命 |
| 电源 | 开发阶段 DC/USB-C，后续锂电池 | 供电 | 峰值电流、续航、散热 |

## 9. 关键风险

1. DSI 屏与 CM3 IO Board 的物理连接器和电气 pinout 兼容性不明确。
2. Waveshare 屏幕面向 Raspberry Pi，非 Pi 平台可能缺少现成设备树。
3. RK3566 Linux 显示栈有多种路径，早期需要控制变量，先用最容易点亮的输出验证模拟器。
4. 掌机产品化需要重新设计电源、音频、按键和结构，开发板组合只能验证核心方案。
5. 若使用桌面系统运行模拟器，启动速度和资源占用可能不符合最终掌机体验。

## 10. 推荐决策

当前阶段建议采用“两条线并行”的验证策略：

- 主线 A：用 Radxa CM3 + IO Board + HDMI/eDP 显示先跑通系统、模拟器、输入和音频，证明 RK3566 运行 GBA 的体验。
- 主线 B：基于 `LCD1`/`U90074` 单独攻关 800x480 DSI 屏的硬件连接和设备树适配，确认后再合并到掌机方案。

如果确认 CM3 IO Board 无法直接接 Waveshare DSI 屏，不建议在开发板阶段投入过多机械转接成本。更合理的路径是先用可用显示输出完成软件验证，同时画一块小型 DSI 转接板或为下一版专用底板预留正确的 DSI、触摸和背光接口。

## 11. 下一步清单

- 获取 Radxa CM3 和 CM3 IO Board 的具体版本、原理图和接口定义。
- 获取 Waveshare 目标屏幕的准确型号、原理图或接口 pinout。
- 启动 Radxa 官方镜像，记录内核版本、设备树、显示节点。
- 安装 RetroArch/mGBA，验证 GBA ROM 帧率、音频和输入。
- 设计 `U90074 39pin -> Waveshare 15pin DSI` 转接验证板。
- 若 DSI 转接路径可行，开始 RK3566 panel/Goodix 触摸设备树适配；若不经济，规划专用底板或替换屏幕方案。

## 12. 参考资料

- Radxa CM3 产品页：https://radxa.com/products/cm/cm3/
- Radxa CM3 IO Board 产品页：https://radxa.com/products/cm/cm3-io-board/
- Waveshare 5inch DSI LCD Wiki：https://www.waveshare.com/wiki/5inch_DSI_LCD
- Waveshare 7inch DSI LCD Wiki：https://www.waveshare.com/wiki/7inch_DSI_LCD
- mGBA 项目：https://mgba.io/
- 本仓库 DSI 接口分析：[Radxa CM3 IO Board DSI 接口分析](cm3-io-dsi-analysis.md)
- 本仓库屏幕适配分析：[Waveshare 4inch DSI LCD 适配分析](waveshare-4inch-dsi-lcd-analysis.md)
