# 开发记录

## 2026-06-17

### CMake 项目骨架

目的：把仓库从文档和硬件资料推进到可构建的软件项目，后续 GBA 验证工具、模拟器启动器和平台探测逻辑都通过 CMake 管理。

变更：

- 新增顶层 `CMakeLists.txt`。
- 新增 `CMakePresets.json`。
- 新增 `src/main.cpp`。
- 新增 `.gitignore`，排除本机构建产物。

验证：

- `cmake --preset debug`
- `cmake --build --preset debug`
- `ctest --preset debug`

### GBA 优先验证路线

目的：明确第一阶段最先验证 GBA，PS1、N64、PSP 放在 GBA 达标之后继续评估。

变更：

- 更新 `README.md`。
- 更新 `docs/hardware-selection.md`。
- 更新 `docs/phase1-hdmi-validation.md`。

### 平台探测命令

目的：第一步不直接调屏，而是先确认 HDMI、音频、输入和温度节点是否被系统识别，为后续 GBA 测试建立基线。

变更：

- 新增 `rk3566-gba probe` 命令。
- 探测 `/sys/class/drm` 的 HDMI/DRM 连接器状态和显示模式。
- 探测 `/proc/asound/cards` 的 ALSA 音频设备。
- 探测 `/sys/class/input` 的输入设备名称。
- 探测 `/sys/class/thermal` 的温度节点。

## 2026-06-21

### Radxa CM3 IO Board HDMI 基线验证

目的：确认第一阶段 HDMI 屏验证路线是否可行。

结果：

- 在 Radxa CM3 IO Board 上完成 CMake 配置、构建和运行。
- `rk3566-gba probe` 识别到 `card0-HDMI-A-1: connected`。
- HDMI modes 中出现 `800x480`，4.3 寸 HDMI 屏已可作为阶段一验证屏。
- 识别到 HDMI 音频 `rockchip-hdmi` 和板载音频 `rockchip-rk817`。
- 暂未识别到 USB 触摸输入，GBA 第一阶段验证暂不依赖触摸。
- 当前温度约 `58 C`，后续跑模拟器时需要继续观察散热。

### GBA 实测准备

目的：把 HDMI 基线验证后的下一步固定为可重复的 GBA 实测流程。

变更：

- 新增 `rk3566-gba gba-check` 命令，用于检查 mGBA、RetroArch 和测试 ROM 环境。
- 新增 `docs/gba-validation.md`，记录 GBA 首轮 30 分钟稳定性测试模板。
- 更新 `README.md` 和 `docs/phase1-hdmi-validation.md`，加入 GBA 实测入口。

验证：

- 使用本机 MinGW g++ 临时编译 `src/main.cpp`、`src/platform_probe.cpp` 和 `src/gba_validation.cpp`。
- 运行 `rk3566-gba --help`。
- 运行 `rk3566-gba gba-check`。
- 运行 `rk3566-gba probe`。

### WSL 构建环境确认

目的：确认 Windows 开发机上是否需要切到 Linux 环境构建。

结论：

- 当前 Windows 原生环境缺少 `Unix Makefiles` 所需的构建程序，`cmake --preset debug` 无法直接完成。
- WSL Ubuntu 22.04 中已具备 `cmake`、`g++`、`make` 和 `ninja`。
- 不需要 SSH 到 WSL；可直接通过 `wsl` 命令在本机 Linux 环境构建。
- 后续 SSH 主要用于连接 Radxa CM3 板端运行 `probe`、`gba-check` 和模拟器实测。

验证：

- `cmake --preset debug`
- `cmake --build --preset debug`
- `ctest --preset debug`

### 图形化开发助手

目的：减少手动输入 WSL、rsync 和 SSH 命令的重复操作。

变更：

- 新增 `tools/radxa_dev_gui.py`，提供 Windows Python/Tkinter 图形窗口。
- 支持检查 WSL 工具、WSL 构建测试、同步源码到 Radxa、板端构建测试、板端 `probe` 和板端 `gba-check`。
- 支持保存本地板端配置到 `.radxa-dev-gui.json`。
- 更新 `.gitignore`，忽略 `.radxa-dev-gui.json`。

使用：

- 在 Windows PowerShell 中运行 `python tools\radxa_dev_gui.py`。
- 首次连接板子时，点击“初始化 SSH 免密终端”并输入一次板子密码。
- 后续可点击“一键全流程”完成 WSL 构建、同步、板端构建和板端验证。

修复：

