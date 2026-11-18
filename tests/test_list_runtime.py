"""Exercise list paths, entry markers, and human-readable file sizes.
验证列表路径、条目标记和可读文件尺寸。
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class ListRuntimeTests(unittest.TestCase):
    """Run focused list checks against the bundled LuaSkills runtime.
    使用随附的 LuaSkills 运行时执行聚焦的列表检查。
    """

    @classmethod
    def setUpClass(cls) -> None:
        """Prepare an isolated runtime without changing the checked-in package.
        准备隔离运行时，同时不修改仓库中的技能包。

        Returns:
            None: The runtime is ready, or the class is skipped when unavailable.
        返回值：
            None：运行时准备就绪；缺失时跳过整个测试类。
        """
        # Resolve the package and bundled debug runtime locations.
        # 确定技能包和随附调试运行时的位置。
        cls.root = Path(__file__).resolve().parent.parent
        cls.debug_root = cls.root.parent / "luaskills-debug"
        # Use a locally built debugger for an unreleased manifest contract.
        # 使用本地构建的调试器验证尚未发布的清单契约。
        debugger = os.environ.get("VULCAN_FILE_DEBUGGER")
        cls.executable = Path(debugger).resolve(strict=True) if debugger else cls.debug_root / "bin" / "luaskills-debug.exe"
        if not cls.executable.is_file():
            raise unittest.SkipTest("bundled luaskills-debug.exe is not available")

        # Copy the runtime so test calls cannot affect its shared distribution.
        # 复制运行时，避免测试调用影响共享发行目录。
        cls.runtime_directory = tempfile.TemporaryDirectory(prefix="vulcan-file-list-runtime-")
        cls.isolated_runtime = Path(cls.runtime_directory.name) / "runtime"
        cls.isolated_skill = Path(cls.runtime_directory.name) / "skill"
        shutil.copytree(
            cls.debug_root / "runtime",
            cls.isolated_runtime,
            ignore=shutil.ignore_patterns(".git"),
        )
        # Install a package copy without Git internals, which can exceed Windows path limits.
        # 安装不含 Git 内部文件的技能包副本，避免超过 Windows 路径长度限制。
        shutil.copytree(
            cls.root,
            cls.isolated_skill,
            ignore=shutil.ignore_patterns(".git", "__pycache__", "tests"),
        )
        cls.addClassCleanup(cls.runtime_directory.cleanup)

    @classmethod
    def call_list(cls, arguments: dict) -> str:
        """Invoke the list entry and return its rendered content.
        调用列表入口并返回渲染后的内容。

        Parameters:
            arguments: JSON-compatible list request.
        参数：
            arguments：可序列化为 JSON 的列表请求。

        Returns:
            str: Tool output text.
        返回值：
            str：工具输出文本。
        """
        # Run the real skill entry through the same debug CLI used by edit tests.
        # 通过编辑测试所用的同一调试命令行执行真实技能入口。
        completed = subprocess.run(
            [
                str(cls.executable),
                "call",
                "--runtime-root",
                str(cls.isolated_runtime),
                "--skill-path",
                str(cls.isolated_skill),
                "--tool",
                "list",
                "--args-json",
                json.dumps(arguments, ensure_ascii=False, separators=(",", ":")),
                "--output",
                "json",
            ],
            cwd=cls.root,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(
                f"debug runtime failed with code {completed.returncode}: "
                f"{completed.stdout}\n{completed.stderr}"
            )
        # Decode only the public result content rather than debug metadata.
        # 仅解码公开结果正文，不依赖调试元数据。
        envelope = json.loads(completed.stdout)
        return envelope["result"]["content"]

    def test_relative_pwd_query_returns_reusable_paths_and_sizes(self) -> None:
        """Check that a relative scan keeps PWD-based paths and formats sizes.
        检查相对扫描保留基于 PWD 的路径并格式化尺寸。

        Returns:
            None: Assertions cover B, KB, MB, and both entry markers.
        返回值：
            None：断言覆盖 B、KB、MB 以及两种条目标记。
        """
        with tempfile.TemporaryDirectory(prefix="vulcan-file-list-fixture-") as directory:
            # Build nested files with exact sizes at representative unit boundaries.
            # 构造精确尺寸的嵌套文件，覆盖有代表性的单位边界。
            workspace = Path(directory) / "workspace"
            source = workspace / "src"
            nested = source / "nested"
            nested.mkdir(parents=True)
            (source / "empty.bin").write_bytes(b"")
            (source / "small.bin").write_bytes(b"a" * 1536)
            (nested / "large.bin").write_bytes(b"b" * 1048576)

            # Relative output must remain directly usable with the same PWD.
            # 相对输出必须可以直接与同一个 PWD 配合使用。
            result = self.call_list({"PWD": str(workspace), "path": "src", "pattern": "*.bin"})
            self.assertIn("[FileList:src Pattern:*.bin", result)
            self.assertIn("[D] src/", result)
            self.assertIn("[F] src/empty.bin (0 B)", result)
            self.assertIn("[F] src/small.bin (1.5 KB)", result)
            self.assertIn("[D] src/nested/", result)
            self.assertIn("[F] src/nested/large.bin (1 MB)", result)
            self.assertNotIn(str(workspace), result)

    def test_implicit_pwd_and_absolute_query_use_distinct_output_roots(self) -> None:
        """Check PWD-only scans and preserve absolute-query behavior.
        检查仅使用 PWD 的扫描，并保留绝对路径查询行为。

        Returns:
            None: Assertions verify the header and file paths in both modes.
        返回值：
            None：断言验证两种模式的标题和文件路径。
        """
        with tempfile.TemporaryDirectory(prefix="vulcan-file-list-fixture-") as directory:
            # Keep one root file and one child file to expose the display base.
            # 分别设置根文件和子文件，以便检验展示基准。
            workspace = Path(directory) / "workspace"
            source = workspace / "src"
            source.mkdir(parents=True)
            (workspace / "root.txt").write_bytes(b"x")
            (source / "child.txt").write_bytes(b"y")

            # Omitting path means the PWD itself is the relative scan root.
            # 省略 path 时，PWD 自身就是相对扫描根目录。
            implicit_result = self.call_list({"PWD": str(workspace), "recursive": False})
            self.assertIn("[FileList:. Pattern:*", implicit_result)
            self.assertIn("[D] ./", implicit_result)
            self.assertIn("[F] root.txt (1 B)", implicit_result)

            # An explicit absolute query keeps the scan directory as its base.
            # 显式绝对路径查询仍以扫描目录作为展示基准。
            absolute_result = self.call_list({"PWD": str(workspace), "path": str(source)})
            self.assertIn(f"[FileList:{source} Pattern:*", absolute_result)
            self.assertIn("[D] ./", absolute_result)
            self.assertIn("[F] child.txt (1 B)", absolute_result)
            self.assertNotIn("[F] src/child.txt", absolute_result)


if __name__ == "__main__":
    unittest.main()
