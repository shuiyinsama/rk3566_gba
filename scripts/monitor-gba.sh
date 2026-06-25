#!/usr/bin/env bash
set -euo pipefail

# GBA 稳定性监控脚本。
# 目的：在 Radxa 板子上连续记录模拟器运行期间的温度、CPU、内存、显示和 mGBA 进程状态。
# 位置：这是用户层采样脚本，不改内核、不改驱动、不改系统服务；它只读取系统状态并写日志。
# 用法：
#   bash ~/rk3566_gba/scripts/monitor-gba.sh
#   bash ~/rk3566_gba/scripts/monitor-gba.sh --duration 1800 --interval 10
#   bash ~/rk3566_gba/scripts/monitor-gba.sh --tag pokemon-emerald-30min

INTERVAL=10
DURATION=1800
PROCESS_NAME="mgba-qt"
OUTPUT_DIR="$HOME/rk3566_gba/logs"
TAG="gba-stability"
DISPLAY_VALUE="${DISPLAY:-}"
XAUTHORITY_VALUE="${XAUTHORITY:-}"

usage() {
  cat <<'EOF'
Usage:
  monitor-gba.sh [options]

Options:
  --interval SEC      Sampling interval in seconds, default: 10
  --duration SEC      Total sampling duration in seconds, default: 1800
                      Use 0 for continuous monitoring until Ctrl+C.
  --process NAME      Process name to monitor, default: mgba-qt
  --output-dir DIR    Directory for board-side logs, default: ~/rk3566_gba/logs
  --tag NAME          Log file name tag, default: gba-stability
  --display :N        X11 display, optional; auto-detected when omitted
  --xauthority PATH   Xauthority file, optional; auto-detected when omitted
  -h, --help          Show this help

Examples:
  bash ~/rk3566_gba/scripts/monitor-gba.sh --duration 1800 --interval 10
  bash ~/rk3566_gba/scripts/monitor-gba.sh --tag pokemon-emerald-30min
EOF
}

# 解析命令行参数。
# 这些参数只影响采样频率、时长和日志位置，不会主动启动或停止模拟器。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      INTERVAL="${2:-}"
      shift 2
      ;;
    --duration)
      DURATION="${2:-}"
      shift 2
      ;;
    --process)
      PROCESS_NAME="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --display)
      DISPLAY_VALUE="${2:-}"
      shift 2
      ;;
    --xauthority)
      XAUTHORITY_VALUE="${2:-}"
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
      echo "Unexpected argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# 检查数字参数，避免 sleep 或循环判断收到空值、负数、文本后行为不可预期。
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -lt 1 ]]; then
  echo "--interval must be a positive integer." >&2
  exit 2
fi

if ! [[ "$DURATION" =~ ^[0-9]+$ ]]; then
  echo "--duration must be a non-negative integer." >&2
  exit 2
fi

# 自动寻找当前 X11 显示号。
# xrandr 和可选的窗口标题读取需要 DISPLAY；如果没有图形桌面，也不影响温度/CPU/内存采样。
detect_display() {
  local socket
  for socket in /tmp/.X11-unix/X*; do
    [[ -S "$socket" ]] || continue
    echo ":${socket##*/X}"
    return 0
  done
  return 1
}

if [[ -z "$DISPLAY_VALUE" ]]; then
  DISPLAY_VALUE="$(detect_display || true)"
fi

# 自动寻找 Xauthority。
# GDM 自动登录常见位置是 /run/user/1000/gdm/Xauthority，找不到时再退回 ~/.Xauthority。
if [[ -z "$XAUTHORITY_VALUE" ]]; then
  if [[ -f "/run/user/$(id -u)/gdm/Xauthority" ]]; then
    XAUTHORITY_VALUE="/run/user/$(id -u)/gdm/Xauthority"
  elif [[ -f "$HOME/.Xauthority" ]]; then
    XAUTHORITY_VALUE="$HOME/.Xauthority"
  fi
fi

if [[ -n "$DISPLAY_VALUE" ]]; then
  export DISPLAY="$DISPLAY_VALUE"
fi

if [[ -n "$XAUTHORITY_VALUE" ]]; then
  export XAUTHORITY="$XAUTHORITY_VALUE"
fi

mkdir -p "$OUTPUT_DIR"

START_STAMP="$(date +%Y%m%d-%H%M%S)"
LOG_BASE="$OUTPUT_DIR/${TAG}-${START_STAMP}"
TEXT_LOG="${LOG_BASE}.log"
CSV_LOG="${LOG_BASE}.csv"

say() {
  printf '%s\n' "$*" | tee -a "$TEXT_LOG"
}

# CSV 字段可能包含空格、冒号或窗口标题，因此统一加双引号并转义双引号。
csv_field() {
  local value="$1"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

# 从 /proc/stat 读取整机 CPU 累计时间。
# 后续两次采样做差，得到采样间隔内的 CPU 忙碌百分比。
read_cpu_times() {
  awk '/^cpu / {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) {
      total += $i
    }
    print idle, total
  }' /proc/stat
}

