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
