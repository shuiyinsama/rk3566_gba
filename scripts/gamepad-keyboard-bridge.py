#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 evdev 手柄事件转换成 mGBA 默认键盘按键。

这个脚本运行在 Radxa 板子上，作用是临时绕过缺失的 joydev 层。
它读取 /dev/input/eventX 里的手柄事件，再通过 /dev/uinput 创建一个虚拟键盘。
mGBA 收不到手柄时，可以先让 mGBA 继续使用默认键盘键位，然后由本脚本负责翻译手柄按键。
"""

from __future__ import annotations

import argparse
import fcntl
import os
import re
import select
import signal
import struct
import sys
import time
from dataclasses import dataclass
from pathlib import Path


# Linux input_event 结构在 arm64 上是：
# struct timeval { long tv_sec; long tv_usec; } + type/code/value。
# 读取 eventX 和写入 uinput 都使用同一个结构。
INPUT_EVENT_FORMAT = "llHHi"
INPUT_EVENT_SIZE = struct.calcsize(INPUT_EVENT_FORMAT)

# 常用事件类型。
EV_SYN = 0x00
EV_KEY = 0x01
EV_ABS = 0x03
SYN_REPORT = 0

# 手柄按键码。名称来自 Linux input-event-codes.h。
BTN_SOUTH = 0x130
BTN_EAST = 0x131
BTN_NORTH = 0x133
BTN_WEST = 0x134
BTN_TL = 0x136
BTN_TR = 0x137
BTN_TL2 = 0x138
BTN_TR2 = 0x139
BTN_SELECT = 0x13A
BTN_START = 0x13B
BTN_MODE = 0x13C
BTN_THUMBL = 0x13D
BTN_THUMBR = 0x13E

# 方向键和摇杆轴。
ABS_X = 0x00
ABS_Y = 0x01
ABS_HAT0X = 0x10
ABS_HAT0Y = 0x11

# mGBA 常见默认键位。
# GBA A -> X，GBA B -> Z，L/R -> A/S，Start -> Enter，Select -> Backspace。
KEY_ESC = 1
KEY_BACKSPACE = 14
KEY_ENTER = 28
KEY_A = 30
KEY_S = 31
KEY_Z = 44
KEY_X = 45
KEY_UP = 103
KEY_LEFT = 105
KEY_RIGHT = 106
KEY_DOWN = 108

BUS_USB = 0x03
UINPUT_DEVICE_NAME = "rk3566-gba-virtual-keyboard"


KEY_NAMES = {
    KEY_ESC: "KEY_ESC",
    KEY_BACKSPACE: "KEY_BACKSPACE",
    KEY_ENTER: "KEY_ENTER",
    KEY_A: "KEY_A",
    KEY_S: "KEY_S",
    KEY_Z: "KEY_Z",
    KEY_X: "KEY_X",
    KEY_UP: "KEY_UP",
    KEY_LEFT: "KEY_LEFT",
    KEY_RIGHT: "KEY_RIGHT",
    KEY_DOWN: "KEY_DOWN",
}

CODE_NAMES = {
    BTN_SOUTH: "BTN_SOUTH",
    BTN_EAST: "BTN_EAST",
    BTN_NORTH: "BTN_NORTH",
    BTN_WEST: "BTN_WEST",
    BTN_TL: "BTN_TL",
    BTN_TR: "BTN_TR",
    BTN_TL2: "BTN_TL2",
    BTN_TR2: "BTN_TR2",
    BTN_SELECT: "BTN_SELECT",
    BTN_START: "BTN_START",
    BTN_MODE: "BTN_MODE",
    BTN_THUMBL: "BTN_THUMBL",
    BTN_THUMBR: "BTN_THUMBR",
    ABS_X: "ABS_X",
    ABS_Y: "ABS_Y",
    ABS_HAT0X: "ABS_HAT0X",
    ABS_HAT0Y: "ABS_HAT0Y",
}

# 默认映射尽量贴合 mGBA 键盘默认值。
# 如果实体手柄布局和你的习惯相反，可以用 --swap-ab 调换 A/B。
DEFAULT_BUTTON_MAP = {
    BTN_SOUTH: KEY_X,
    BTN_EAST: KEY_Z,
    BTN_WEST: KEY_A,
    BTN_NORTH: KEY_S,
    BTN_TL: KEY_A,
    BTN_TR: KEY_S,
    BTN_SELECT: KEY_BACKSPACE,
    BTN_START: KEY_ENTER,
    BTN_MODE: KEY_ESC,
}

SWAPPED_BUTTON_MAP = {
    **DEFAULT_BUTTON_MAP,
    BTN_SOUTH: KEY_Z,
    BTN_EAST: KEY_X,
}

DIRECTION_KEYS = {
    "left": KEY_LEFT,
    "right": KEY_RIGHT,
    "up": KEY_UP,
    "down": KEY_DOWN,
}


def _ioc(direction: int, kind: int, number: int, size: int) -> int:
    """按 Linux ioctl 规则计算 ioctl 编号。

    这样脚本不用依赖 python-evdev 或额外 C 头文件。
    """

    return (direction << 30) | (size << 16) | (kind << 8) | number


def _io(kind: str, number: int) -> int:
    """生成无参数 ioctl 编号。"""

    return _ioc(0, ord(kind), number, 0)


def _iow(kind: str, number: int, size: int) -> int:
    """生成写入参数的 ioctl 编号。"""

    return _ioc(1, ord(kind), number, size)


# uinput ioctl 编号。
UI_SET_EVBIT = _iow("U", 100, struct.calcsize("i"))
UI_SET_KEYBIT = _iow("U", 101, struct.calcsize("i"))
UI_DEV_CREATE = _io("U", 1)
UI_DEV_DESTROY = _io("U", 2)
UI_DEV_SETUP = _iow("U", 3, struct.calcsize("HHHH80sI"))

# evdev 独占读取 ioctl。开启后物理手柄事件不会再同时送给其它程序。
EVIOCGRAB = _iow("E", 0x90, struct.calcsize("i"))


@dataclass
class InputDeviceInfo:
    """从 /proc/bus/input/devices 解析出的输入设备信息。"""

    name: str
    handlers: str
    event_path: str | None


class VirtualKeyboard:
    """通过 /dev/uinput 创建虚拟键盘。"""

    def __init__(self, keys: set[int]) -> None:
        self.keys = keys
        self.fd: int | None = None

    def __enter__(self) -> "VirtualKeyboard":
        """创建虚拟键盘设备。"""

        fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        self.fd = fd

        # 第一步：声明这个虚拟设备会发送 EV_KEY 和 EV_SYN。
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)

        # 第二步：声明会用到哪些键。没有声明的键，内核会拒绝发送。
        for key in sorted(self.keys):
            fcntl.ioctl(fd, UI_SET_KEYBIT, key)

        # 第三步：设置虚拟设备身份，让桌面和 mGBA 看到它是一把键盘。
        name = UINPUT_DEVICE_NAME.encode("utf-8")[:79]
        setup = struct.pack("HHHH80sI", BUS_USB, 0x3566, 0x00BA, 1, name, 0)
        fcntl.ioctl(fd, UI_DEV_SETUP, setup)
        fcntl.ioctl(fd, UI_DEV_CREATE)

        # uinput 创建设备后需要给桌面一点时间识别。
        time.sleep(0.2)
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        """销毁虚拟键盘设备。"""

        if self.fd is None:
            return
        try:
            fcntl.ioctl(self.fd, UI_DEV_DESTROY)
        finally:
            os.close(self.fd)
            self.fd = None

    def send_key(self, key: int, pressed: bool) -> None:
        """发送一次键盘按下或松开。"""

        value = 1 if pressed else 0
        self._write_event(EV_KEY, key, value)
        self._write_event(EV_SYN, SYN_REPORT, 0)

    def _write_event(self, event_type: int, code: int, value: int) -> None:
        """向 /dev/uinput 写入单个 input_event。"""

        if self.fd is None:
            raise RuntimeError("virtual keyboard is not open")
        now = time.time()
        sec = int(now)
        usec = int((now - sec) * 1_000_000)
        os.write(self.fd, struct.pack(INPUT_EVENT_FORMAT, sec, usec, event_type, code, value))


class Bridge:
    """读取手柄事件并发出键盘事件。"""

    def __init__(
        self,
        event_path: str,
        button_map: dict[int, int],
        grab: bool,
        show_events: bool,
        analog_deadzone: int,
    ) -> None:
        self.event_path = event_path
        self.button_map = button_map
        self.grab = grab
        self.show_events = show_events
        self.analog_deadzone = analog_deadzone
        self.key_sources: dict[int, set[str]] = {}
        self.analog_center: dict[int, int] = {}
        self.stop_requested = False

    def run(self) -> None:
        """启动桥接循环，直到用户按 Ctrl+C。"""

        keys = set(self.button_map.values()) | set(DIRECTION_KEYS.values())
        with VirtualKeyboard(keys) as keyboard:
            with open(self.event_path, "rb", buffering=0) as event_file:
                if self.grab:
                    fcntl.ioctl(event_file.fileno(), EVIOCGRAB, 1)

                try:
                    self._loop(event_file, keyboard)
                finally:
                    if self.grab:
                        fcntl.ioctl(event_file.fileno(), EVIOCGRAB, 0)
                    self._release_all(keyboard)

    def _loop(self, event_file, keyboard: VirtualKeyboard) -> None:
        """主循环：等待 eventX 产生事件，然后逐条处理。"""

        signal.signal(signal.SIGINT, self._request_stop)
        signal.signal(signal.SIGTERM, self._request_stop)

        print("手柄到键盘映射已启动。按 Ctrl+C 停止。", flush=True)
        print(f"读取设备: {self.event_path}", flush=True)
        print("默认键位: 方向键=方向，BTN_SOUTH=X(GBA A)，BTN_EAST=Z(GBA B)，Start=Enter，Select=Backspace", flush=True)

        while not self.stop_requested:
            readable, _, _ = select.select([event_file], [], [], 0.5)
            if not readable:
                continue

            data = event_file.read(INPUT_EVENT_SIZE)
            if len(data) != INPUT_EVENT_SIZE:
                continue

            _, _, event_type, code, value = struct.unpack(INPUT_EVENT_FORMAT, data)
            if event_type == EV_KEY:
                self._handle_button(code, value, keyboard)
            elif event_type == EV_ABS:
                self._handle_axis(code, value, keyboard)

    def _request_stop(self, _signum, _frame) -> None:
        """收到停止信号时退出循环。"""

        self.stop_requested = True

    def _handle_button(self, code: int, value: int, keyboard: VirtualKeyboard) -> None:
        """处理手柄按钮。

        value: 1 表示按下，0 表示松开，2 表示长按重复。
        键盘桥接只需要按下/松开，重复事件交给 mGBA 自己处理。
        """

        key = self.button_map.get(code)
        if key is None or value == 2:
            return

        pressed = value != 0
        self._set_key_source(keyboard, key, f"button:{code}", pressed)
        if self.show_events:
            print(f"{event_name(code)} -> {key_name(key)} {'down' if pressed else 'up'}", flush=True)

    def _handle_axis(self, code: int, value: int, keyboard: VirtualKeyboard) -> None:
        """处理方向键和左摇杆。

        Xbox 手柄的十字键通常是 ABS_HAT0X / ABS_HAT0Y。
        左摇杆通常是 ABS_X / ABS_Y；脚本会把第一次看到的值当作中心点。
        """

        if code == ABS_HAT0X:
            self._set_direction(keyboard, "left", "hat0x", value < 0)
            self._set_direction(keyboard, "right", "hat0x", value > 0)
            return

        if code == ABS_HAT0Y:
            self._set_direction(keyboard, "up", "hat0y", value < 0)
            self._set_direction(keyboard, "down", "hat0y", value > 0)
            return

        if code in (ABS_X, ABS_Y):
            center = self.analog_center.setdefault(code, value)
            delta = value - center
            if code == ABS_X:
                self._set_direction(keyboard, "left", "absx", delta < -self.analog_deadzone)
                self._set_direction(keyboard, "right", "absx", delta > self.analog_deadzone)
            else:
                self._set_direction(keyboard, "up", "absy", delta < -self.analog_deadzone)
                self._set_direction(keyboard, "down", "absy", delta > self.analog_deadzone)

    def _set_direction(self, keyboard: VirtualKeyboard, direction: str, source: str, pressed: bool) -> None:
        """把方向状态转换成键盘方向键。"""

        key = DIRECTION_KEYS[direction]
        changed = self._set_key_source(keyboard, key, f"direction:{direction}:{source}", pressed)
        if self.show_events:
            if changed:
                print(f"{direction} -> {key_name(key)} {'down' if pressed else 'up'}", flush=True)

    def _set_key_source(self, keyboard: VirtualKeyboard, key: int, source: str, pressed: bool) -> bool:
        """按来源维护键盘状态。

        同一个虚拟键可能来自多个手柄输入，例如备用按键和肩键都映射到同一个键。
        只有第一个来源按下时才发 key down，最后一个来源松开时才发 key up。
        """

        if pressed:
            sources = self.key_sources.setdefault(key, set())
            if source in sources:
                return False
            was_pressed = bool(sources)
            sources.add(source)
            if not was_pressed:
                keyboard.send_key(key, True)
                return True
            return False

        sources = self.key_sources.get(key)
        if not sources or source not in sources:
            return False
        sources.remove(source)
        if sources:
            return False
        keyboard.send_key(key, False)
        del self.key_sources[key]
        return True

    def _release_all(self, keyboard: VirtualKeyboard) -> None:
        """退出脚本前释放所有虚拟按键，避免桌面误以为某个键一直按住。"""

        for key in list(self.key_sources):
            keyboard.send_key(key, False)
        self.key_sources.clear()


def parse_devices() -> list[InputDeviceInfo]:
    """解析 /proc/bus/input/devices，找出可用输入设备。"""

    path = Path("/proc/bus/input/devices")
    if not path.exists():
        return []

    devices: list[InputDeviceInfo] = []
    sections = path.read_text(encoding="utf-8", errors="replace").strip().split("\n\n")

    for section in sections:
        name_match = re.search(r'N: Name="([^"]+)"', section)
        handlers_match = re.search(r"H: Handlers=(.+)", section)
        if not name_match or not handlers_match:
            continue

        handlers = handlers_match.group(1)
        event_match = re.search(r"\bevent\d+\b", handlers)
        devices.append(
            InputDeviceInfo(
                name=name_match.group(1),
                handlers=handlers,
                event_path=f"/dev/input/{event_match.group(0)}" if event_match else None,
            )
        )

    return devices


def find_gamepad_event() -> str | None:
    """自动选择最像手柄的 event 设备。"""

    keywords = ("gamepad", "controller", "joystick", "xbox", "8bitdo", "dualshock", "dualsense")
    for device in parse_devices():
        if not device.event_path:
            continue
        lower_name = device.name.lower()
        if any(keyword in lower_name for keyword in keywords):
            return device.event_path
    return None


def list_devices() -> None:
    """列出当前输入设备，方便用户找到 eventX。"""

    for device in parse_devices():
        marker = "手柄候选" if device.event_path and device.event_path == find_gamepad_event() else ""
        print(f"{device.event_path or '-':18} {device.name}  [{device.handlers}] {marker}")


def event_name(code: int) -> str:
    """把事件码转成可读名称。"""

    return CODE_NAMES.get(code, f"code_{code}")


def key_name(code: int) -> str:
    """把键盘码转成可读名称。"""

    return KEY_NAMES.get(code, f"key_{code}")


def require_root_hint() -> None:
    """检查权限并给出初学者能直接照做的提示。"""

    if os.geteuid() == 0:
        return
    print("需要 root 权限读取 /dev/input/eventX 并写入 /dev/uinput。", file=sys.stderr)
    print("请这样运行：", file=sys.stderr)
    print("  sudo python3 ~/rk3566_gba/scripts/gamepad-keyboard-bridge.py --event /dev/input/event3", file=sys.stderr)
    raise SystemExit(1)


def parse_args() -> argparse.Namespace:
    """解析命令行参数。"""

    parser = argparse.ArgumentParser(description="把 evdev 手柄输入映射成 mGBA 默认键盘按键。")
    parser.add_argument("--list", action="store_true", help="列出输入设备后退出")
    parser.add_argument("--event", help="手柄 event 设备，例如 /dev/input/event3；不填则自动寻找")
    parser.add_argument("--swap-ab", action="store_true", help="调换 BTN_SOUTH/BTN_EAST 对应的 GBA A/B")
    parser.add_argument("--grab", action="store_true", help="独占读取物理手柄，避免事件同时送给其它程序")
    parser.add_argument("--show-events", action="store_true", help="打印每次转换，便于调试按键映射")
    parser.add_argument("--analog-deadzone", type=int, default=8000, help="左摇杆方向阈值，默认 8000")
    return parser.parse_args()


def main() -> int:
    """程序入口。"""

    args = parse_args()

    if args.list:
        list_devices()
        return 0

    require_root_hint()

    event_path = args.event or find_gamepad_event()
    if not event_path:
        print("没有自动找到手柄 event 设备。请先运行 --list 查看，再用 --event 指定。", file=sys.stderr)
        return 2
    if not Path(event_path).exists():
        print(f"输入设备不存在: {event_path}", file=sys.stderr)
        return 2
    if not Path("/dev/uinput").exists():
        print("/dev/uinput 不存在，当前系统无法创建虚拟键盘。", file=sys.stderr)
        return 2

    button_map = SWAPPED_BUTTON_MAP if args.swap_ab else DEFAULT_BUTTON_MAP
    bridge = Bridge(
        event_path=event_path,
        button_map=button_map,
        grab=args.grab,
        show_events=args.show_events,
        analog_deadzone=args.analog_deadzone,
    )
    bridge.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
