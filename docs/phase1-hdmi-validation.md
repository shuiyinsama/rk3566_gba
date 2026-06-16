# 阶段一 HDMI 验证清单

## 1. 目标

第一阶段使用 Radxa CM3 IO Board 和 HDMI 小屏验证 RK3566 掌机方案，不在这一阶段处理 DSI 转接板和 panel 驱动。

核心问题：

- RK3566 是否足够支撑目标模拟器。
- 4.3 寸 800x480 横屏是否适合当前掌机方向。
- 输入、音频、散热和功耗是否具备进入成品板设计的基础。

## 2. 推荐屏幕

优先选择：

- Waveshare 4.3inch HDMI LCD (B)。
- 其它 4.3 寸 800x480 HDMI 屏。

必须确认：

- HDMI 视频输入。
- USB 供电。
- 如果带触摸，触摸应为 USB HID。
- 不依赖 Raspberry Pi GPIO 或 SPI 触摸。

不建议第一阶段购买：

- SPI 显示屏。
- 电阻触摸且依赖 GPIO/SPI 的屏。
- 高价 1080p AMOLED 屏。
- 需要定制驱动板或特殊 EDID 的屏。

## 3. 接线

基础连接：

- CM3 IO Board HDMI -> HDMI 屏。
- HDMI 屏 USB 电源 -> 稳定 5V USB 电源。
- 若需要触摸，HDMI 屏 USB 触摸线 -> CM3 IO Board USB。
- USB 手柄或键盘 -> CM3 IO Board USB。

调试建议：

- 屏幕和 CM3 IO Board 尽量分开供电，避免小屏供电口反向影响开发板。
- 第一次启动先不接触摸，只接 HDMI 显示。
- 系统稳定后再接 USB 触摸和手柄。

## 4. 系统验证

记录：

- 镜像名称和版本。
- 内核版本。
- 桌面环境或 DRM/KMS 输出方式。
- HDMI 识别到的分辨率和刷新率。
- 是否需要手动设置 800x480。

命令参考：

```bash
uname -a
cat /etc/os-release
ls /sys/class/drm
```

## 5. 模拟器验证

建议按平台分层测试。

基础平台：

- GBA：mGBA 或 RetroArch mGBA core。
- PS1：DuckStation、PCSX ReARMed 或 RetroArch core。
- SFC/MD/FC/街机：RetroArch 对应 core。

探索平台：

- PSP：PPSSPP，优先 1x 渲染分辨率。
- N64：Mupen64Plus / RetroArch core。
- Dreamcast：Flycast。

每个游戏记录：

- 模拟器和版本。
- 渲染后端。
- 分辨率倍率。
- 是否开 frameskip。
- 平均帧率。
- 声音是否爆音或不同步。
- 输入延迟主观感受。
- 运行 15 分钟后的温度。

## 6. 音频验证

第一阶段可以按优先级使用这些音频路径：

1. HDMI 屏自带耳机口或音频输出。
2. USB 声卡或 USB 音箱。
3. CM3 IO Board 自带音频接口。

验证重点：

- 系统是否能识别 HDMI/USB 音频设备。
- 模拟器声音是否和画面同步。
- 音量调节是否方便。
- 是否有爆音、底噪或断续。
- 长时间运行时声音是否稳定。

## 7. PSP 测试建议

PSP 是 RK3566 的探索目标，不要只用轻量游戏判断整体可行。

建议准备三档游戏：

- 轻量：2D、文字、策略、节奏类。
- 中等：常见 3D 动作、赛车、格斗。
- 重负载：God of War、GTA、Midnight Club 一类。

测试重点：

- 1x 分辨率是否稳定。
- Vulkan/OpenGL ES 哪个更稳。
- 是否需要 frameskip。
- 音频是否同步。
- 发热是否明显影响持续性能。

## 8. 屏幕体验验证

用 4.3 寸 800x480 横屏重点观察：

- GBA 3x 整数缩放是否舒服。
- PSP 480x272 放大到 800x480 后黑边和清晰度是否可接受。
- 前端 UI 字号是否可读。
- 菜单、存档、设置页面是否适合小屏操作。
- 触摸是否有必要保留到成品阶段。

## 9. 成品阶段输入结论

阶段一结束后，应明确这些问题：

- 是否需要双摇杆。
- L2/R2 是否必须。
- Home/Menu 是否独立按键。
- 音量键和亮度键是否独立。
- 是否需要触摸作为主要交互，还是仅作为辅助。

## 10. 进入成品底板的门槛

满足以下条件后再进入 DSI 屏和自研底板设计：

- GBA/PS1 稳定。
- PSP 有明确可玩范围。
- 散热和功耗可控。
- 4.3 寸或 5 寸屏幕尺寸已确认。
- 输入布局已确认。
- 确认继续沿用 Radxa CM3 核心板。
