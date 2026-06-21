# -*- coding: utf-8 -*-
"""Radxa CM3 / RK3566 开发辅助窗口。

这个脚本运行在 Windows Python 上，通过按钮调用 WSL、rsync 和 ssh。
目的：把常用的构建、同步、板端测试步骤固定下来，减少每次手动输入命令的重复劳动。
"""

from __future__ import annotations

import json
import queue
import shlex
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from tkinter import END, LEFT, RIGHT, BOTH, X, Y, StringVar, Text, Tk, messagebox
from tkinter import ttk


APP_TITLE = "Radxa CM3 GBA 开发助手"
CONFIG_FILE = ".radxa-dev-gui.json"
SSH_OPTIONS = "-o BatchMode=yes -o ConnectTimeout=8"
WSL_NOISE_MARKERS = (
    "WSL",
    "localhost",
    "NAT",
    "wsl",
)
CREATE_NEW_CONSOLE = getattr(subprocess, "CREATE_NEW_CONSOLE", 0)


def repo_root() -> Path:
    """返回仓库根目录。

    脚本放在 tools/ 下，所以父目录的父目录就是仓库根目录。
    后续所有命令都围绕这个目录运行，避免从错误路径构建或同步。
    """

    return Path(__file__).resolve().parents[1]


def windows_path_to_wsl(path: Path) -> str:
    """把 Windows 路径转换成 WSL 路径。

    示例：
    D:\\1workandstudy\\03_rk3566_gba\\rk3566_gba
    会转换为：
    /mnt/d/1workandstudy/03_rk3566_gba/rk3566_gba

    用法：WSL 中的 cmake、rsync、ssh 都需要 Linux 风格路径。
    """

    resolved = path.resolve()
    if not resolved.drive:
        return str(resolved)

    drive = resolved.drive.rstrip(":").lower()
    tail = str(resolved)[len(resolved.drive) :].replace("\\", "/")
    if not tail.startswith("/"):
        tail = "/" + tail
    return f"/mnt/{drive}{tail}"


def quoted(value: str) -> str:
    """对传给 WSL bash 的片段做 POSIX shell 转义。"""

    return shlex.quote(value)


def quoted_remote_path(value: str) -> str:
    """转义远端 Linux 路径，同时保留开头的 `~` 展开。

    如果把 `~/rk3566_gba` 整体写成 `'~/rk3566_gba'`，远端 shell 不会把 `~`
    展开成用户家目录。所以这里让开头的 `~/` 保持不加引号，只转义后面的路径片段。
    """

    if value == "~":
        return "~"
    if value.startswith("~/"):
        rest = value[2:]
        return "~/" + quoted(rest) if rest else "~/"
    return quoted(value)


@dataclass
class GuiCommand:
    """描述一个按钮要执行的单条命令。

    title 用于日志标题。
    bash 是最终传给 `wsl bash -lc` 的命令字符串。
    """

    title: str
    bash: str


