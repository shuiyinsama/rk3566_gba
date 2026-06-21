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

验证：

- SSH 免密初始化成功，公钥已安装到 `radxa@192.168.8.43`。
- WSL 构建测试通过，`ctest --preset debug` 三项测试全部通过。
- 板端缺少 `rsync`，已通过 `tar` 兜底完成源码同步。
- 板端构建测试通过，`ctest --preset debug` 三项测试全部通过。
- 板端 `probe` 识别到 `card0-HDMI-A-1: connected`，modes 包含 `800x480`。
- 板端 `gba-check` 可运行；当前未安装 mGBA、RetroArch 和 mGBA libretro core，且未设置 `RK3566_GBA_ROM`。
