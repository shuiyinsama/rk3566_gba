#!/usr/bin/env bash
set -euo pipefail

# GBA 一键掌机模式脚本。
# 目的：把“启动手柄映射 -> 切换 800x480 -> 启动 mGBA -> 状态/停止/重启”合成一个入口。
# 位置：这是用户层编排脚本，不是 systemd 服务；先用于手动验证，验证稳定后再接开机自启动。
# 用法：
#   bash ~/rk3566_gba/scripts/gba-handheld.sh start /home/radxa/roms/gba/pokemon-green.gba
#   bash ~/rk3566_gba/scripts/gba-handheld.sh status
#   bash ~/rk3566_gba/scripts/gba-handheld.sh stop
#   bash ~/rk3566_gba/scripts/gba-handheld.sh restart /home/radxa/roms/gba/pokemon-green.gba

COMMAND="${1:-}"
if [[ -z "$COMMAND" ]]; then
  COMMAND="status"
elif [[ "$COMMAND" == "--list-gamepads" ]]; then
  COMMAND="list-gamepads"
  shift
else
  shift
fi

ROM_PATH="${RK3566_GBA_ROM:-}"
GAMEPAD_EVENT="auto"
ENABLE_GAMEPAD=1
SHOW_EVENTS=0
SWAP_AB=0
GRAB=0
STOP_TIMEOUT=8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_SCRIPT="$SCRIPT_DIR/gba-session.sh"
BRIDGE_SCRIPT="$SCRIPT_DIR/gamepad-keyboard-bridge.py"
STATE_DIR="/tmp/rk3566-gba"
BRIDGE_PID_FILE="$STATE_DIR/gamepad-bridge.pid"
BRIDGE_LOG="$STATE_DIR/gamepad-bridge.log"

usage() {
  cat <<'EOF'
Usage:
  gba-handheld.sh <command> [options] [rom.gba]

Commands:
  status          Show mGBA and gamepad bridge status
  start           Start gamepad bridge if possible, then start mGBA
  stop            Stop mGBA and the gamepad bridge started by this script
  restart         Stop everything, then start again

Options:
  --event PATH       Gamepad evdev path, default: auto
  --no-gamepad       Do not start the gamepad-to-keyboard bridge
  --show-events      Print bridge conversion events into /tmp/rk3566-gba/gamepad-bridge.log
  --swap-ab          Swap BTN_SOUTH/BTN_EAST mapping for A/B feel
  --grab             Ask evdev to exclusively grab the physical gamepad
  --list-gamepads    List detected gamepad candidates and exit
  --timeout SEC      mGBA stop timeout, default: 8
  -h, --help         Show this help

Examples:
  bash ~/rk3566_gba/scripts/gba-handheld.sh start /home/radxa/roms/gba/pokemon-green.gba
  bash ~/rk3566_gba/scripts/gba-handheld.sh start --event /dev/input/event3 /home/radxa/roms/gba/pokemon-green.gba
  bash ~/rk3566_gba/scripts/gba-handheld.sh restart --swap-ab /home/radxa/roms/gba/pokemon-green.gba
  bash ~/rk3566_gba/scripts/gba-handheld.sh stop
EOF
}

# 解析命令行参数。
# ROM 可以作为最后一个普通参数传入，也可以使用 RK3566_GBA_ROM 环境变量。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)
      GAMEPAD_EVENT="${2:-}"
      shift 2
      ;;
    --no-gamepad)
      ENABLE_GAMEPAD=0
      shift
      ;;
    --show-events)
      SHOW_EVENTS=1
      shift
      ;;
    --swap-ab)
      SWAP_AB=1
      shift
      ;;
    --grab)
      GRAB=1
      shift
      ;;
    --list-gamepads)
      COMMAND="list-gamepads"
      shift
      ;;
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

mkdir -p "$STATE_DIR"

