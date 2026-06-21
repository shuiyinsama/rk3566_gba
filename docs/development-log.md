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