- 修复 WSL 命令经 Windows 参数层传递时 `$tool` 被错误展开的问题。
- 过滤 WSL 启动阶段无关的本地化乱码提示。
- 修复 `ssh-keygen -N ""` 空参数在 PowerShell/WSL 多层引号中丢失的问题。
- 同步源码时增加板端 `rsync` 检测；板端缺少 `rsync` 时自动使用 `tar` 兜底同步。
- 板端构建前清理 `build/debug`，避免 CMake cache 残留 Windows/WSL 路径导致源目录不匹配。
- 新增“板端安装 GBA 工具”按钮，在交互终端中安装 `mgba-qt`、`retroarch` 和 `libretro-mgba`。

验证：

- SSH 免密初始化成功，公钥已安装到 `radxa@192.168.8.43`。
- WSL 构建测试通过，`ctest --preset debug` 三项测试全部通过。
- 板端缺少 `rsync`，已通过 `tar` 兜底完成源码同步。
- 板端构建测试通过，`ctest --preset debug` 三项测试全部通过。
- 板端 `probe` 识别到 `card0-HDMI-A-1: connected`，modes 包含 `800x480`。
- 板端 `gba-check` 可运行；当前未安装 mGBA、RetroArch 和 mGBA libretro core，且未设置 `RK3566_GBA_ROM`。

## 2026-06-22

### GBA 模拟器首轮跑通

目的：确认 Radxa CM3 IO Board + 4.3 寸 HDMI 屏是否能实际运行 GBA 模拟器，而不仅是通过平台探测。

环境：

- 板端系统：Debian GNU/Linux 12 (bookworm)，`arm64`。
- 内核：`6.1.84-18-rk2410-nocsf`。
- 图形环境：KDE Plasma / X11，实际显示号为 `:1`。
- HDMI 输出：`HDMI-1`，已从 `1920x1080` 临时切换到 `800x480`。

操作：

- 手动安装 `mgba-qt`、`retroarch` 和 `libretro-mgba`。
- 准备测试 ROM：`/home/radxa/roms/gba/pokemon-green.gba`。
- 运行 `rk3566-gba gba-check`，确认 mGBA Qt、RetroArch、mGBA libretro core 和测试 ROM 均已识别。
- 使用 `DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority` 将 mGBA Qt 启动到 HDMI 屏。

结果：

- `mgba-qt` 已安装，路径为 `/usr/games/mgba-qt`。
- `retroarch` 已安装，路径为 `/usr/bin/retroarch`。
- `mgba_libretro.so` 已安装，路径为 `/usr/lib/aarch64-linux-gnu/libretro/mgba_libretro.so`。
- 测试 ROM 被系统识别为 GBA ROM，标题为 `POKEMON EMER`，大小约 `16 MB`。
- mGBA Qt 成功打开游戏画面，标题栏显示约 `59.5 fps`。
- 800x480 模式下桌面和模拟器窗口可正常显示，初步确认 GBA 运行无根本障碍。

注意：

- 从 SSH 启动图形程序时，不能使用 `DISPLAY=:0`；当前桌面显示号是 `:1`。
- 终端中前台运行 `mgba-qt` 会一直占用命令行，属于正常现象；需要后台启动或关闭窗口后才会返回。
- 目前仍是桌面窗口方式运行，尚未进入真正掌机化体验。
- 后续需要开发或固化一键启动流程：切换 800x480、设置显示环境、启动 mGBA、全屏或无边框显示、记录温度和帧率。

### GBA 一键启动脚本

目的：把手动验证时反复输入的显示环境、分辨率切换和 mGBA 启动命令固化为用户层脚本。

变更：

- 新增 `scripts/launch-gba.sh`。
- 自动检测 `/tmp/.X11-unix/X*`，避免把 `DISPLAY=:0` 或 `DISPLAY=:1` 写死。
- 自动选择 GDM 的 `XAUTHORITY` 文件。
- 自动从 `xrandr` 读取已连接显示输出，并切换到 `800x480`。
- 默认使用 mGBA 3x 缩放和全屏启动 ROM。
- 支持 `--windowed`、`--background`、`--mode`、`--scale` 和 `--keep-existing` 参数。

用法：

```bash
bash ~/rk3566_gba/scripts/launch-gba.sh /home/radxa/roms/gba/pokemon-green.gba
```

验证：

- 本地 WSL 执行 `bash -n scripts/launch-gba.sh` 通过。
- 同步到板端后执行 `bash -n ~/rk3566_gba/scripts/launch-gba.sh` 通过。
- `bash ~/rk3566_gba/scripts/launch-gba.sh --help` 可正常输出帮助。
- 执行 `bash ~/rk3566_gba/scripts/launch-gba.sh --background /home/radxa/roms/gba/pokemon-green.gba` 成功。
- 脚本自动识别 `DISPLAY=:0`、`XAUTHORITY=/run/user/1000/gdm/Xauthority` 和输出 `HDMI-1`。
- 脚本成功将 HDMI 输出切换到 `800x480`。
- mGBA 以 `mgba-qt -f --scale 3 /home/radxa/roms/gba/pokemon-green.gba` 启动并保持运行。