class RadxaDevGui:
    """主窗口逻辑。

    这个类负责：
    1. 读取和保存本地配置。
    2. 根据按钮生成 WSL/SSH/rsync 命令。
    3. 在后台线程执行命令，避免窗口卡死。
    4. 把命令输出实时写入日志窗口。
    """

    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title(APP_TITLE)
        self.root.geometry("1040x720")

        self.repo = repo_root()
        self.repo_wsl = windows_path_to_wsl(self.repo)
        self.config_path = self.repo / CONFIG_FILE
        self.output_queue: queue.Queue[str] = queue.Queue()
        self.worker_running = False

        self.board_user = StringVar(value="radxa")
        self.board_host = StringVar(value="")
        self.remote_dir = StringVar(value="~/rk3566_gba")
        self.rom_path = StringVar(value="")

        self._build_ui()
        self._load_config()
        self._poll_output()

    def _build_ui(self) -> None:
        """创建窗口控件。

        布局分三块：
        - 配置区：填写板子用户名、IP、远端源码目录和 ROM 路径。
        - 按钮区：一键触发常用开发步骤。
        - 日志区：显示每条命令和执行输出。
        """

        outer = ttk.Frame(self.root, padding=12)
        outer.pack(fill=BOTH, expand=True)

        config = ttk.LabelFrame(outer, text="板端配置", padding=10)
        config.pack(fill=X)

        ttk.Label(config, text="用户名").grid(row=0, column=0, sticky="w")
        ttk.Entry(config, textvariable=self.board_user, width=18).grid(row=0, column=1, sticky="ew", padx=(6, 16))

        ttk.Label(config, text="板子 IP / 主机名").grid(row=0, column=2, sticky="w")
        ttk.Entry(config, textvariable=self.board_host, width=26).grid(row=0, column=3, sticky="ew", padx=(6, 16))

        ttk.Label(config, text="远端源码目录").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(config, textvariable=self.remote_dir, width=38).grid(
            row=1, column=1, columnspan=3, sticky="ew", padx=(6, 16), pady=(8, 0)
        )

        ttk.Label(config, text="GBA ROM 路径").grid(row=2, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(config, textvariable=self.rom_path, width=38).grid(
            row=2, column=1, columnspan=3, sticky="ew", padx=(6, 16), pady=(8, 0)
        )

        config.columnconfigure(3, weight=1)

        buttons = ttk.LabelFrame(outer, text="操作", padding=10)
        buttons.pack(fill=X, pady=(10, 0))

        # 第一组：本机 / WSL 操作。
        ttk.Button(buttons, text="保存配置", command=self.save_config).pack(side=LEFT, padx=(0, 6))
        ttk.Button(buttons, text="检查 WSL 工具", command=self.check_wsl_tools).pack(side=LEFT, padx=6)
        ttk.Button(buttons, text="WSL 构建测试", command=self.wsl_build_test).pack(side=LEFT, padx=6)

        # 第二组：和板子交互的操作。
        ttk.Button(buttons, text="同步源码到板子", command=self.sync_to_board).pack(side=LEFT, padx=6)
        ttk.Button(buttons, text="板端构建测试", command=self.board_build_test).pack(side=LEFT, padx=6)
        ttk.Button(buttons, text="板端 probe", command=self.board_probe).pack(side=LEFT, padx=6)
        ttk.Button(buttons, text="板端 gba-check", command=self.board_gba_check).pack(side=LEFT, padx=6)
        ttk.Button(buttons, text="一键全流程", command=self.full_flow).pack(side=LEFT, padx=6)

        terminal_buttons = ttk.Frame(outer)
        terminal_buttons.pack(fill=X, pady=(8, 0))
        ttk.Button(terminal_buttons, text="打开 WSL 终端", command=self.open_wsl_terminal).pack(side=LEFT, padx=(0, 6))
        ttk.Button(terminal_buttons, text="初始化 SSH 免密终端", command=self.open_ssh_key_terminal).pack(side=LEFT, padx=6)
        ttk.Button(terminal_buttons, text="打开板子 SSH 终端", command=self.open_board_ssh_terminal).pack(side=LEFT, padx=6)
        ttk.Button(terminal_buttons, text="清空日志", command=self.clear_log).pack(side=RIGHT)

        log_frame = ttk.LabelFrame(outer, text="日志", padding=10)
        log_frame.pack(fill=BOTH, expand=True, pady=(10, 0))

        scrollbar = ttk.Scrollbar(log_frame)
        scrollbar.pack(side=RIGHT, fill=Y)

        self.log = Text(log_frame, wrap="word", yscrollcommand=scrollbar.set, font=("Consolas", 10))
        self.log.pack(side=LEFT, fill=BOTH, expand=True)
        scrollbar.config(command=self.log.yview)

        self._append_log(f"仓库路径: {self.repo}\n")
        self._append_log(f"WSL 路径: {self.repo_wsl}\n")

    def _load_config(self) -> None:
        """读取本地配置。

        配置文件只保存个人机器信息，例如板子 IP 和用户名。
        它会被 .gitignore 忽略，不应该提交到仓库。
        """

        if not self.config_path.exists():
            return

        try:
            data = json.loads(self.config_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            self._append_log(f"读取配置失败: {exc}\n")
            return

        self.board_user.set(data.get("board_user", self.board_user.get()))
        self.board_host.set(data.get("board_host", self.board_host.get()))
        self.remote_dir.set(data.get("remote_dir", self.remote_dir.get()))
        self.rom_path.set(data.get("rom_path", self.rom_path.get()))

    def save_config(self) -> None:
        """保存窗口配置，方便下次打开直接使用。"""

        data = {
            "board_user": self.board_user.get().strip(),
            "board_host": self.board_host.get().strip(),
            "remote_dir": self.remote_dir.get().strip(),
            "rom_path": self.rom_path.get().strip(),
        }
        self.config_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        self._append_log(f"已保存配置: {self.config_path}\n")

    def check_wsl_tools(self) -> None:
        """检查 WSL 里是否具备开发所需工具。"""

        command = (
            f"cd {quoted(self.repo_wsl)} && "
            "printf 'PWD=%s\\n' \"$PWD\" && uname -a && "
            "printf '\\nTools:\\n' && "
            "for tool in cmake g++ make ninja rsync ssh; do "
            "if command -v \"$tool\" >/dev/null 2>&1; then printf '%-8s %s\\n' \"$tool\" \"$(command -v \"$tool\")\"; "
            "else printf '%-8s missing\\n' \"$tool\"; fi; "
            "done"
        )
        self._run_commands([GuiCommand("检查 WSL 工具", command)])

    def wsl_build_test(self) -> None:
        """在 WSL 中执行本机 Linux 构建和测试。"""

        command = (
            f"cd {quoted(self.repo_wsl)} && "
            "cmake --preset debug && "
            "cmake --build --preset debug && "
            "ctest --preset debug"
        )
        self._run_commands([GuiCommand("WSL 构建测试", command)])

    def sync_to_board(self) -> None:
        """把当前源码同步到 Radxa 板子。

        说明：
        - 优先使用 rsync，可以只传变更文件。
        - 如果板子端没有 rsync，自动改用 tar 兜底同步。
        - 排除 build/，避免把本机 x86_64 构建产物传到 ARM 板子。
        - 排除 .git/ 和本地 GUI 配置，减少无关文件。
        """

        if not self._validate_board_config():
            return
        self.save_config()
        self._run_commands([GuiCommand("同步源码到板子", self._sync_command())])

    def board_build_test(self) -> None:
        """SSH 到板子，在板子上执行 CMake 构建和测试。"""

        if not self._validate_board_config():
            return
        self.save_config()
        remote = "rm -rf build/debug && cmake --preset debug && cmake --build --preset debug && ctest --preset debug"
        self._run_commands([GuiCommand("板端构建测试", self._ssh_command(remote))])

    def board_probe(self) -> None:
        """SSH 到板子运行硬件基线探测。"""

        if not self._validate_board_config():
            return
        self.save_config()
        self._run_commands([GuiCommand("板端 probe", self._ssh_command("./build/debug/rk3566-gba probe"))])

    def board_gba_check(self) -> None:
        """SSH 到板子运行 GBA 实测准备检查。"""

        if not self._validate_board_config():
            return
        self.save_config()
        rom = self.rom_path.get().strip()
        prefix = f"RK3566_GBA_ROM={quoted_remote_path(rom)} " if rom else ""
        self._run_commands([GuiCommand("板端 gba-check", self._ssh_command(f"{prefix}./build/debug/rk3566-gba gba-check"))])

    def full_flow(self) -> None:
        """执行推荐的一键流程。

        顺序：
        1. WSL 本机构建测试，先确认源码没有明显问题。
        2. 同步源码到板子，优先 rsync，板端缺少 rsync 时自动使用 tar 兜底。
        3. 板子本机重新构建测试，确保架构和系统库匹配。
        4. 板端 probe，记录 HDMI/音频/输入/温度基线。
        5. 板端 gba-check，确认模拟器和 ROM 准备情况。
        """

        if not self._validate_board_config():
            return
        self.save_config()

        rom = self.rom_path.get().strip()
        gba_prefix = f"RK3566_GBA_ROM={quoted_remote_path(rom)} " if rom else ""
        commands = [
            GuiCommand(
                "WSL 构建测试",
                f"cd {quoted(self.repo_wsl)} && cmake --preset debug && cmake --build --preset debug && ctest --preset debug",
            ),
            GuiCommand("同步源码到板子", self._sync_command()),
            GuiCommand(
                "板端构建测试",
                self._ssh_command("rm -rf build/debug && cmake --preset debug && cmake --build --preset debug && ctest --preset debug"),
            ),
            GuiCommand("板端 probe", self._ssh_command("./build/debug/rk3566-gba probe")),
            GuiCommand("板端 gba-check", self._ssh_command(f"{gba_prefix}./build/debug/rk3566-gba gba-check")),
        ]
        self._run_commands(commands)

    def open_wsl_terminal(self) -> None:
        """打开一个交互式 WSL 终端，并进入仓库目录。"""

        script = self._write_wsl_script(
            "wsl-terminal",
            f"""
            cd {quoted(self.repo_wsl)}
            rm -f "$0"
            exec bash
            """,
        )
        self._open_console(["wsl", "bash", script], "WSL 终端")

    def open_ssh_key_terminal(self) -> None:
        """打开交互终端，初始化 SSH 免密登录。

        这个步骤通常只需要做一次。
        如果没有 SSH key，会先生成 ed25519 key，然后执行 ssh-copy-id。
        ssh-copy-id 需要输入一次板子密码，所以必须放到交互终端里做。
        """

        if not self._validate_board_config():
            return
        target = self._target()
        script = self._write_wsl_script(
            "ssh-init",
            f"""
            target={quoted(target)}

            mkdir -p ~/.ssh
            chmod 700 ~/.ssh

            if [ ! -f ~/.ssh/id_ed25519 ]; then
              echo "未找到 ~/.ssh/id_ed25519，正在生成免密码 SSH key..."
              ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -C "rk3566_gba_dev"
            else
              echo "已存在 ~/.ssh/id_ed25519，跳过 SSH key 生成。"
            fi

            echo
            echo "即将把公钥安装到 $target。"
            echo "如果提示 password，请输入 Radxa 板子的登录密码。"
            ssh-copy-id "$target"

            echo
            echo "SSH 免密初始化结束。可以回到开发助手窗口继续点按钮。"
            rm -f "$0"
            exec bash
            """,
        )
        self._open_console(["wsl", "bash", script], "SSH 免密初始化终端")

    def open_board_ssh_terminal(self) -> None:
        """打开一个交互式 SSH 终端，方便临时查看板子状态。"""

        if not self._validate_board_config():
            return
        self._open_console(["wsl", "ssh", self._target()], "板子 SSH 终端")

    def clear_log(self) -> None:
        """清空日志窗口。"""

        self.log.delete("1.0", END)

    def _validate_board_config(self) -> bool:
        """检查板子连接配置是否足够生成 SSH/rsync 命令。"""

        if not self.board_user.get().strip():
            messagebox.showerror(APP_TITLE, "请填写板子用户名。")
            return False
        if not self.board_host.get().strip():
            messagebox.showerror(APP_TITLE, "请填写板子 IP 或主机名。")
            return False
        if not self.remote_dir.get().strip():
            messagebox.showerror(APP_TITLE, "请填写远端源码目录。")
            return False
        return True

    def _target(self) -> str:
        """返回 SSH 目标，例如 radxa@192.168.1.50。"""

        return f"{self.board_user.get().strip()}@{self.board_host.get().strip()}"

    def _remote_dir(self) -> str:
        """返回远端源码目录。"""

        return self.remote_dir.get().strip()

    def _sync_command(self) -> str:
        """生成源码同步命令。

        目的：
        - 板端有 rsync 时走 rsync，速度快，并且支持删除远端旧文件。
        - 板端没有 rsync 时走 tar 兜底，不需要先手动安装板端工具。
        """

        target = self._target()
        remote_dir = self._remote_dir().rstrip("/")
        remote_dir_for_shell = quoted_remote_path(remote_dir)
        remote_arg = f"{target}:{remote_dir}/"
        ssh_transport = "ssh " + SSH_OPTIONS
        remote_mkdir = f"mkdir -p {remote_dir_for_shell}"
        remote_extract = f"mkdir -p {remote_dir_for_shell} && cd {remote_dir_for_shell} && tar -xf -"
        excludes = (
            "--exclude build/ "
            "--exclude .git/ "
            f"--exclude {quoted(CONFIG_FILE)} "
            "--exclude '.radxa-dev-gui-*.sh'"
        )

        return "\n".join(
            [
                f"cd {quoted(self.repo_wsl)}",
                f"if ssh {SSH_OPTIONS} {quoted(target)} 'command -v rsync >/dev/null 2>&1'; then",
                '  echo "板端已安装 rsync，使用 rsync 增量同步。"',
                f"  rsync -av --delete {excludes} -e {quoted(ssh_transport)} ./ {quoted(remote_arg)}",
                "else",
                '  echo "板端未找到 rsync，改用 tar 兜底同步。"',
                '  echo "提示：tar 兜底不会删除板端已经存在但本地已移除的旧文件；安装 rsync 后会自动恢复增量同步。"',
                f"  ssh {SSH_OPTIONS} {quoted(target)} {quoted(remote_mkdir)}",
                f"  tar {excludes} -cf - . | ssh {SSH_OPTIONS} {quoted(target)} {quoted(remote_extract)}",
                "fi",
            ]
        )

    def _ssh_command(self, remote_command: str) -> str:
        """生成通过 SSH 在板子上执行的命令。

        remote_command 会先进入远端源码目录再运行。
        """

        remote = f"cd {quoted_remote_path(self._remote_dir())} && {remote_command}"
        return f"ssh {SSH_OPTIONS} {quoted(self._target())} {quoted(remote)}"

    def _run_commands(self, commands: list[GuiCommand]) -> None:
        """启动后台线程执行一组命令。"""

        if self.worker_running:
            messagebox.showwarning(APP_TITLE, "已有命令正在运行，请等待完成。")
            return

        self.worker_running = True
        thread = threading.Thread(target=self._worker, args=(commands,), daemon=True)
        thread.start()

    def _worker(self, commands: list[GuiCommand]) -> None:
        """后台执行命令。

        如果某一步失败，后续步骤会停止，避免在不完整状态下继续同步或运行板端测试。
        """

        try:
            for command in commands:
                self.output_queue.put(f"\n[{time.strftime('%H:%M:%S')}] {command.title}\n")
                self.output_queue.put("$ wsl bash -se\n")
                self.output_queue.put(command.bash + "\n")

                process = subprocess.Popen(
                    ["wsl", "bash", "-se"],
                    cwd=str(self.repo),
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )

                assert process.stdin is not None
                assert process.stdout is not None
                process.stdin.write((command.bash + "\n").encode("utf-8"))
                process.stdin.close()

                for raw_line in process.stdout:
                    line = raw_line.decode("utf-8", errors="replace")
                    if not self._is_wsl_startup_noise(line):
                        self.output_queue.put(line)

                return_code = process.wait()
                self.output_queue.put(f"[退出码] {return_code}\n")
                if return_code != 0:
                    self.output_queue.put("命令失败，已停止后续步骤。\n")
                    return

            self.output_queue.put("全部步骤完成。\n")
        except FileNotFoundError as exc:
            self.output_queue.put(f"启动命令失败: {exc}\n")
        finally:
            self.worker_running = False

    def _is_wsl_startup_noise(self, line: str) -> bool:
        """过滤 WSL 启动时偶发的乱码警告。

        截图里的乱码来自 wsl.exe 启动阶段的本地化提示，内容和本项目无关。
        这些提示经常夹杂 NUL 字符或替换字符，放进日志会误导判断。
        """

        if "\x00" in line or "�" in line:
            return True
        return False

    def _write_wsl_script(self, name: str, body: str) -> str:
        """写入一个临时 WSL bash 脚本并返回 WSL 路径。

        交互式命令不再通过 `wsl bash -lc "..."` 传递，避免 PowerShell、wsl.exe
        和 bash 三层引号把 `ssh-keygen -N ""` 这样的空参数吃掉。
        """

        script_path = self.repo / f".radxa-dev-gui-{name}.sh"
        lines = ["#!/usr/bin/env bash", "set -e"]
        lines.extend(line.strip() for line in body.strip().splitlines())
        script_path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        return windows_path_to_wsl(script_path)

    def _open_console(self, args: list[str], title: str) -> None:
        """打开一个新的控制台窗口执行交互式命令。"""

        try:
            subprocess.Popen(
                args,
                cwd=str(self.repo),
                creationflags=CREATE_NEW_CONSOLE,
            )
            self._append_log(f"已打开{title}: {' '.join(args)}\n")
        except OSError as exc:
            messagebox.showerror(APP_TITLE, f"打开{title}失败：{exc}")

    def _append_log(self, text: str) -> None:
        """向日志窗口追加文本并滚动到底部。"""

        self.log.insert(END, text)
        self.log.see(END)

    def _poll_output(self) -> None:
        """定时从队列取后台线程输出，写入 Tk 日志控件。"""

        while True:
            try:
                text = self.output_queue.get_nowait()
            except queue.Empty:
                break
            self._append_log(text)

        self.root.after(80, self._poll_output)


def main() -> None:
    """启动 GUI。"""

    root = Tk()
    RadxaDevGui(root)
    root.mainloop()


if __name__ == "__main__":
    main()
