# rk3566_gba

RK3566 / Radxa CM3 掌机验证项目。当前第一验证目标是 GBA，第一阶段使用 Radxa CM3 IO Board + 4.3 寸 HDMI 屏完成系统、显示、输入、音频、散热和 GBA 模拟器验证；成品阶段再围绕目标 DSI 屏设计自研 CM3 底板。

## 构建

项目使用 CMake 管理。

```bash
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
./build/debug/rk3566-gba --help
```

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