calc_cpu_percent() {
  local prev_idle="$1"
  local prev_total="$2"
  local idle="$3"
  local total="$4"

  awk \
    -v prev_idle="$prev_idle" \
    -v prev_total="$prev_total" \
    -v idle="$idle" \
    -v total="$total" \
    'BEGIN {
      total_delta = total - prev_total
      idle_delta = idle - prev_idle
      if (total_delta <= 0) {
        printf "NA"
      } else {
        printf "%.1f", (total_delta - idle_delta) * 100 / total_delta
      }
    }'
}

# 读取所有 thermal_zone 的温度，并取最高值。
# 最高值更适合做稳定性判断，因为任何热点过高都可能导致降频或卡顿。
read_temperature_c() {
  local max_raw=""
  local raw=""
  local zone

  for zone in /sys/class/thermal/thermal_zone*/temp; do
    [[ -r "$zone" ]] || continue
    raw="$(cat "$zone" 2>/dev/null || true)"
    [[ "$raw" =~ ^-?[0-9]+$ ]] || continue
    if [[ -z "$max_raw" || "$raw" -gt "$max_raw" ]]; then
      max_raw="$raw"
    fi
  done

  if [[ -z "$max_raw" ]]; then
    printf 'NA'
  else
    awk -v temp="$max_raw" 'BEGIN { printf "%.1f", temp / 1000 }'
  fi
}

# 读取内存占用。
# 使用 MemAvailable 比 free memory 更接近 Linux 实际还能分配的内存。
read_memory_mb() {
  awk '
    /MemTotal:/ { total = int($2 / 1024) }
    /MemAvailable:/ { available = int($2 / 1024) }
    END {
      if (total > 0) {
        print total - available, total
      } else {
        print "NA", "NA"
      }
    }
  ' /proc/meminfo
}

# 读取 CPU 当前频率。
# 多核频率可能不同，这里取当前最高频率，便于观察是否出现明显降频。
read_cpu_freq_mhz() {
  local max_khz=""
  local raw=""
  local file

  for file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
    [[ -r "$file" ]] || continue
    raw="$(cat "$file" 2>/dev/null || true)"
    [[ "$raw" =~ ^[0-9]+$ ]] || continue
    if [[ -z "$max_khz" || "$raw" -gt "$max_khz" ]]; then
      max_khz="$raw"
    fi
  done

  if [[ -z "$max_khz" ]]; then
    printf 'NA'
  else
    awk -v freq="$max_khz" 'BEGIN { printf "%.0f", freq / 1000 }'
  fi
}

# 读取 mGBA 进程状态。
# 如果 process_found 为 0，说明模拟器已经退出或没有启动，是稳定性记录里的关键失败信号。
read_process_info() {
  local pid=""
  local ps_output=""
  local pcpu=""
  local pmem=""
  local rss=""
  local stat=""
  local etime=""

  pid="$(pgrep -x "$PROCESS_NAME" | head -n 1 || true)"
  if [[ -z "$pid" ]]; then
    printf '0,,,,,,\n'
    return 0
  fi

  ps_output="$(ps -p "$pid" -o pcpu= -o pmem= -o rss= -o stat= -o etime= 2>/dev/null | awk '{$1=$1; print}' || true)"
  if [[ -z "$ps_output" ]]; then
    printf '0,,,,,,\n'
    return 0
  fi

  read -r pcpu pmem rss stat etime <<<"$ps_output"
  printf '1,%s,%s,%s,%s,%s,%s\n' "$pid" "$pcpu" "$pmem" "$rss" "$stat" "$etime"
}

# 读取当前显示模式。
# 这能确认 HDMI 是否保持在 800x480，避免桌面恢复到 1920x1080 后误判模拟器画面很小。
read_display_mode() {
  if [[ -z "${DISPLAY:-}" ]] || ! command -v xrandr >/dev/null 2>&1; then
    printf 'NA'
    return 0
  fi

  xrandr --current 2>/dev/null | awk '
    / connected/ { output = $1 }
    /\*/ {
      if (output != "") {
        print output ":" $1
        found = 1
        exit
      }
    }
    END {
      if (!found) {
        print "NA"
      }
    }
  '
}

# 可选读取窗口标题。
# 如果板端装了 xdotool 或 wmctrl，标题里可能出现 mGBA 当前 FPS；没装也没关系，字段留空。
read_window_title() {
  if [[ -z "${DISPLAY:-}" ]]; then
    return 0
  fi

  if command -v xdotool >/dev/null 2>&1; then
    xdotool search --onlyvisible --name 'mGBA' getwindowname %@ 2>/dev/null | head -n 1 || true
    return 0
  fi

  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -l 2>/dev/null | awk '/mGBA/ { $1=""; $2=""; $3=""; sub(/^ +/, ""); print; exit }' || true
    return 0
  fi

  return 0
}

