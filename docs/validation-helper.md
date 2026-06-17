# 阶段一验证工具

`rk3566-gba` 是阶段一验证用的命令行助手。当前版本不集成模拟器，只负责输出验证步骤、列出上板命令、生成测试记录文件。

## 命令

```bash
rk3566-gba --help
rk3566-gba --version
rk3566-gba --checklist
rk3566-gba --system-commands
rk3566-gba --new-record records/phase1-001.md
```

## 用法建议

- 上板前先运行 `--checklist` 对照验证顺序。
- 首次启动系统后运行 `--system-commands`，按输出命令收集系统、显示、USB、音频、温度信息。
- 每轮测试前运行 `--new-record` 生成一份测试记录，再把实际结果填进去。

## 当前边界

- 不负责安装模拟器。
- 不直接读取系统温度、帧率或功耗。
- 不处理 DSI panel、触摸驱动或底板硬件配置。

