#!/usr/bin/env bash
set -euo pipefail

# GBA 音频验证脚本。
# 目的：把板端音频设备枚举、桌面音频服务状态、ALSA 播放测试这些步骤固定下来。
# 位置：这是用户层验证脚本，不修改内核、设备树或系统服务；默认只读取状态。
# 用法：
#   bash ~/rk3566_gba/scripts/audio-check.sh
#   bash ~/rk3566_gba/scripts/audio-check.sh --play
#   bash ~/rk3566_gba/scripts/audio-check.sh --play --device default
#   bash ~/rk3566_gba/scripts/audio-check.sh --play --device plughw:0,0 --duration 8

PLAY=0
DURATION=6
DEVICE="default"
FREQ=440

usage() {
  cat <<'EOF'
Usage:
  audio-check.sh [options]

Options:
  --play             Play a short stereo test tone after printing audio status
  --device DEVICE    ALSA playback device, default: default
                    Examples: default, plughw:0,0, plughw:1,0
  --duration SEC     Test tone duration in seconds, default: 6
  --freq HZ          Sine tone frequency, default: 440
  -h, --help         Show this help

Examples:
  bash ~/rk3566_gba/scripts/audio-check.sh
  bash ~/rk3566_gba/scripts/audio-check.sh --play
  bash ~/rk3566_gba/scripts/audio-check.sh --play --device plughw:0,0
EOF
}

# 解析命令行参数。
# 默认只打印状态，只有明确传 --play 时才会发声，避免 SSH 误触时突然出声。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --play)
      PLAY=1
      shift
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --duration)
      DURATION="${2:-}"
      shift 2
      ;;
    --freq)
      FREQ="${2:-}"
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

# 检查数值参数，避免 timeout/speaker-test 收到异常参数。
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [[ "$DURATION" -lt 1 ]]; then
  echo "--duration must be a positive integer." >&2
  exit 2
fi

if ! [[ "$FREQ" =~ ^[0-9]+$ ]] || [[ "$FREQ" -lt 20 ]]; then
  echo "--freq must be an integer >= 20." >&2
  exit 2
fi

print_section() {
  printf '\n== %s ==\n' "$1"
}

run_optional() {
  # 运行可能不存在或可能失败的音频查询命令。
  # 失败时不停止脚本，因为不同桌面镜像可能使用 ALSA、PulseAudio 或 PipeWire 的不同组合。
  local title="$1"
  shift

  print_section "$title"
  if "$@"; then
    return 0
  fi
  printf 'unavailable or failed:'
  printf ' %q' "$@"
  printf '\n'
}

print_audio_status() {
  # 读取 ALSA 层声卡。
  # 这里能看到 HDMI 音频、板载音频是否被内核识别。
  print_section "/proc/asound/cards"
  if [[ -r /proc/asound/cards ]]; then
    cat /proc/asound/cards
  else
    echo "/proc/asound/cards not found"
  fi

  # 读取 ALSA 硬件播放设备。
  # 后续 --device plughw:X,Y 的 X/Y 就从这里来。
  run_optional "aplay -l" aplay -l

  # 读取 ALSA 逻辑设备。
  # default、hdmi、plughw 等名字会出现在这里。
  run_optional "aplay -L short list" bash -lc "aplay -L 2>/dev/null | sed -n '1,80p'"

  # 读取混音控制。
  # 如果有 Master、PCM、Speaker、Headphone、HDMI 之类的控制项，后面可以用 alsamixer/amixer 调音量。
  run_optional "amixer controls" bash -lc "amixer scontrols 2>/dev/null || true"

  # 桌面音频服务状态。
  # KDE 桌面常见是 PipeWire + WirePlumber，也可能兼容 pactl 命令。
  run_optional "pactl info" pactl info
  run_optional "pactl sinks" pactl list short sinks
  run_optional "wpctl status" wpctl status

  # 当前相关进程。
  print_section "audio processes"
  ps -ef | grep -E '[p]ipewire|[w]ireplumber|[p]ulse' || true
}

play_test_tone() {
  # 优先使用 speaker-test，因为它能直接走 ALSA 并做左右声道验证。
  # 这一步用于回答“板子到屏幕/喇叭有没有声音”，不专门验证 mGBA。
  print_section "playback test"
  echo "Device: $DEVICE"
  echo "Duration: ${DURATION}s"
  echo "Frequency: ${FREQ}Hz"
  echo "如果听到左右声道测试音，请记录为音频链路可用。"

  if command -v speaker-test >/dev/null 2>&1; then
    timeout "${DURATION}s" speaker-test -D "$DEVICE" -t sine -f "$FREQ" -c 2 || true
    return 0
  fi

  # 如果系统没有 speaker-test，退回到 Python 生成 wav，再用 aplay 播放。
  # Python 只用来生成临时测试音，脚本流程仍由 shell 控制。
  if command -v python3 >/dev/null 2>&1 && command -v aplay >/dev/null 2>&1; then
    local wav
    wav="$(mktemp /tmp/rk3566-gba-audio-test.XXXXXX.wav)"
    python3 - "$wav" "$DURATION" "$FREQ" <<'PY'
import math
import struct
import sys
import wave

path = sys.argv[1]
duration = int(sys.argv[2])
freq = int(sys.argv[3])
rate = 48000
amp = 0.25

with wave.open(path, "wb") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    for index in range(duration * rate):
        sample = int(math.sin(2 * math.pi * freq * index / rate) * amp * 32767)
        # 前半段左声道，后半段右声道，便于听左右输出是否正常。
        if index < duration * rate // 2:
            frame = struct.pack("<hh", sample, 0)
        else:
            frame = struct.pack("<hh", 0, sample)
        wav.writeframesraw(frame)
PY
    aplay -D "$DEVICE" "$wav" || true
    rm -f "$wav"
    return 0
  fi

  echo "speaker-test/aplay/python3 not available. Install alsa-utils first:" >&2
  echo "  sudo apt install -y alsa-utils" >&2
  return 1
}

print_audio_status

if [[ "$PLAY" -eq 1 ]]; then
  play_test_tone
else
  print_section "next step"
  echo "只完成了音频状态检查。要播放测试音，请运行："
  echo "  bash ~/rk3566_gba/scripts/audio-check.sh --play"
fi