## 2026-06-25

### GBA 稳定性监控脚本

目的：在模拟器已经能跑起来之后，开始把 30 分钟稳定性记录做成可重复流程，并且让电脑端可以实时看到板端采样信息。

变更：

- 新增 `scripts/monitor-gba.sh`，在板端采集温度、CPU、CPU 频率、内存、系统负载、mGBA 进程状态、HDMI 当前模式和可选窗口标题。
- 新增 `tools/monitor_gba_from_pc.py`，在 Windows 开发机上通过 WSL SSH 执行板端监控脚本，并把输出实时保存到电脑端 `logs/`。
- 更新 `tools/radxa_dev_gui.py`，增加“GBA 稳定性监控”按钮；填写 ROM 路径时会先后台启动 mGBA，再监控 30 分钟。
- 更新 `README.md` 和 `docs/gba-validation.md`，补充电脑端监控命令、日志位置和单次测试记录字段。
- 更新 `.gitignore`，忽略本地 `logs/` 监控输出。

用法：

```powershell
python tools\monitor_gba_from_pc.py --launch --rom /home/radxa/roms/gba/pokemon-green.gba --duration 1800 --interval 10
```

如果 mGBA 已经在板端运行，可以去掉 `--launch` 只做记录：

```powershell
python tools\monitor_gba_from_pc.py --duration 1800 --interval 10
```

### GBA 30 分钟稳定性记录

目的：在一键启动脚本和监控脚本可用后，完成第一轮正式 GBA 连续运行记录。

操作：

- 使用 `tools/monitor_gba_from_pc.py` 通过 WSL SSH 启动板端 mGBA。
- 运行板端 `scripts/monitor-gba.sh`，采样间隔 `10s`，计划时长 `1800s`。
- 监控结束后将板端 `.log` 和 `.csv` 拉回电脑 `logs/` 目录。
- 记录结束后停止 `mgba-qt`，避免板子继续空跑发热。

结果：

- 共采集 175 个样本。
- 温度范围为 `71.1 C` 到 `73.9 C`。
- 15 分钟温度为 `71.7 C`。
- 结束点 `1798s` 温度为 `71.7 C`。
- CPU 频率全程记录为 `1800 MHz`。
- mGBA 进程全程存在，未崩溃。
- HDMI 模式全程保持 `HDMI-1:800x480`，未恢复到 1920x1080。
- 本轮没有同步验证音频、输入、菜单、存档和退出体验。

结论：

- GBA 模拟器 30 分钟稳定性基线通过。
- 后续优先验证 USB 手柄输入、音频路径、退出/重启流程和开机自启动体验。

### 手柄到键盘映射脚本

目的：当前板端内核没有可加载的 `joydev` 模块，无法生成 `/dev/input/js0`；mGBA 也未直接识别 USB 手柄。因此先增加用户层输入映射，把 evdev 手柄事件转换成 mGBA 默认键盘按键。

环境发现：

- 手柄识别为 `Microsoft Xbox Series S|X Controller`。
- 手柄 evdev 设备为 `/dev/input/event3`。
- `evtest` 能看到 `BTN_SOUTH` 等按键事件。
- `sudo modprobe joydev` 失败，当前内核目录中没有 `joydev` 模块。
- `/dev/uinput` 存在，可以创建用户层虚拟键盘。

变更：

- 新增 `scripts/gamepad-keyboard-bridge.py`。
- 脚本读取 `/dev/input/eventX`，通过 `/dev/uinput` 创建虚拟键盘。
- 默认把方向键映射为键盘方向键。
- 默认把 `BTN_SOUTH` / `BTN_EAST` 映射为 `X` / `Z`，对应 mGBA 常见默认 A/B 键位。
- 默认把 `BTN_START` / `BTN_SELECT` 映射为 `Enter` / `Backspace`。
- 支持 `--swap-ab` 调换 A/B 体感。
- 支持 `--show-events` 打印转换过程，便于手动验证。

用法：

```bash
sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3 --show-events
```

保持映射脚本运行后，再启动 mGBA。若游戏里 A/B 体感相反，可改用：

```bash
sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3 --swap-ab --show-events
```

验证：

- 初次测试时 Xbox 灯未亮且映射脚本没有打印按键事件，判断不是 mGBA 配置问题，而是手柄连接/事件输入状态需要先确认。
- 重新确认有线连接后，映射脚本可读取 `/dev/input/event3` 并转换成虚拟键盘输入。
- mGBA 获得焦点后，手柄可以操控 GBA 游戏。

结论：

- USB 手柄输入链路已跑通。
- 当前可行路线是 `evdev -> /dev/uinput 虚拟键盘 -> mGBA 默认键盘映射`。
- 后续需要把映射脚本纳入一键启动或系统服务，避免每次手动开两个终端。
