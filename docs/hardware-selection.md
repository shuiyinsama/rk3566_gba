# RK3566 多模拟器掌机阶段方案

## 1. 项目定位

本项目以 GBA 模拟器作为第一验证目标，同时保留扩展为 Linux 多模拟器掌机的空间。

目标平台：

- 核心板：Radxa CM3 / RK3566，后续成品也计划沿用。
- 第一阶段底板：Radxa CM3 IO Board，仅作为开发验证平台。
- 第一阶段屏幕：4.3 寸 HDMI 触摸屏，优先 800x480。
- 成品阶段屏幕：重新评估 4.3 寸或 5 寸 DSI 屏，并在自研底板上直接集成屏幕接口。

当前重点不是先攻克 DSI 屏点亮，而是先验证 RK3566 是否能稳定完成 GBA 掌机体验，再继续评估 PS1、N64、PSP 等平台。

## 2. 性能边界判断

RK3566 适合先做 GBA/PS1 等轻中量级复古模拟掌机，但不适合把 3DS 作为核心目标。

推荐目标分层：

| 平台 | 预期 |
| --- | --- |
| GBA / GBC / GB / NES / FC / MD / SFC | 主要目标，预期稳定 |
| PS1 | 主要目标，预期稳定 |
| CPS / Neo Geo / 常见街机 | 主要目标，需按核心和游戏验证 |
| N64 | 可尝试，兼容性和性能分游戏 |
| PSP | 可尝试，建议按 1x 分辨率和游戏列表验证 |
| Dreamcast | 可尝试，部分游戏可玩 |
| 3DS | 不建议作为设计目标 |
| PS2 / GameCube / Wii / Switch | 不建议作为设计目标 |

PSP 可以作为探索目标，但需要接受部分游戏降帧、跳帧或单独调参。3DS 对 CPU/GPU 压力明显高于 RK3566 的舒适区，不建议为了 3DS 改变硬件路线。

## 3. 阶段路线

### 3.1 阶段一：HDMI + GBA 验证平台

使用 Radxa CM3 IO Board + 4.3 寸 HDMI 屏完成软件和体验验证。

推荐屏幕：

- Waveshare 4.3inch HDMI LCD (B)，800x480，电容触摸。
- 同类 4.3 寸 800x480 HDMI + USB HID 触摸屏。
- 若需要更大的调试空间，可用 5 寸 800x480 HDMI 屏。

阶段一不要求 DSI 屏点亮，也不要求设计转接板。

验证重点：

- 系统镜像、启动、存储稳定性。
- RetroArch、mGBA、DuckStation/PCSX、PPSSPP 等模拟器运行情况。
- PSP 游戏实际帧率、音频同步、延迟和发热。
- USB 手柄或临时按键输入映射。
- 音频输出、音量控制、耳机/扬声器方案方向。
- 屏幕尺寸、分辨率、横屏 UI 和前端体验。
- 长时间运行温度和功耗。

阶段一的首要目标是回答一个问题：RK3566 + Linux 是否能稳定提供 GBA 掌机体验。GBA 达标后，再测试 PS1、N64 和 PSP 的边界。

### 3.2 阶段二：成品形态定义

在阶段一确认性能边界后，再定义成品掌机规格。

需要确定：

- 最终重点平台：GBA/PS1 为主，还是加入 PSP 作为重要目标。
- 屏幕尺寸：4.3 寸优先，5 寸作为大掌机备选。
- 屏幕分辨率：800x480 优先，必要时评估 720p。
- 输入布局：方向键、ABXY、L1/R1、L2/R2、Start/Select、Home/Menu、音量键。
- 是否需要模拟摇杆。
- 电池容量、续航目标、散热结构。
- 外壳尺寸和屏幕 FPC 位置。

### 3.3 阶段三：自研 CM3 掌机底板

成品阶段不建议继续迁就 CM3 IO Board 的 `LCD1` 或 `U90074` 连接器形态。应直接围绕最终屏幕和结构画自研底板。

自研底板建议集成：

- Radxa CM3 连接器。
- 目标 DSI 屏 FPC 座。
- 触摸 I2C、RST、INT。
- 背光电源、PWM 和 enable 控制。
- GPIO 按键或按键矩阵。
- I2S codec、功放、扬声器和耳机接口。
- 电池充放电、电量计、电源路径管理。
- USB-C 供电、调试和数据。
- microSD 或 eMMC 使用策略。
- 散热片、螺丝柱和结构固定点。

这样成品机不会有独立 DSI 转接小板，屏幕 FPC 可以直接插到底板上。

## 4. 屏幕策略

### 4.1 第一阶段 HDMI 屏

第一阶段用 HDMI 屏是为了减少变量。HDMI 屏只负责显示和临时触摸，不代表最终产品形态。

购买建议：

