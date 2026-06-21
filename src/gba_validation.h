#pragma once

#include <iosfwd>

// 执行 GBA 实测准备检查。
// 用法：由命令行入口 `rk3566-gba gba-check` 调用，把检查结果打印到传入的输出流。
// 目的：在真正启动模拟器之前，确认板子上是否已经具备 GBA 首轮验证所需的模拟器、RetroArch core 和测试 ROM 路径。
int run_gba_validation_check(std::ostream& out);
