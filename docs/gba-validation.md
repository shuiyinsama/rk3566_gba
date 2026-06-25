# GBA 实测流程与记录

## 1. 目标

确认 RK3566 / Radxa CM3 在 4.3 寸 800x480 HDMI 屏上是否能稳定提供 GBA 掌机体验。

第一轮只验证 GBA，不同时展开 PS1、PSP 或其它平台，避免性能、显示、输入和音频问题混在一起。

## 2. 测试前检查

先运行平台探测和 GBA 准备检查：

```bash
./build/debug/rk3566-gba probe
./build/debug/rk3566-gba gba-check
```

必须记录：

- 系统镜像和内核版本。
- HDMI 是否为 `card0-HDMI-A-1: connected`。
- HDMI modes 是否包含 `800x480`。
- 当前使用的音频设备。
- 当前输入设备。
- 初始温度。
- mGBA 或 RetroArch mGBA core 是否已安装。

## 3. 推荐首轮设置

首轮尽量减少变量：

- 模拟器优先使用 mGBA，其次使用 RetroArch mGBA core。
- 屏幕使用 800x480 横屏。
- GBA 画面优先 3x 整数缩放到 720x480。
- 先使用 USB 手柄或键盘，暂不依赖触摸。
- 音频优先使用 HDMI 音频；若有问题，再切到板载音频或 USB 声卡。
- 单次连续运行 30 分钟，中途不要频繁切换设置。

一键启动脚本：

```bash
bash ~/rk3566_gba/scripts/launch-gba.sh /home/radxa/roms/gba/pokemon-green.gba
```

脚本会自动寻找 X11 显示号、设置 `XAUTHORITY`、切换 HDMI 到 800x480，并用 mGBA 3x 缩放启动 ROM。

## 4. 稳定性监控

推荐用电脑端脚本启动并观察 30 分钟记录：

```powershell
python tools\monitor_gba_from_pc.py --launch --rom /home/radxa/roms/gba/pokemon-green.gba --duration 1800 --interval 10
```

这条命令做两件事：

1. 通过 SSH 在板子上执行 `bash ~/rk3566_gba/scripts/launch-gba.sh --background ...`，让 mGBA 在 HDMI 屏上后台运行。
2. 继续执行 `bash ~/rk3566_gba/scripts/monitor-gba.sh --duration 1800 --interval 10`，每 10 秒采集一次温度、CPU、内存、mGBA 进程、HDMI 当前模式和可选窗口标题。

如果已经手动启动了 mGBA，只想从电脑上看记录，运行：

```powershell
python tools\monitor_gba_from_pc.py --duration 1800 --interval 10
```

日志位置：

- 电脑端实时输出副本：`logs/gba-monitor-pc-*.log`。
- 板端文本日志：`~/rk3566_gba/logs/gba-stability-*.log`。
- 板端 CSV 数据：`~/rk3566_gba/logs/gba-stability-*.csv`。

CSV 用来后续画温度曲线或对比不同散热方案；文本日志用来快速看当时屏幕、音频和进程状态。

## 5. 手柄输入验证

当前 Radxa 内核没有可加载的 `joydev` 模块，因此不会生成 `/dev/input/js0`。如果 `evtest` 能看到手柄事件，但 mGBA 不能直接识别手柄，可先使用用户层映射脚本：

```bash
sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3 --show-events
```

脚本做的事：

1. 读取 `/dev/input/event3` 中的 Xbox 手柄事件。
2. 通过 `/dev/uinput` 创建一把虚拟键盘。
3. 把手柄方向键转换成键盘方向键。
4. 把 `BTN_SOUTH` 转成 `X`，作为 mGBA 默认的 GBA A 键。
5. 把 `BTN_EAST` 转成 `Z`，作为 mGBA 默认的 GBA B 键。
6. 把 `BTN_START` 转成 `Enter`，把 `BTN_SELECT` 转成 `Backspace`。
7. 把 `BTN_TL` / `BTN_TR` 转成 `A` / `S`，对应 mGBA 默认的 L/R。

验证方法：

1. 先在一个 SSH 终端运行映射脚本，并保持不退出。
2. 另一个终端启动 mGBA：

```bash
bash ~/rk3566_gba/scripts/launch-gba.sh /home/radxa/roms/gba/pokemon-green.gba
```

3. 确认 mGBA 窗口获得焦点。
4. 按方向键、A/B、Start/Select，观察游戏是否响应。
5. 如果 A/B 体感相反，停止脚本后加 `--swap-ab` 再试。

```bash
sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3 --swap-ab --show-events
```

## 6. 单次测试记录模板

| 项目 | 记录 |
| --- | --- |
| 日期 |  |
| 开发板 | Radxa CM3 IO Board |
| 系统镜像 |  |
| 内核版本 |  |
| 屏幕 | 4.3 寸 HDMI 800x480 |
| 模拟器 |  |
| 游戏 |  |
| 渲染/缩放设置 |  |
| 输入设备 |  |
| 音频设备 |  |
| 初始温度 |  |
| 15 分钟温度 |  |
| 30 分钟温度 |  |
| 帧率表现 |  |
| 音频表现 |  |
| 输入延迟主观感受 |  |
| 存档/菜单/退出 |  |
| 电脑端监控日志 |  |
| 板端 CSV 日志 |  |
| 结论 |  |

## 7. 判断标准

通过标准：

- 能稳定接近 60 FPS。
- 音频无明显爆音、断续或不同步。
- 输入延迟主观可接受。
- 30 分钟运行无崩溃、无明显降频卡顿。
- 温度趋势可接受，并且散热余量仍可优化。

