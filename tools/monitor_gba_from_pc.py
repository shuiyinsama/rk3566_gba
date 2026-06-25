# -*- coding: utf-8 -*-
"""从 Windows 开发机远程查看 Radxa GBA 稳定性监控。

这个脚本运行在电脑上，通过 WSL 里的 ssh 连接板子。
目的：不用一直盯着板子的小屏幕，在电脑终端实时看到温度、CPU、内存、mGBA 进程和显示模式。
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from datetime import datetime
from pathlib import Path


CONFIG_FILE = ".radxa-dev-gui.json"
SSH_OPTIONS = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8"]


def repo_root() -> Path:
    """返回仓库根目录。

    脚本放在 tools/ 下，所以父目录的父目录就是仓库根目录。
    本地日志会写到仓库的 logs/ 目录，便于之后整理实测记录。
    """

    return Path(__file__).resolve().parents[1]


def load_gui_config(root: Path) -> dict[str, str]:
    """读取开发助手保存的板端配置。

    如果你已经在图形开发助手里填过板子 IP、远端目录和 ROM 路径，
    这里会自动复用，避免命令行里再重复输入。
    """

    path = root / CONFIG_FILE
    if not path.exists():
        return {}

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}

    return {key: str(value) for key, value in data.items() if value is not None}


def quote_remote_path(value: str) -> str:
    """转义远端 Linux 路径，同时保留开头的 `~` 展开。

    远端 shell 只有看到未加引号的 `~/`，才会展开成 `/home/radxa/`。
    """

    if value == "~":
        return "~"
    if value.startswith("~/"):
        rest = value[2:]
        return "~/" + shlex.quote(rest) if rest else "~/"
    return shlex.quote(value)


def build_parser(config: dict[str, str]) -> argparse.ArgumentParser:
    """创建命令行参数解析器。

    默认值优先来自 .radxa-dev-gui.json；没有配置时使用当前项目约定。
    """

    default_user = config.get("board_user") or "radxa"
    default_host = config.get("board_host") or "192.168.8.43"
    default_board = f"{default_user}@{default_host}" if "@" not in default_host else default_host
    default_remote_dir = config.get("remote_dir") or "~/rk3566_gba"
    default_rom = config.get("rom_path") or ""

    parser = argparse.ArgumentParser(description="在电脑上实时查看 Radxa GBA 稳定性监控输出。")
    parser.add_argument("--board", default=default_board, help="SSH 目标，例如 radxa@192.168.8.43")
    parser.add_argument("--remote-dir", default=default_remote_dir, help="板端源码目录，默认来自开发助手配置")
    parser.add_argument("--interval", type=int, default=10, help="采样间隔秒数，默认 10")
    parser.add_argument("--duration", type=int, default=1800, help="监控总时长秒数，默认 1800；0 表示持续运行")
    parser.add_argument("--tag", default="gba-stability", help="板端日志文件名前缀")
    parser.add_argument("--launch", action="store_true", help="监控前先用 launch-gba.sh 后台启动 mGBA")
    parser.add_argument("--rom", default=default_rom, help="配合 --launch 使用的 GBA ROM 路径")
    parser.add_argument("--direct-ssh", action="store_true", help="直接调用 Windows ssh；默认通过 WSL ssh")
    parser.add_argument("--local-log-dir", default=str(repo_root() / "logs"), help="电脑端日志目录")
    return parser


def build_remote_command(args: argparse.Namespace) -> str:
    """拼出要在板子上执行的远端命令。

    如果传了 --launch，会先后台启动 mGBA，再进入稳定性采样；
    如果没有传 --launch，则只监控当前已经运行的 mGBA。
    """

    remote_dir = args.remote_dir.rstrip("/")
    monitor_script = f"{remote_dir}/scripts/monitor-gba.sh"
    command_parts: list[str] = []

    if args.launch:
        if not args.rom:
            raise SystemExit("使用 --launch 时需要提供 --rom，或先在开发助手里保存 GBA ROM 路径。")
        launch_script = f"{remote_dir}/scripts/launch-gba.sh"
        command_parts.append(
            "bash "
            + quote_remote_path(launch_script)
            + " --background "
            + quote_remote_path(args.rom)
        )

    command_parts.append(
        "bash "
        + quote_remote_path(monitor_script)
        + f" --duration {int(args.duration)}"
        + f" --interval {int(args.interval)}"
        + " --tag "
        + shlex.quote(args.tag)
    )

    return " && ".join(command_parts)


def run_streaming_command(command: list[str], local_log: Path) -> int:
    """执行远程监控命令，并把输出同时写到屏幕和电脑端日志。

    stdout/stderr 合并处理，这样板端脚本的错误信息也会进入同一份记录。
    """

    local_log.parent.mkdir(parents=True, exist_ok=True)
    print(f"电脑端日志: {local_log}", flush=True)
    print("启动命令: " + " ".join(shlex.quote(part) for part in command), flush=True)
    print(flush=True)

    with local_log.open("w", encoding="utf-8", newline="\n") as log_file:
        log_file.write("启动命令: " + " ".join(shlex.quote(part) for part in command) + "\n\n")
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )

        assert process.stdout is not None
        try:
            for line in process.stdout:
                if is_wsl_startup_noise(line):
                    continue
                print(line, end="", flush=True)
                log_file.write(line)
                log_file.flush()
        except KeyboardInterrupt:
            print("\n收到 Ctrl+C，正在停止远程监控...", flush=True)
            process.terminate()

        return process.wait()


def is_wsl_startup_noise(line: str) -> bool:
    """过滤 WSL 启动阶段的本地化乱码提示。

    这类提示经常带 NUL 字符或替换字符，和板端稳定性数据无关。
    """

    return "\x00" in line or "�" in line


def main() -> int:
    """命令行入口。"""

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8")

    root = repo_root()
    config = load_gui_config(root)
    parser = build_parser(config)
    args = parser.parse_args()

    remote_command = build_remote_command(args)
    ssh_command = ["ssh", *SSH_OPTIONS, args.board, remote_command]
    if not args.direct_ssh:
        ssh_command = ["wsl", *ssh_command]

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    local_log = Path(args.local_log_dir) / f"gba-monitor-pc-{stamp}.log"
    return run_streaming_command(ssh_command, local_log)


if __name__ == "__main__":
    raise SystemExit(main())
