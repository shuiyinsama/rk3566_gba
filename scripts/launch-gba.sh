#!/usr/bin/env bash
set -euo pipefail

# GBA 一键启动脚本。
# 目的：把手动输入的显示环境、分辨率切换和 mGBA 启动命令固定下来。
# 位置：这是用户层脚本，不是内核驱动、设备树或系统服务。
# 用法：
#   bash scripts/launch-gba.sh /home/radxa/roms/gba/game.gba
#   RK3566_GBA_ROM=/home/radxa/roms/gba/game.gba bash scripts/launch-gba.sh
#   bash scripts/launch-gba.sh --windowed /home/radxa/roms/gba/game.gba

MODE="800x480"
SCALE="3"
FULLSCREEN=1
BACKGROUND=0
KILL_EXISTING=1
ROM_PATH="${RK3566_GBA_ROM:-}"

usage() {
  cat <<'EOF'
Usage:
  launch-gba.sh [options] [rom.gba]

Options:
  --mode WxH       HDMI display mode, default: 800x480
  --scale N        mGBA viewport scale, default: 3
  --windowed       Start mGBA in a normal window instead of full-screen
  --background     Start mGBA in background and return to shell immediately
  --keep-existing  Do not kill existing mgba-qt processes before launch
  -h, --help       Show this help

Examples:
  bash scripts/launch-gba.sh /home/radxa/roms/gba/pokemon-green.gba
  RK3566_GBA_ROM=/home/radxa/roms/gba/pokemon-green.gba bash scripts/launch-gba.sh
  bash scripts/launch-gba.sh --windowed /home/radxa/roms/gba/pokemon-green.gba
EOF
}

# 解析命令行参数。
# 脚本既支持直接传 ROM 路径，也支持用 RK3566_GBA_ROM 环境变量传路径。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --scale)
      SCALE="${2:-}"
      shift 2
      ;;
    --windowed)
      FULLSCREEN=0
      shift
      ;;
    --background)
      BACKGROUND=1
      shift
      ;;
    --keep-existing)
      KILL_EXISTING=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      ROM_PATH="$1"
      shift
      ;;
  esac
done

# 检查 ROM 路径。
# 如果这里失败，说明脚本还没进入模拟器层，先修文件路径或拷贝 ROM。
if [[ -z "$ROM_PATH" ]]; then
  echo "Missing ROM path. Pass a ROM path or set RK3566_GBA_ROM." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$ROM_PATH" ]]; then
  echo "ROM not found: $ROM_PATH" >&2
  exit 1
fi

# 检查必要工具。
# xrandr 负责切 HDMI 分辨率，mgba-qt 负责实际运行游戏。
if ! command -v xrandr >/dev/null 2>&1; then
  echo "xrandr not found. Install x11-xserver-utils first." >&2
  exit 1
fi

if ! command -v mgba-qt >/dev/null 2>&1; then
  echo "mgba-qt not found. Install mgba-qt first." >&2
  exit 1
fi

# 自动寻找当前 X11 显示号。
# 自动登录后常见是 X0；有时重启或会话变化会变成 X1。
detect_display() {
  local socket
  for socket in /tmp/.X11-unix/X*; do
    [[ -S "$socket" ]] || continue
    echo ":${socket##*/X}"
    return 0
  done
  return 1
}

DISPLAY_VALUE="${DISPLAY:-}"
if [[ -z "$DISPLAY_VALUE" ]]; then
  DISPLAY_VALUE="$(detect_display || true)"
fi

if [[ -z "$DISPLAY_VALUE" ]]; then
  echo "No X11 display socket found under /tmp/.X11-unix." >&2
  exit 1
fi

# 自动寻找 Xauthority。
# GDM 自动登录时通常使用 /run/user/1000/gdm/Xauthority。
XAUTHORITY_VALUE="${XAUTHORITY:-}"
if [[ -z "$XAUTHORITY_VALUE" ]]; then
  if [[ -f "/run/user/$(id -u)/gdm/Xauthority" ]]; then
    XAUTHORITY_VALUE="/run/user/$(id -u)/gdm/Xauthority"
  elif [[ -f "$HOME/.Xauthority" ]]; then
    XAUTHORITY_VALUE="$HOME/.Xauthority"
  fi
fi

if [[ -z "$XAUTHORITY_VALUE" || ! -f "$XAUTHORITY_VALUE" ]]; then
  echo "Xauthority not found. Tried GDM and ~/.Xauthority." >&2
  exit 1
fi

export DISPLAY="$DISPLAY_VALUE"
export XAUTHORITY="$XAUTHORITY_VALUE"

# 找到当前 HDMI 输出名。
# 目前 Radxa CM3 IO Board 上通常是 HDMI-1，但脚本不写死，先从 xrandr 读取。
OUTPUT_NAME="$(xrandr --query | awk '/ connected/{print $1; exit}')"
if [[ -z "$OUTPUT_NAME" ]]; then
  echo "No connected display output found by xrandr." >&2
  exit 1
fi

echo "ROM: $ROM_PATH"
echo "DISPLAY: $DISPLAY"
echo "XAUTHORITY: $XAUTHORITY"
echo "Output: $OUTPUT_NAME"
echo "Mode: $MODE"

# 切换到掌机验证屏分辨率。
# 如果屏幕不支持该模式，xrandr 会失败并停止脚本。
xrandr --output "$OUTPUT_NAME" --mode "$MODE"

# 避免多次点击或多次运行后叠出多个 mGBA 窗口。
if [[ "$KILL_EXISTING" -eq 1 ]]; then
  pkill -x mgba-qt >/dev/null 2>&1 || true
fi

# 组装 mGBA 参数。
# GBA 原生 240x160，3x 后是 720x480，正好适合 800x480 横屏左右留黑边。
MGBA_ARGS=()
if [[ "$FULLSCREEN" -eq 1 ]]; then
  MGBA_ARGS+=("-f")
fi
MGBA_ARGS+=("--scale" "$SCALE")
MGBA_ARGS+=("$ROM_PATH")

echo "Launching: mgba-qt ${MGBA_ARGS[*]}"

if [[ "$BACKGROUND" -eq 1 ]]; then
  nohup mgba-qt "${MGBA_ARGS[@]}" >/tmp/rk3566-gba-mgba.log 2>&1 &
  echo "mGBA started in background. Log: /tmp/rk3566-gba-mgba.log"
else
  exec mgba-qt "${MGBA_ARGS[@]}"
fi
