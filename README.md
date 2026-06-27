# rk3566_gba

RK3566 / Radxa CM3 掌机验证项目。当前第一验证目标是 GBA，第一阶段使用 Radxa CM3 IO Board + 4.3 寸 HDMI 屏完成系统、显示、输入、音频、散热和 GBA 模拟器验证；成品阶段再围绕目标 DSI 屏设计自研 CM3 底板。

## 构建

项目使用 CMake 管理。

Windows 开发机建议通过 WSL Ubuntu 构建，不需要 SSH 到 WSL。SSH 主要用于后续连接 Radxa CM3 板端做实际硬件验证。

```bash
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
./build/debug/rk3566-gba --help
```

若之前在 Windows 原生路径下生成过 `build/debug`，切到 WSL 后可能遇到 CMake cache 路径不匹配。删除 `build/debug` 后重新运行 `cmake --preset debug` 即可。

## 开发助手

Windows 上可以启动 Python 图形窗口，把 WSL 构建、同步源码、板端构建和板端验证做成按钮：

```powershell
python tools\radxa_dev_gui.py
```

首次连接板子时，先填写用户名和 IP，然后点“初始化 SSH 免密终端”，按提示输入一次板子密码。之后常用流程可以点“一键全流程”。

同步源码时优先使用板端 `rsync`。如果板端没有安装 `rsync`，开发助手会自动改用 `tar` 兜底同步；兜底同步可以继续推进验证，但不会删除板端已存在而本地已移除的旧文件。

进入 GBA 实测前，点“板端安装 GBA 工具”安装 `mgba-qt`、`retroarch` 和 `libretro-mgba`。这个步骤需要在弹出的终端里输入一次板子 sudo 密码。

第一阶段上板后先跑平台探测：

```bash
./build/debug/rk3566-gba probe
```

确认 HDMI、音频、输入和温度基线后，再进入 GBA 实测准备：

```bash
./build/debug/rk3566-gba gba-check
```

GBA 模拟器环境准备好后，可以用一键启动脚本切换 HDMI 分辨率并启动 mGBA：

```bash
bash ~/rk3566_gba/scripts/launch-gba.sh /home/radxa/roms/gba/pokemon-green.gba
```

开始 30 分钟稳定性记录时，可以直接在电脑上运行：

```powershell
python tools\monitor_gba_from_pc.py --launch --rom /home/radxa/roms/gba/pokemon-green.gba --duration 1800 --interval 10
```

这条命令会通过 WSL SSH 连接板子，先后台启动 mGBA，再把温度、CPU、内存、mGBA 进程和 HDMI 模式实时显示在电脑终端里；电脑端日志会写入 `logs/`，板端 CSV 和文本日志会写入 `~/rk3566_gba/logs/`。

如果模拟器已经在板子上运行，只想记录当前状态，可以去掉 `--launch`：

```powershell
python tools\monitor_gba_from_pc.py --duration 1800 --interval 10
```

如果 mGBA 无法直接识别 USB 手柄，但 `evtest` 能看到手柄事件，可以先用用户层映射脚本把手柄转换成 mGBA 默认键盘按键：

```bash
sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3 --show-events
```

保持这个终端运行，再启动 mGBA。默认映射为方向键、`X`/`Z`、`Enter`、`Backspace`、`A`/`S`，对应 mGBA 常见默认键位。

音频验证可以先列出板端音频状态，再播放测试音：

```bash
bash ~/rk3566_gba/scripts/audio-check.sh
bash ~/rk3566_gba/scripts/audio-check.sh --play
```

如果默认设备没有声音，再根据 `aplay -l` 中的声卡编号尝试 `--device plughw:X,Y`。

退出和重启验证使用会话管理脚本：

```bash
bash ~/rk3566_gba/scripts/gba-session.sh status
bash ~/rk3566_gba/scripts/gba-session.sh stop
bash ~/rk3566_gba/scripts/gba-session.sh start /home/radxa/roms/gba/pokemon-green.gba
bash ~/rk3566_gba/scripts/gba-session.sh restart /home/radxa/roms/gba/pokemon-green.gba
```

一键掌机模式会把手柄映射和 mGBA 启动合在一起：

```bash
bash ~/rk3566_gba/scripts/gba-handheld.sh start /home/radxa/roms/gba/pokemon-green.gba
bash ~/rk3566_gba/scripts/gba-handheld.sh status
bash ~/rk3566_gba/scripts/gba-handheld.sh stop
```

手柄的 `/dev/input/eventX` 编号可能会变化，脚本会优先使用 `/dev/input/by-id/*event-joystick` 自动定位。需要排查时运行：

```bash
bash ~/rk3566_gba/scripts/gba-handheld.sh --list-gamepads
```

## 文档

- [RK3566 多模拟器掌机阶段方案](docs/hardware-selection.md)
- [阶段一 HDMI 验证清单](docs/phase1-hdmi-validation.md)
- [GBA 实测流程与记录](docs/gba-validation.md)
- [开发记录](docs/development-log.md)
- [Radxa CM3 IO Board DSI 接口分析](docs/cm3-io-dsi-analysis.md)
- [Waveshare 4inch DSI LCD 适配分析](docs/waveshare-4inch-dsi-lcd-analysis.md)
- [U90074 转 Waveshare 15-pin DSI 转接小板草案](hardware/u90074_to_waveshare_15pin_dsi/README.md)

## 当前路线

第一阶段使用 Radxa CM3 IO Board + 4.3 寸 HDMI 屏验证系统、模拟器性能、输入、音频、功耗和散热。DSI 屏和自研掌机底板放到第二阶段，在确认 RK3566 性能边界后再选型。

## 文档编码

本仓库 Markdown 文档使用 UTF-8。若在 PowerShell 或部分终端看到中文乱码，优先用 VS Code、Typora、Obsidian 或其它 UTF-8 Markdown 查看器打开。
