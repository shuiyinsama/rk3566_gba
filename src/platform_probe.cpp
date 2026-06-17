#include "platform_probe.h"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace fs = std::filesystem;

namespace {

std::optional<std::string> read_first_line(const fs::path& path) {
  std::ifstream file(path);
  if (!file) {
    return std::nullopt;
  }

  std::string line;
  std::getline(file, line);
  return line;
}

std::vector<std::string> read_lines(const fs::path& path, std::size_t max_lines) {
  std::ifstream file(path);
  std::vector<std::string> lines;
  std::string line;

  while (lines.size() < max_lines && std::getline(file, line)) {
    if (!line.empty()) {
      lines.push_back(line);
    }
  }

  return lines;
}

std::vector<fs::path> list_directories(const fs::path& root) {
  std::error_code error;
  std::vector<fs::path> paths;

  if (!fs::exists(root, error)) {
    return paths;
  }

  for (const auto& entry : fs::directory_iterator(root, error)) {
    if (!error && entry.is_directory(error)) {
      paths.push_back(entry.path());
    }
  }

  std::sort(paths.begin(), paths.end());
  return paths;
}

std::string basename(const fs::path& path) {
  return path.filename().string();
}

void print_section(std::ostream& out, std::string_view title) {
  out << "\n== " << title << " ==\n";
}

void probe_drm(std::ostream& out) {
  print_section(out, "DRM display connectors");

  const auto connectors = list_directories("/sys/class/drm");
  bool printed = false;

  for (const auto& connector : connectors) {
    const auto status = read_first_line(connector / "status");
    if (!status) {
      continue;
    }

    printed = true;
    out << "- " << basename(connector) << ": " << *status << "\n";

    // Purpose: available modes tell us whether the HDMI screen exposes 800x480.
    const auto modes = read_lines(connector / "modes", 12);
    if (modes.empty()) {
      out << "  modes: unavailable\n";
      continue;
    }

    out << "  modes:";
    for (const auto& mode : modes) {
      out << ' ' << mode;
    }
    out << "\n";
  }

  if (!printed) {
    out << "No DRM connector status files found.\n";
  }
}

void probe_audio(std::ostream& out) {
  print_section(out, "Audio devices");

  const auto cards = read_lines("/proc/asound/cards", 16);
  if (cards.empty()) {
    out << "No ALSA card list found.\n";
    return;
  }

  for (const auto& line : cards) {
    out << line << "\n";
  }
}

void probe_input(std::ostream& out) {
  print_section(out, "Input devices");

  const auto inputs = list_directories("/sys/class/input");
  bool printed = false;

  for (const auto& input : inputs) {
    const auto name = read_first_line(input / "device" / "name");
    if (!name) {
      continue;
    }

    printed = true;
    out << "- " << basename(input) << ": " << *name << "\n";
  }

  if (!printed) {
    out << "No input device names found.\n";
  }
}

void probe_thermal(std::ostream& out) {
  print_section(out, "Thermal zones");

  const auto zones = list_directories("/sys/class/thermal");
  bool printed = false;

  for (const auto& zone : zones) {
    if (basename(zone).rfind("thermal_zone", 0) != 0) {
      continue;
    }

    const auto type = read_first_line(zone / "type").value_or("unknown");
    const auto temp = read_first_line(zone / "temp");

    printed = true;
    out << "- " << basename(zone) << " (" << type << ")";
    if (temp) {
      try {
        const double celsius = std::stod(*temp) / 1000.0;
        out << ": " << std::fixed << std::setprecision(1) << celsius << " C";
      } catch (const std::exception&) {
        out << ": raw temp " << *temp;
      }
    } else {
      out << ": temp unavailable";
    }
    out << "\n";
  }

  if (!printed) {
    out << "No thermal zones found.\n";
  }
}

}  // namespace

int run_platform_probe(std::ostream& out) {
  out << "RK3566 handheld platform probe\n";
  out << "Purpose: capture the HDMI/audio/input/thermal baseline before GBA testing.\n";

  probe_drm(out);
  probe_audio(out);
  probe_input(out);
  probe_thermal(out);

  return 0;
}
