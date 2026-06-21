#include "gba_validation.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// GBA 实测准备命令的实现。
// 这个文件只做“开跑前检查”和“测试流程提示”，不直接启动模拟器。
// 这样可以先把 HDMI、音频、输入、温度和模拟器环境分开确认，避免首轮 GBA 测试时变量太多。
namespace {

// PATH 和目录分隔符在 Windows 开发机与 RK3566 Linux 板端不同。
// 这里统一成两个常量，让后面的查找逻辑可以同时在本机冒烟测试和板端测试中使用。
#ifdef _WIN32
constexpr char kPathSeparator = ';';
constexpr char kDirectorySeparator = '\\';
#else
constexpr char kPathSeparator = ':';
constexpr char kDirectorySeparator = '/';
#endif

// 描述一个需要在 PATH 中查找的模拟器前端。
// label 用于输出给人看，executable 是实际要查找的命令名。
struct ToolCheck {
  std::string label;
  std::string executable;
};

// 将 PATH 环境变量拆成目录列表。
// 步骤：
// 1. 按当前平台的 PATH 分隔符切分。
// 2. 跳过空段，避免后续拼出无意义的候选路径。
// 3. 保留原始字符串，减少 Windows 中文路径上的编码转换风险。
std::vector<std::string> split_path(std::string_view value) {
  std::vector<std::string> parts;
  std::size_t start = 0;

  while (start <= value.size()) {
    const auto end = value.find(kPathSeparator, start);
    const auto part = value.substr(start, end - start);
    if (!part.empty()) {
      parts.emplace_back(part);
    }

    if (end == std::string_view::npos) {
      break;
    }
    start = end + 1;
  }

  return parts;
}

// 拼接目录和文件名。
// 这里不用 std::filesystem，是因为 Windows 上包含中文用户名的 PATH 可能触发字符集转换异常；
// gba-check 只需要判断常规文件是否存在，字符串拼接已经足够。
std::string join_path(std::string_view directory, std::string_view filename) {
  std::string path(directory);
  if (!path.empty() && path.back() != '/' && path.back() != '\\') {
    path.push_back(kDirectorySeparator);
  }
  path.append(filename);
  return path;
}

// 检查一个普通文件是否可以打开。
// 用法：用于判断模拟器可执行文件、RetroArch core 或用户指定的 ROM 路径是否存在。
bool file_exists(std::string_view path) {
  std::ifstream file(std::string(path), std::ios::binary);
  return file.good();
}

// 在 PATH 中查找一个命令。
// 步骤：
// 1. 读取 PATH；如果系统没有 PATH，就直接认为找不到。
// 2. 逐个目录拼出候选文件名。
// 3. Windows 下额外尝试 `.exe` 后缀，方便本机开发环境冒烟测试。
std::optional<std::string> find_in_path(std::string_view executable) {
  const char* path_env = std::getenv("PATH");
  if (path_env == nullptr) {
    return std::nullopt;
  }

  const auto directories = split_path(path_env);
  for (const auto& directory : directories) {
    const auto candidate = join_path(directory, executable);
    if (file_exists(candidate)) {
      return candidate;
    }

#ifdef _WIN32
    const auto exe_candidate = join_path(directory, std::string(executable) + ".exe");
    if (file_exists(exe_candidate)) {
      return exe_candidate;
    }
#endif
  }

  return std::nullopt;
}

// 在一组固定路径中找第一个存在的文件。
// 用法：RetroArch 的 libretro core 常常安装到系统固定目录，所以这里按常见路径顺序探测。
std::optional<std::string> find_first_existing(const std::vector<std::string>& paths) {
  for (const auto& path : paths) {
    if (file_exists(path)) {
      return path;
    }
  }

  return std::nullopt;
}

// 打印一个可读的小节标题，让命令输出适合直接复制进测试记录。
void print_section(std::ostream& out, std::string_view title) {
  out << "\n== " << title << " ==\n";
}

// 检查 GBA 模拟器前端是否已安装。
// 目的：首轮验证至少需要 mGBA 或 RetroArch 之一；如果都没有，后续就先安装工具，而不是继续查 ROM。
bool print_tool_checks(std::ostream& out) {
  print_section(out, "GBA emulator frontends");

  // 按优先级列出可接受的 GBA 测试入口。
  // mGBA CLI/Qt 适合直接验证 GBA；RetroArch 适合后续统一多模拟器前端。
  const std::vector<ToolCheck> tools = {
      {"mGBA CLI", "mgba"},
      {"mGBA Qt", "mgba-qt"},
      {"RetroArch", "retroarch"},
  };

  bool any_found = false;
  for (const auto& tool : tools) {
    // 每个工具都单独输出结果，方便判断“完全没装”还是“只装了 RetroArch”。
    const auto path = find_in_path(tool.executable);
    out << "- " << tool.label << " (" << tool.executable << "): ";
    if (path) {
      any_found = true;
      out << "found at " << *path << "\n";
    } else {
      out << "not found in PATH\n";
    }
  }

  if (!any_found) {
    out << "Install mGBA or RetroArch with the mGBA core before runtime testing.\n";
  }

  return any_found;
}

// 检查 RetroArch 的 mGBA core 是否位于常见系统路径。
// 目的：如果使用 RetroArch 路线，仅有 retroarch 命令还不够，还需要实际的 GBA core。
bool print_libretro_core_check(std::ostream& out) {
  print_section(out, "RetroArch mGBA core");

  // 覆盖 Debian/Ubuntu/Radxa Linux 上常见的 aarch64、armhf 和通用 libretro 安装路径。
  const std::vector<std::string> common_paths = {
      "/usr/lib/aarch64-linux-gnu/libretro/mgba_libretro.so",
      "/usr/lib/arm-linux-gnueabihf/libretro/mgba_libretro.so",
      "/usr/lib/libretro/mgba_libretro.so",
      "/usr/lib64/libretro/mgba_libretro.so",
      "/usr/local/lib/libretro/mgba_libretro.so",
  };

  const auto core_path = find_first_existing(common_paths);
  if (core_path) {
    out << "- mgba_libretro.so: found at " << *core_path << "\n";
    return true;
  }

  out << "- mgba_libretro.so: not found in common libretro paths\n";
  out << "  If RetroArch is used, record the actual mGBA core path in the test log.\n";
  return false;
}

// 检查测试 ROM 路径。
// 用法：用户在运行前设置 `RK3566_GBA_ROM=/path/to/test.gba`。
// 目的：避免把 ROM 文件路径写死进仓库，也避免误提交 ROM 资源。
bool print_rom_check(std::ostream& out) {
  print_section(out, "Test ROM");

  // 没有设置环境变量时只提示，不报错；gba-check 是准备检查，不负责强制启动测试。
  const char* rom_env = std::getenv("RK3566_GBA_ROM");
  if (rom_env == nullptr || std::string_view(rom_env).empty()) {
    out << "- RK3566_GBA_ROM: not set\n";
    out << "  Set it to the GBA test ROM path before launching the emulator.\n";
    return false;
  }

  // 设置了环境变量后，再确认文件是否真的存在。
  // 这样可以提前发现路径拼错、U 盘未挂载或 ROM 文件不在板子上的问题。
  const std::string rom_path = rom_env;
  out << "- RK3566_GBA_ROM: " << rom_path;
  if (file_exists(rom_path)) {
    out << " (found)\n";
    return true;
  }

  out << " (missing)\n";
  return false;
}

// 打印首轮 GBA 实测的操作顺序。
// 这些步骤和 docs/gba-validation.md 保持一致，方便在板端直接照着跑。
void print_next_steps(std::ostream& out) {
  print_section(out, "Next runtime steps");

  out << "1. Run './build/debug/rk3566-gba probe' and keep the HDMI/audio/input/thermal output.\n";
  out << "2. Launch mGBA or RetroArch with one known-good GBA game.\n";
  out << "3. Use integer scaling where possible: GBA 240x160 -> 720x480 on the 800x480 screen.\n";
  out << "4. Record FPS stability, audio sync, input feel, and temperatures at 0/15/30 minutes.\n";
  out << "5. Put the result in docs/gba-validation.md.\n";
}

}  // namespace

// `rk3566-gba gba-check` 的主执行函数。
// 顺序：
// 1. 检查模拟器前端。
// 2. 检查 RetroArch mGBA core。
// 3. 检查用户指定的测试 ROM。
// 4. 打印下一步 30 分钟稳定性测试流程。
int run_gba_validation_check(std::ostream& out) {
  out << "RK3566 GBA validation readiness check\n";
  out << "Purpose: prepare the first emulator stability run after the HDMI baseline.\n";

  print_tool_checks(out);
  print_libretro_core_check(out);
  print_rom_check(out);
  print_next_steps(out);

  return 0;
}
