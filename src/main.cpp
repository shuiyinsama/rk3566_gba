#include "platform_probe.h"

#include <iostream>
#include <string_view>

namespace {

void print_usage(std::ostream& out, std::string_view program_name) {
  out << "Usage: " << program_name << " [--help] [--version] [probe]\n"
      << "\n"
      << "rk3566-gba is the validation entry point for the RK3566 handheld project.\n"
      << "The first software milestone is GBA bring-up on Radxa CM3 with an HDMI\n"
      << "validation screen. Emulator integration will be added after the platform\n"
      << "baseline is confirmed.\n"
      << "\n"
      << "Planned validation order:\n"
      << "  1. System boot, HDMI output, audio, input, and thermal checks\n"
      << "  2. GBA emulator bring-up and 60 FPS stability\n"
      << "  3. PS1 and lightweight retro cores\n"
      << "  4. PSP exploratory testing\n"
      << "\n"
      << "Commands:\n"
      << "  probe    Print Linux display/audio/input/thermal baseline information\n";
}

}  // namespace

int main(int argc, char* argv[]) {
  const std::string_view program_name = argc > 0 ? argv[0] : "rk3566-gba";

  if (argc > 1) {
    const std::string_view arg = argv[1];
    if (arg == "--help" || arg == "-h") {
      print_usage(std::cout, program_name);
      return 0;
    }
    if (arg == "--version") {
      std::cout << "rk3566-gba 0.1.0\n";
      return 0;
    }
    if (arg == "probe") {
      return run_platform_probe(std::cout);
    }

    std::cerr << "Unknown argument: " << arg << "\n\n";
    print_usage(std::cerr, program_name);
    return 2;
  }

  print_usage(std::cout, program_name);
  return 0;
}
