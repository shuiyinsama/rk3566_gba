#include <fstream>
#include <iostream>
#include <string>
#include <string_view>

namespace {

constexpr std::string_view kVersion = "0.2.0";

constexpr std::string_view kRecordTemplate = R"(# Phase 1 Test Record

## Basic Info

| Item | Value |
| --- | --- |
| Date |  |
| Board | Radxa CM3 + CM3 IO Board |
| OS image |  |
| Kernel |  |
| Screen | 4.3 inch 800x480 HDMI |
| Input device |  |
| Audio device |  |
| Power supply |  |

## System Bring-up

| Check | Result | Notes |
| --- | --- | --- |
| Boot |  |  |
| HDMI output |  |  |
| Resolution |  |  |
| USB input detected |  |  |
| Audio device detected |  |  |
| Network |  |  |

## GBA

| Check | Result | Notes |
| --- | --- | --- |
| Emulator |  |  |
| 60 FPS |  |  |
| 3x integer scale |  |  |
| Audio sync |  |  |
| Input latency |  |  |
| Save/load |  |  |
| 30 min stability |  |  |
| Max temperature |  |  |

## Other Platforms

| Platform | Emulator/Core | Game | Result | Notes |
| --- | --- | --- | --- | --- |
| PS1 |  |  |  |  |
| FC/NES |  |  |  |  |
| MD/Genesis |  |  |  |  |
| SFC/SNES |  |  |  |  |
| PSP |  |  |  |  |
| N64 |  |  |  |  |
| Dreamcast |  |  |  |  |

## Thermal And Power

| Scenario | Temperature | Current | Power | Notes |
| --- | --- | --- | --- | --- |
| Idle |  |  |  |  |
| GBA 30 min |  |  |  |  |
| PS1 15 min |  |  |  |  |
| PSP 15 min |  |  |  |  |

## Decision

| Question | Decision |
| --- | --- |
| Is GBA validated? |  |
| Is PS1 validated? |  |
| Should PSP remain a target? |  |
| Is 4.3 inch screen suitable? |  |
| Input layout recommendation |  |
| Audio path recommendation |  |
| Thermal recommendation |  |
| Continue to next phase? |  |
)";

void print_usage(std::ostream& out, std::string_view program_name) {
  out << "Usage: " << program_name << " [command]\n"
      << "\n"
      << "Commands:\n"
      << "  --help, -h              Show this help message\n"
      << "  --version               Show version\n"
      << "  --checklist             Print phase 1 validation checklist\n"
      << "  --system-commands       Print Linux commands for board bring-up\n"
      << "  --new-record <path>     Create a Markdown test record\n"
      << "\n"
      << "Default command: --checklist\n";
}

void print_checklist(std::ostream& out) {
  out << "Phase 1 validation checklist\n"
      << "\n"
      << "1. Boot and OS baseline\n"
      << "   - Confirm OS image, kernel, storage, network, and USB devices.\n"
      << "2. HDMI display\n"
      << "   - Confirm 800x480 output, refresh rate, fullscreen behavior, and stability.\n"
      << "3. Input\n"
      << "   - Confirm GBA controls, hotkeys, menu, save/load, and exit flow.\n"
      << "4. Audio\n"
      << "   - Compare HDMI audio, USB audio, and board audio if available.\n"
      << "5. GBA\n"
      << "   - Validate 60 FPS, 3x integer scaling, audio sync, and 30 min stability.\n"
      << "6. PS1 and lightweight retro platforms\n"
      << "   - Validate stable playable range after GBA passes.\n"
      << "7. PSP/N64/Dreamcast boundary tests\n"
      << "   - Treat these as exploration targets, not phase 1 pass/fail gates.\n"
      << "8. Thermal and power\n"
      << "   - Record idle, GBA, PS1, and PSP temperature/power data.\n"
      << "9. Product direction\n"
      << "   - Decide screen size, input layout, audio path, and thermal direction.\n";
}

void print_system_commands(std::ostream& out) {
  out << "# System\n"
      << "uname -a\n"
      << "cat /etc/os-release\n"
      << "lscpu\n"
      << "free -h\n"
      << "lsblk\n"
      << "\n"
      << "# Display\n"
      << "ls /sys/class/drm\n"
      << "find /sys/class/drm -maxdepth 2 -type f -name modes -print -exec cat {} \\;\n"
      << "xrandr --verbose\n"
      << "\n"
      << "# USB and input\n"
      << "lsusb\n"
      << "cat /proc/bus/input/devices\n"
      << "\n"
      << "# Audio\n"
      << "aplay -l\n"
      << "pactl list short sinks\n"
      << "\n"
      << "# Thermal and frequency\n"
      << "cat /sys/class/thermal/thermal_zone*/temp\n"
      << "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq\n";
}

int create_record(std::string_view path) {
  std::ofstream file(std::string(path));
  if (!file) {
    std::cerr << "Failed to create record: " << path << "\n";
    return 1;
  }

  file << kRecordTemplate;
  if (!file) {
    std::cerr << "Failed to write record: " << path << "\n";
    return 1;
  }

  std::cout << "Created test record: " << path << "\n";
  return 0;
}

}  // namespace

int main(int argc, char* argv[]) {
  const std::string_view program_name = argc > 0 ? argv[0] : "rk3566-gba";

  if (argc == 1) {
    print_checklist(std::cout);
    return 0;
  }

  const std::string_view command = argv[1];

  if (command == "--help" || command == "-h") {
    print_usage(std::cout, program_name);
    return 0;
  }

  if (command == "--version") {
    std::cout << "rk3566-gba " << kVersion << "\n";
    return 0;
  }

  if (command == "--checklist") {
    print_checklist(std::cout);
    return 0;
  }

  if (command == "--system-commands") {
    print_system_commands(std::cout);
    return 0;
  }

  if (command == "--new-record") {
    if (argc < 3) {
      std::cerr << "--new-record requires an output path\n\n";
      print_usage(std::cerr, program_name);
      return 2;
    }
    return create_record(argv[2]);
  }

  std::cerr << "Unknown command: " << command << "\n\n";
  print_usage(std::cerr, program_name);
  return 2;
}