# 先写 CSV 表头，后续可直接用 Excel、Python、LibreOffice 打开分析。
{
  printf 'timestamp_iso,elapsed_s,temp_c,cpu_usage_pct,cpu_freq_mhz,mem_used_mb,mem_total_mb,load1,load5,load15,process_found,process_pid,process_cpu_pct,process_mem_pct,process_rss_kb,process_state,process_elapsed,display_mode,window_title\n'
} >"$CSV_LOG"

say "GBA 稳定性监控开始"
say "采样间隔: ${INTERVAL}s"
if [[ "$DURATION" -eq 0 ]]; then
  say "计划时长: 持续运行，按 Ctrl+C 停止"
else
  say "计划时长: ${DURATION}s"
fi
say "监控进程: ${PROCESS_NAME}"
say "DISPLAY: ${DISPLAY:-NA}"
say "XAUTHORITY: ${XAUTHORITY:-NA}"
say "板端文本日志: ${TEXT_LOG}"
say "板端 CSV 日志: ${CSV_LOG}"

# 记录一次静态环境快照，方便事后知道这份数据是在什么系统、什么屏幕状态下采的。
{
  echo
  echo "== system =="
  date -Is
  uname -a
  if [[ -r /etc/os-release ]]; then
    sed -n '1,8p' /etc/os-release
  fi
  echo
  echo "== display =="
  if [[ -n "${DISPLAY:-}" ]] && command -v xrandr >/dev/null 2>&1; then
    xrandr --current 2>/dev/null | sed -n '1,20p' || true
  else
    echo "xrandr unavailable or DISPLAY missing"
  fi
  echo
  echo "== audio cards =="
  if [[ -r /proc/asound/cards ]]; then
    cat /proc/asound/cards
  else
    echo "/proc/asound/cards unavailable"
  fi
} >>"$TEXT_LOG" 2>&1

START_EPOCH="$(date +%s)"
read -r PREV_IDLE PREV_TOTAL < <(read_cpu_times)

while true; do
  NOW_EPOCH="$(date +%s)"
  ELAPSED=$((NOW_EPOCH - START_EPOCH))
  if [[ "$DURATION" -gt 0 && "$ELAPSED" -gt "$DURATION" ]]; then
    break
  fi

  TIMESTAMP_ISO="$(date -Is)"
  TEMP_C="$(read_temperature_c)"
  read -r IDLE TOTAL < <(read_cpu_times)
  CPU_USAGE="$(calc_cpu_percent "$PREV_IDLE" "$PREV_TOTAL" "$IDLE" "$TOTAL")"
  PREV_IDLE="$IDLE"
  PREV_TOTAL="$TOTAL"
  CPU_FREQ="$(read_cpu_freq_mhz)"
  read -r MEM_USED MEM_TOTAL < <(read_memory_mb)
  read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

  IFS=',' read -r PROCESS_FOUND PROCESS_PID PROCESS_CPU PROCESS_MEM PROCESS_RSS PROCESS_STATE PROCESS_ELAPSED < <(read_process_info)
  DISPLAY_MODE="$(read_display_mode)"
  WINDOW_TITLE="$(read_window_title | tr '\r\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"

  {
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,' \
      "$TIMESTAMP_ISO" "$ELAPSED" "$TEMP_C" "$CPU_USAGE" "$CPU_FREQ" \
      "$MEM_USED" "$MEM_TOTAL" "$LOAD1" "$LOAD5" "$LOAD15" \
      "$PROCESS_FOUND" "$PROCESS_PID" "$PROCESS_CPU" "$PROCESS_MEM" \
      "$PROCESS_RSS" "$PROCESS_STATE" "$PROCESS_ELAPSED"
    csv_field "$DISPLAY_MODE"
    printf ','
    csv_field "$WINDOW_TITLE"
    printf '\n'
  } >>"$CSV_LOG"

  if [[ "$PROCESS_FOUND" == "1" ]]; then
    say "[$(date +%H:%M:%S)] elapsed=${ELAPSED}s temp=${TEMP_C}C cpu=${CPU_USAGE}% freq=${CPU_FREQ}MHz mem=${MEM_USED}/${MEM_TOTAL}MB load=${LOAD1} mgba_pid=${PROCESS_PID} mgba_cpu=${PROCESS_CPU}% mgba_mem=${PROCESS_MEM}% display=${DISPLAY_MODE} title=${WINDOW_TITLE:-NA}"
  else
    say "[$(date +%H:%M:%S)] elapsed=${ELAPSED}s temp=${TEMP_C}C cpu=${CPU_USAGE}% freq=${CPU_FREQ}MHz mem=${MEM_USED}/${MEM_TOTAL}MB load=${LOAD1} mgba=not-running display=${DISPLAY_MODE}"
  fi

  sleep "$INTERVAL"
done

say "GBA 稳定性监控结束"
say "板端文本日志: ${TEXT_LOG}"
say "板端 CSV 日志: ${CSV_LOG}"