未通过时优先记录现象，不急着同时更换多个变量。建议一次只调整模拟器、音频路径、缩放方式或散热条件中的一项。

## 8. 通过后的下一步

GBA 首轮通过后，再继续：

1. 增加不同类型 GBA 游戏样本。
2. 测试 USB 手柄映射、菜单键和退出流程。
3. 验证 PS1。
4. 评估 PSP 的可玩边界。
5. 根据温度和输入体验决定是否进入成品形态定义。

## 9. 首轮记录

| 项目 | 记录 |
| --- | --- |
| 日期 | 2026-06-22 |
| 开发板 | Radxa CM3 IO Board |
| 系统镜像 | Debian GNU/Linux 12 (bookworm) |
| 内核版本 | `6.1.84-18-rk2410-nocsf` |
| 屏幕 | 4.3 寸 HDMI 800x480 |
| 模拟器 | mGBA Qt `0.10.1` |
| 游戏 | `pokemon-green.gba`，识别标题 `POKEMON EMER` |
| 渲染/缩放设置 | 桌面窗口模式，HDMI 输出临时切换到 800x480 |
| 输入设备 | 暂未正式验证 |
| 音频设备 | 暂未正式验证 |
| 初始温度 | 待补充 |
| 15 分钟温度 | 待补充 |
| 30 分钟温度 | 待补充 |
| 帧率表现 | 标题栏显示约 `59.5 fps` |
| 音频表现 | 待补充 |
| 输入延迟主观感受 | 待补充 |
| 存档/菜单/退出 | 待补充 |
| 电脑端监控日志 | 待补充 |
| 板端 CSV 日志 | 待补充 |
| 结论 | mGBA Qt 已成功出画面，GBA 运行路线可行；仍需继续做 30 分钟稳定性、输入、音频和掌机化启动验证。 |

## 10. 30 分钟稳定性记录

| 项目 | 记录 |
| --- | --- |
| 日期 | 2026-06-25 |
| 开发板 | Radxa CM3 IO Board |
| 系统镜像 | Debian GNU/Linux 12 (bookworm) |
| 内核版本 | `6.1.84-18-rk2410-nocsf` |
| 屏幕 | `HDMI-1:800x480`，全程未变化 |
| 模拟器 | mGBA Qt `0.10.1` |
| 游戏 | `/home/radxa/roms/gba/pokemon-green.gba`，识别标题 `POKEMON EMER` |
| 启动命令 | `bash ~/rk3566_gba/scripts/launch-gba.sh --background /home/radxa/roms/gba/pokemon-green.gba` |
| 监控命令 | `bash ~/rk3566_gba/scripts/monitor-gba.sh --duration 1800 --interval 10 --tag gba-stability` |
| 渲染/缩放设置 | mGBA 全屏，`--scale 3`，GBA 240x160 放大到 720x480 |
| 采样数量 | 175 个样本 |
| 初始温度 | `73.9 C` |
| 15 分钟温度 | `71.7 C`，采样点 `899s` |
| 30 分钟温度 | `71.7 C`，采样点 `1798s` |
| 温度范围 | `71.1 C` 到 `73.9 C` |
| CPU 频率 | 全程记录为 `1800 MHz` |
| mGBA 进程 | 全程存在，未崩溃 |
| HDMI 显示模式 | 全程 `HDMI-1:800x480`，未恢复到 1920x1080 |
| 帧率表现 | 监控脚本未读取到窗口标题；人工首轮观察标题栏约 `59.5 fps` |
| 音频表现 | 本轮未做主观听感记录 |
| 输入延迟主观感受 | 本轮未做正式输入记录 |
| 存档/菜单/退出 | 本轮未验证 |
| 电脑端监控日志 | `logs/gba-monitor-pc-20260625-210635.log` |
| 板端文本日志 | `logs/gba-stability-20260625-120633.log`，板端原路径 `/home/radxa/rk3566_gba/logs/gba-stability-20260625-120633.log` |
| 板端 CSV 日志 | `logs/gba-stability-20260625-120633.csv`，板端原路径 `/home/radxa/rk3566_gba/logs/gba-stability-20260625-120633.csv` |
| 结论 | GBA 模拟器 30 分钟稳定性基线通过；未出现崩溃、分辨率回退或持续升温。下一轮应验证输入、音频和退出/重启体验。 |

## 11. USB 手柄输入记录

| 项目 | 记录 |
| --- | --- |
| 日期 | 2026-06-25 |
| 手柄 | Microsoft Xbox Series S/X Controller，USB 有线连接 |
| evdev 设备 | `/dev/input/event3` |
| joydev 设备 | 未生成 `/dev/input/js0` |
| joydev 状态 | `sudo modprobe joydev` 失败，当前内核未提供 `joydev` 模块 |
| mGBA 原生识别 | 未识别到手柄，KDE Game Controller 页面也未找到 joystick 设备 |
| 临时方案 | 使用 `scripts/gamepad-keyboard-bridge.py` 读取 evdev，并通过 `/dev/uinput` 创建虚拟键盘 |
| 验证命令 | `sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3 --show-events` |
| 游戏验证 | 映射脚本运行后，手柄可以操控 mGBA 中的 GBA 游戏 |
| 注意事项 | 如果 Xbox 灯不亮或按键无输出，先重新确认 USB 有线连接和 `evtest /dev/input/event3` 是否仍有事件 |
| 结论 | 输入验证通过，但当前依赖用户层 evdev 到键盘映射；后续掌机化阶段需要把该映射做成更稳定的启动流程或替换为更合适的输入后端。 |
