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

第一阶段上板后先跑平台探测：

```bash
./build/debug/rk3566-gba probe
```

确认 HDMI、音频、输入和温度基线后，再进入 GBA 实测准备：

```bash
./build/debug/rk3566-gba gba-check
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