- 优先 4.3 寸，800x480。
- 优先电容触摸。
- 触摸必须走 USB HID，避免依赖 Raspberry Pi GPIO/SPI 的触摸方案。
- 供电尽量为 5V USB，方便调试。
- 不必追求高分辨率或 AMOLED。

### 4.2 成品阶段 DSI 屏

成品阶段再选 DSI 屏会更合理，因为自研底板可以直接按屏幕规格书设计接口。

优先规格：

- 4.3 寸 800x480 横屏 DSI 触摸屏。
- 5 寸 800x480 DSI 触摸屏作为大尺寸备选。
- 资料必须齐全：FPC pinout、供电需求、背光参数、触摸芯片、初始化序列或 Linux/RK356x 参考。

建议优先考虑：

- Waveshare 43H-800480-IPS-CT / QLED-CT。
- Waveshare 4.3inch DSI LCD。
- Waveshare 50H-800480-IPS-CT，若接受更大整机。

不建议：

- SPI 小屏，刷新率和延迟不适合。
- 只提供 Raspberry Pi overlay、没有 pinout 或初始化资料的屏。
- 为 3DS 做双屏或特殊比例屏幕。

## 5. 当前 CM3 IO Board 的角色

Radxa CM3 IO Board 只作为第一阶段验证底板。

它适合：

- 启动系统。
- 验证 HDMI 输出。
- 验证 USB 输入和存储。
- 验证网络、音频、功耗和散热。
- 作为后续 DSI 资料分析参考。

它不适合：

- 直接作为成品掌机主板。
- 强行围绕现有 `LCD1` / `U90074` 连接器选择最终屏幕。
- 在第一阶段投入大量 DSI 转接板调试成本。

已有 DSI 分析仍然有价值，但应作为成品底板设计前的接口参考，而不是阶段一的主线任务。

## 6. 第一阶段推荐 BOM

| 模块 | 推荐 |
| --- | --- |
| 核心板 | Radxa CM3 / RK3566 |
| 验证底板 | Radxa CM3 IO Board |
| 屏幕 | Waveshare 4.3inch HDMI LCD (B) 或同类 4.3 寸 800x480 HDMI USB 触摸屏 |
| 输入 | USB 手柄、键盘，后续可临时接 GPIO 按键 |
| 存储 | microSD 或 eMMC |
| 音频 | 第一阶段优先 HDMI 音频输出或 USB 声卡；成品阶段再设计 I2S codec、功放、扬声器和耳机口 |
| 电源 | 稳定 5V/USB-C 或开发板推荐供电 |
| 散热 | 小散热片，必要时加风扇做压力测试 |

## 7. 第一阶段完成标准

阶段一完成时，应至少得到这些结论：

- GBA/PS1 是否能稳定运行。
- PSP 可玩游戏范围和不可接受游戏范围。
- UI 分辨率和 4.3 寸 800x480 是否舒服。
- 按键数量和布局是否足够。
- 音频延迟是否可接受。
- 满载温度和功耗是否可接受。
- 是否继续沿用 RK3566 / CM3 进入成品底板设计。

## 8. 后续任务清单

1. 采购或确认 4.3 寸 HDMI 800x480 USB 触摸屏。
2. 启动 Radxa 官方镜像，记录内核版本、GPU/DRM/KMS 状态。
3. 安装并测试 RetroArch、mGBA、PS1 模拟器和 PPSSPP。
4. 建立游戏测试表，记录帧率、声音、温度、功耗。
5. 验证 USB HID 触摸和 USB 手柄输入。
6. 基于测试结果决定是否进入成品底板阶段。
7. 成品阶段再选择 DSI 屏，并围绕目标屏幕画 CM3 掌机底板。

## 9. 文档编码说明

本仓库文档使用 UTF-8 Markdown。Linux、VS Code、GitHub 和大多数现代编辑器都可以直接打开。

如果在 PowerShell 或某些终端里看到中文乱码，通常是终端输出编码问题，不是 Markdown 格式不能在 Linux 使用。建议使用 VS Code、Typora、Obsidian 或支持 UTF-8 的 Markdown 查看器打开。

## 10. 参考资料

- Radxa CM3 产品页：https://radxa.com/products/cm/cm3/
- Radxa CM3 IO Board 产品页：https://radxa.com/products/cm/cm3-io-board/
- Radxa CM3 DSI 接口文档：https://docs.radxa.com/en/som/cm/cm3/getting-started/interface-usage/mipi-dsi
- mGBA 项目：https://mgba.io/
- PPSSPP 项目：https://www.ppsspp.org/
- 本仓库 DSI 接口分析：[Radxa CM3 IO Board DSI 接口分析](cm3-io-dsi-analysis.md)
- 本仓库屏幕适配分析：[Waveshare 4inch DSI LCD 适配分析](waveshare-4inch-dsi-lcd-analysis.md)
