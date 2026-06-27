#!/usr/bin/env bash
set -euo pipefail

# GBA 运行会话管理脚本。
# 目的：验证 mGBA 是否能稳定查看状态、退出、再次启动和重启。
# 位置：这是用户层脚本，不修改系统服务；它只是调用 launch-gba.sh 并管理 mgba-qt 进程。
# 用法：
#   bash ~/rk3566_gba/scripts/gba-session.sh status
#   bash ~/rk3566_gba/scripts/gba-session.sh stop
#   bash ~/rk3566_gba/scripts/gba-session.sh start /home/radxa/roms/gba/pokemon-green.gba
#   bash ~/rk3566_gba/scripts/gba-session.sh restart /home/radxa/roms/gba/pokemon-green.gba

PROCESS_NAME="mgba-qt"
STOP_TIMEOUT=8
ROM_PATH="${RK3566_GBA_ROM:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCH_SCRIPT="$SCRIPT_DIR/launch-gba.sh"

usage() {
  cat <<'EOF'
Usage:
  gba-session.sh <command> [options] [rom.gba]

Commands:
  status          Show mGBA process and display status
  start           Start mGBA in background through launch-gba.sh
  stop            Ask mGBA to exit, then force-kill only if it does not quit
  restart         Stop existing mGBA, then start again

Options:
  --timeout SEC   Seconds to wait after SIGTERM before SIGKILL, default: 8
  -h, --help      Show this help

Examples:
  bash ~/rk3566_gba/scripts/gba-session.sh status
  bash ~/rk3566_gba/scripts/gba-session.sh stop
  bash ~/rk3566_gba/scripts/gba-session.sh start /home/radxa/roms/gba/pokemon-green.gba
  bash ~/rk3566_gba/scripts/gba-session.sh restart /home/radxa/roms/gba/pokemon-green.gba
EOF
}

COMMAND="${1:-}"
if [[ -z "$COMMAND" ]]; then
  usage >&2
  exit 2
fi
shift

# 解析命令行参数。
# start/restart 可以直接传 ROM 路径，也可以提前设置 RK3566_GBA_ROM。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      STOP_TIMEOUT="${2:-}"
      shift 2
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

if ! [[ "$STOP_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$STOP_TIMEOUT" -lt 1 ]]; then
  echo "--timeout must be a positive integer." >&2
  exit 2
fi

find_display() {
  # 自动寻找 X11 显示号，用于 status 时读取 xrandr。
  # 如果没有图形桌面，status 仍然会继续显示进程状态。
  local socket
  for socket in /tmp/.X11-unix/X*; do
    [[ -S "$socket" ]] || continue
    echo ":${socket##*/X}"
    return 0
  done
  return 1
}

find_xauthority() {
  # GDM 自动登录时通常使用 /run/user/1000/gdm/Xauthority。
  # 找不到时退回 ~/.Xauthority；两者都没有则不导出。
  if [[ -n "${XAUTHORITY:-}" && -f "${XAUTHORITY:-}" ]]; then
    echo "$XAUTHORITY"
    return 0
  fi

  if [[ -f "/run/user/$(id -u)/gdm/Xauthority" ]]; then
    echo "/run/user/$(id -u)/gdm/Xauthority"
    return 0
  fi

  if [[ -f "$HOME/.Xauthority" ]]; then
    echo "$HOME/.Xauthority"
    return 0
  fi

  return 1
}

prepare_display_env() {
  # 为 xrandr 和可能的图形程序补齐 DISPLAY/XAUTHORITY。
  # launch-gba.sh 内部也会做一次检测，这里主要服务 status 命令。
  local display_value
  local xauthority_value

  display_value="${DISPLAY:-}"
  if [[ -z "$display_value" ]]; then
    display_value="$(find_display || true)"
  fi

  if [[ -n "$display_value" ]]; then
    export DISPLAY="$display_value"
  fi

  xauthority_value="$(find_xauthority || true)"
  if [[ -n "$xauthority_value" ]]; then
    export XAUTHORITY="$xauthority_value"
  fi
}

mgba_pids() {
  pgrep -x "$PROCESS_NAME" || true
}

show_status() {
  # 显示 mGBA 进程、当前 HDMI 模式和最近一次 mGBA 日志。
  # 这一步用于判断 stop/restart 后是否有残留进程或分辨率异常。
  local pids
  local pid

  prepare_display_env

  echo "== mGBA process =="
  pids="$(mgba_pids)"
  if [[ -z "$pids" ]]; then
    echo "not running"
  else
    for pid in $pids; do
      ps -p "$pid" -o pid=,stat=,etime=,pcpu=,pmem=,cmd=
    done
  fi

  echo
  echo "== display =="
  if [[ -n "${DISPLAY:-}" && -n "${XAUTHORITY:-}" ]] && command -v xrandr >/dev/null 2>&1; then
    xrandr --current 2>/dev/null | sed -n '1,8p' || true
  else
    echo "xrandr unavailable or DISPLAY/XAUTHORITY missing"
  fi

  echo
  echo "== recent mGBA log =="
  if [[ -f /tmp/rk3566-gba-mgba.log ]]; then
    tail -n 12 /tmp/rk3566-gba-mgba.log
  else
    echo "/tmp/rk3566-gba-mgba.log not found"
  fi
}

stop_mgba() {
  # 先发 SIGTERM，让 Qt/mGBA 有机会正常退出。
  # 如果超过 timeout 仍未退出，再用 SIGKILL，避免验证流程卡住。
  local pids
  local waited

  pids="$(mgba_pids)"
  if [[ -z "$pids" ]]; then
    echo "mGBA is not running."
    return 0
  fi

  echo "Sending SIGTERM to $PROCESS_NAME: $pids"
  pkill -TERM -x "$PROCESS_NAME" || true

  waited=0
  while [[ "$waited" -lt "$STOP_TIMEOUT" ]]; do
    sleep 1
    if [[ -z "$(mgba_pids)" ]]; then
      echo "mGBA exited cleanly after ${waited}s."
      return 0
    fi
    waited=$((waited + 1))
  done

  echo "mGBA did not exit within ${STOP_TIMEOUT}s; sending SIGKILL."
  pkill -KILL -x "$PROCESS_NAME" || true
  sleep 1

  if [[ -n "$(mgba_pids)" ]]; then
    echo "mGBA is still running after SIGKILL." >&2
    return 1
  fi

  echo "mGBA was force-killed."
}

start_mgba() {
  # 通过 launch-gba.sh 启动，保证 DISPLAY、XAUTHORITY、800x480 和 3x 缩放逻辑保持一致。
  if [[ -z "$ROM_PATH" ]]; then
    echo "Missing ROM path. Pass a ROM path or set RK3566_GBA_ROM." >&2
    exit 2
  fi

  if [[ ! -x "$LAUNCH_SCRIPT" && ! -f "$LAUNCH_SCRIPT" ]]; then
    echo "launch script not found: $LAUNCH_SCRIPT" >&2
    exit 1
  fi

  bash "$LAUNCH_SCRIPT" --background "$ROM_PATH"
  sleep 2
  show_status
}

case "$COMMAND" in
  status)
    show_status
    ;;
  start)
    start_mgba
    ;;
  stop)
    stop_mgba
    show_status
    ;;
  restart)
    stop_mgba
    start_mgba
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage >&2
    exit 2
    ;;
esac