bridge_pid() {
  # 只信任本脚本写下的 PID 文件，并确认进程仍是手柄映射脚本。
  local pid

  [[ -f "$BRIDGE_PID_FILE" ]] || return 0
  pid="$(cat "$BRIDGE_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0

  if ps -p "$pid" -o cmd= 2>/dev/null | grep -q 'gamepad-keyboard-bridge.py'; then
    echo "$pid"
  fi
}

detect_gamepad_event() {
  # 优先使用 /dev/input/by-id/*event-joystick。
  # by-id 是 udev 生成的稳定别名；即使底层 event3 变成 event9，它也会指向新的 event。
  local by_id
  local resolved

  for by_id in /dev/input/by-id/*event-joystick; do
    [[ -e "$by_id" ]] || continue
    resolved="$(readlink -f "$by_id" 2>/dev/null || true)"
    if [[ -n "$resolved" && -e "$resolved" ]]; then
      echo "$resolved"
      return 0
    fi
  done

  # 如果系统没有 by-id，再从 /proc/bus/input/devices 自动寻找最像手柄的 eventX。
  # 目前 Xbox 手柄会被识别为 Microsoft Xbox Series S|X Controller。
  awk '
    BEGIN { RS = ""; FS = "\n" }
    {
      block = tolower($0)
    }
    block ~ /name=.*(controller|gamepad|joystick|xbox|8bitdo|dualshock|dualsense)/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^H: Handlers=/ && match($i, /event[0-9]+/)) {
          print "/dev/input/" substr($i, RSTART, RLENGTH)
          exit
        }
      }
    }
  ' /proc/bus/input/devices 2>/dev/null || true
}

list_gamepads() {
  # 打印自动识别会使用的候选设备，方便排查 event 编号变化。
  local detected
  local by_id
  local resolved

  detected="$(detect_gamepad_event)"
  echo "== auto selected =="
  if [[ -n "$detected" ]]; then
    echo "$detected"
  else
    echo "not found"
  fi

  echo
  echo "== /dev/input/by-id/*event-joystick =="
  for by_id in /dev/input/by-id/*event-joystick; do
    if [[ -e "$by_id" ]]; then
      resolved="$(readlink -f "$by_id" 2>/dev/null || true)"
      echo "$by_id -> $resolved"
    fi
  done

  echo
  echo "== controller-like entries from /proc/bus/input/devices =="
  awk '
    BEGIN { RS = ""; FS = "\n" }
    {
      block = tolower($0)
    }
    block ~ /name=.*(controller|gamepad|joystick|xbox|8bitdo|dualshock|dualsense)/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^N: / || $i ~ /^H: /) {
          print $i
        }
      }
      print ""
    }
  ' /proc/bus/input/devices 2>/dev/null || true
}

resolve_gamepad_event() {
  if [[ "$GAMEPAD_EVENT" == "auto" ]]; then
    detect_gamepad_event
  else
    echo "$GAMEPAD_EVENT"
  fi
}

start_bridge() {
  # 启动 evdev -> uinput 虚拟键盘桥。
  # 如果没有找到手柄，继续启动游戏；这样键盘验证或纯展示时不会被手柄阻塞。
  local pid
  local event_path
  local bridge_args=()

  if [[ "$ENABLE_GAMEPAD" -eq 0 ]]; then
    echo "Gamepad bridge disabled by --no-gamepad."
    return 0
  fi

  pid="$(bridge_pid || true)"
  if [[ -n "$pid" ]]; then
    echo "Gamepad bridge already running: $pid"
    return 0
  fi

  if [[ ! -f "$BRIDGE_SCRIPT" ]]; then
    echo "Gamepad bridge script not found: $BRIDGE_SCRIPT" >&2
    return 1
  fi

  event_path="$(resolve_gamepad_event)"
  if [[ -z "$event_path" ]]; then
    echo "No gamepad event device found; starting mGBA without gamepad bridge."
    return 0
  fi

  if [[ ! -e "$event_path" ]]; then
    echo "Gamepad event device does not exist: $event_path" >&2
    return 1
  fi

  bridge_args=(python3 "$BRIDGE_SCRIPT" --event "$event_path")
  if [[ "$SHOW_EVENTS" -eq 1 ]]; then
    bridge_args+=(--show-events)
  fi
  if [[ "$SWAP_AB" -eq 1 ]]; then
    bridge_args+=(--swap-ab)
  fi
  if [[ "$GRAB" -eq 1 ]]; then
    bridge_args+=(--grab)
  fi

  echo "Starting gamepad bridge for $event_path"
  echo "Bridge log: $BRIDGE_LOG"

  # /dev/uinput 需要 root 权限。交互终端里 sudo 会提示输入一次密码。
  if [[ "$(id -u)" -eq 0 ]]; then
    "${bridge_args[@]}" >"$BRIDGE_LOG" 2>&1 &
  else
    sudo -v
    sudo "${bridge_args[@]}" >"$BRIDGE_LOG" 2>&1 &
  fi
  echo "$!" >"$BRIDGE_PID_FILE"

  sleep 1
  pid="$(bridge_pid || true)"
  if [[ -z "$pid" ]]; then
    echo "Gamepad bridge failed to stay running. Recent log:" >&2
    tail -n 20 "$BRIDGE_LOG" >&2 || true
    return 1
  fi

  echo "Gamepad bridge started: $pid"
}

stop_bridge() {
  # 只停止本脚本启动的桥接进程。
  # 用户手动启动的其它输入工具不在这里清理，避免误杀。
  local pid

  pid="$(bridge_pid || true)"
  if [[ -z "$pid" ]]; then
    rm -f "$BRIDGE_PID_FILE"
    echo "Gamepad bridge is not running."
    return 0
  fi

  echo "Stopping gamepad bridge: $pid"
  if [[ "$(id -u)" -eq 0 ]]; then
    kill "$pid" 2>/dev/null || true
  else
    sudo kill "$pid" 2>/dev/null || true
  fi

  sleep 1
  if [[ -n "$(bridge_pid || true)" ]]; then
    echo "Gamepad bridge did not exit; sending SIGKILL."
    if [[ "$(id -u)" -eq 0 ]]; then
      kill -KILL "$pid" 2>/dev/null || true
    else
      sudo kill -KILL "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$BRIDGE_PID_FILE"
}

start_mgba() {
  # 交给 gba-session.sh 处理分辨率、X11 环境和 mGBA 后台启动。
  if [[ -z "$ROM_PATH" ]]; then
    echo "Missing ROM path. Pass a ROM path or set RK3566_GBA_ROM." >&2
    exit 2
  fi

  bash "$SESSION_SCRIPT" start "$ROM_PATH"
}

stop_mgba() {
  bash "$SESSION_SCRIPT" stop --timeout "$STOP_TIMEOUT"
}

show_status() {
  local pid

  echo "== handheld session =="
  echo "state dir: $STATE_DIR"
  echo

  echo "== gamepad bridge =="
  echo "auto event: $(detect_gamepad_event || true)"
  pid="$(bridge_pid || true)"
  if [[ -n "$pid" ]]; then
    ps -p "$pid" -o pid=,stat=,etime=,cmd=
    echo "log: $BRIDGE_LOG"
    tail -n 8 "$BRIDGE_LOG" 2>/dev/null || true
  else
    echo "not running"
  fi

  echo
  bash "$SESSION_SCRIPT" status
}

case "$COMMAND" in
  status)
    show_status
    ;;
  list-gamepads)
    list_gamepads
    ;;
  start)
    start_bridge
    start_mgba
    ;;
  stop)
    stop_mgba
    stop_bridge
    show_status
    ;;
  restart)
    stop_mgba
    stop_bridge
    start_bridge
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
