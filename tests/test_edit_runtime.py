"""Exercise the real Lua runtime contract for single-file multi-node edits.
通过真实 Lua 运行时验证单文件多节点编辑契约。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class EditRuntimeTests(unittest.TestCase):
    """Run focused end-to-end checks against the bundled debug runtime.
    通过打包的调试运行时执行聚焦的端到端检查。
    """

    @classmethod
    def setUpClass(cls) -> None:
        """Locate the bundled runtime executable or skip unavailable integration checks.
        定位打包的运行时可执行文件，不可用时跳过集成检查。
        """
        cls.root = Path(__file__).resolve().parent.parent
        cls.debug_root = cls.root.parent / "luaskills-debug"
        cls.executable = cls.debug_root / "bin" / "luaskills-debug.exe"
        if not cls.executable.is_file():
            raise unittest.SkipTest("bundled luaskills-debug.exe is not available")
        cls.runtime_directory = tempfile.TemporaryDirectory(prefix="vulcan-file-runtime-")
        cls.isolated_runtime = Path(cls.runtime_directory.name) / "runtime"
        shutil.copytree(
            cls.debug_root / "runtime",
            cls.isolated_runtime,
            ignore=shutil.ignore_patterns(".git"),
        )
        cls.addClassCleanup(cls.runtime_directory.cleanup)

    @classmethod
    def call_edit(cls, arguments: dict, enable_host_result: bool = False) -> str | tuple[str, dict | None]:
        """Invoke the edit tool and return its rendered Markdown result.
        调用 edit 工具并返回渲染后的 Markdown 结果。

        Parameters:
            arguments: JSON-compatible edit request.
            arguments：可序列化为 JSON 的 edit 请求。
            enable_host_result: Whether to request the structured host projection.
            enable_host_result：是否请求宿主结构化结果投影。

        Returns:
            str | tuple[str, dict | None]: Rendered content, optionally paired with the host result.
            str | tuple[str, dict | None]：渲染内容，可选地附带宿主结果。
        """
        # Serialize once so oversized requests can use the file-based CLI transport.
        # 只序列化一次，使超大请求可以改用基于文件的 CLI 传输。
        serialized_arguments = json.dumps(arguments, ensure_ascii=False, separators=(",", ":"))
        command = [
            str(cls.executable),
            "call",
            "--runtime-root",
            str(cls.isolated_runtime),
            "--skill-path",
            ".",
            "--tool",
            "edit",
        ]
        # Keep a temporary argument-file path for cleanup after the subprocess exits.
        # 保存临时参数文件路径，确保子进程退出后能够清理。
        arguments_file: Path | None = None
        if len(serialized_arguments.encode("utf-8")) > 30000:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                suffix=".json",
                delete=False,
            ) as handle:
                handle.write(serialized_arguments)
                arguments_file = Path(handle.name)
            command.extend(["--args-file", str(arguments_file)])
        else:
            command.extend(["--args-json", serialized_arguments])
        if enable_host_result:
            command.append("--enable-host-result")
        command.extend(["--output", "json"])
        try:
            completed = subprocess.run(
                command,
                cwd=cls.root,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
        finally:
            if arguments_file is not None:
                arguments_file.unlink(missing_ok=True)
        if completed.returncode != 0:
            raise AssertionError(
                f"debug runtime failed with code {completed.returncode}: "
                f"{completed.stdout}\n{completed.stderr}"
            )
        envelope = json.loads(completed.stdout)
        result = envelope["result"]
        if enable_host_result:
            return result["content"], result.get("host_result")
        return result["content"]

    @staticmethod
    def write_file(path: Path, content: str) -> None:
        """Write one UTF-8 fixture using the requested logical file content.
        按请求中的逻辑文件内容写入一个 UTF-8 测试文件。
        """
        path.write_text(content, encoding="utf-8", newline="")

    def test_multi_node_preview_reports_final_ranges_and_shifts(self) -> None:
        """Verify original coordinates map to sorted final ranges in preview output.
        验证预览结果会把原始坐标映射为排序后的最终范围。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            self.write_file(path, "alpha\nbeta\ngamma\ndelta\nepsilon\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "no_apply": True,
                    "nodes": [
                        {
                            "id": "first",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "beta-1\nbeta-2",
                        },
                        {
                            "id": "later",
                            "type": "edit",
                            "start_line": 5,
                            "end_line": 5,
                            "old_content": "epsilon",
                            "new_content": "epsilon-new",
                        },
                        {"id": "tail", "type": "append", "new_content": "zeta"},
                    ],
                }
            )
            self.assertIn("first", content)
            self.assertIn("original `L2-L2` -> final `L2-L3`", content)
            self.assertIn("later", content)
            self.assertIn("original `L5-L5` -> final `L6-L6`", content)
            self.assertIn("shift:", content)
            later_preview = content.split("## Preview later", 1)[1].split("## Preview tail", 1)[0]
            self.assertIn(" L3 [final]: beta-2", later_preview)
            self.assertIn(" L5 [final]: delta", later_preview)
            self.assertIn("-L5 [original]: epsilon", later_preview)
            self.assertIn("+L6 [final]: epsilon-new", later_preview)
            self.assertNotIn(" L2: beta", later_preview)
            tail_preview = content.split("## Preview tail", 1)[1]
            self.assertIn(" L6 [final]: epsilon-new", tail_preview)
            self.assertNotIn(" L5 [final]: epsilon", tail_preview)
            self.assertEqual(path.read_text(encoding="utf-8"), "alpha\nbeta\ngamma\ndelta\nepsilon\n")

    def test_overlap_rejects_request_without_write(self) -> None:
        """Verify overlapping edit ranges reject the whole request before writing.
        验证重叠编辑范围会在写盘前拒绝整个请求。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            original = "alpha\nbeta\ngamma\ndelta\n"
            self.write_file(path, original)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "left",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 3,
                            "old_content": "beta\ngamma",
                            "new_content": "changed",
                        },
                        {
                            "id": "right",
                            "type": "edit",
                            "start_line": 3,
                            "end_line": 4,
                            "old_content": "gamma\ndelta",
                            "new_content": "changed-too",
                        },
                    ],
                }
            )
            self.assertIn("overlapping_nodes", content)
            self.assertIn("commit_scope: `none`", content)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_host_change_set_contains_final_ranges_for_each_node(self) -> None:
        """Verify the structured host projection retains one hunk per final node range.
        验证结构化宿主投影会为每个节点保留一个对应最终范围的 hunk。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            self.write_file(path, "alpha\nbeta\ngamma\ndelta\nepsilon\n")
            content, host_result = self.call_edit(
                {
                    "file": str(path),
                    "no_apply": True,
                    "nodes": [
                        {
                            "id": "first",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "beta-1\nbeta-2",
                        },
                        {
                            "id": "later",
                            "type": "edit",
                            "start_line": 5,
                            "end_line": 5,
                            "old_content": "epsilon",
                            "new_content": "epsilon-new",
                        },
                        {"id": "tail", "type": "append", "new_content": "zeta"},
                    ],
                },
                enable_host_result=True,
            )
            self.assertIn("PREVIEW_ONLY", content)
            self.assertIsNotNone(host_result)
            assert host_result is not None
            self.assertEqual(host_result["kind"], "change_set")
            hunks = host_result["payload"]["files"][0]["hunks"]
            self.assertEqual([hunk["node_id"] for hunk in hunks], ["first", "later", "tail"])
            self.assertEqual([hunk["final_range"] for hunk in hunks], ["L2-L3", "L6-L6", "L7-L7"])
            self.assertEqual(hunks[0]["before"], "alpha")
            self.assertEqual(hunks[1]["before"], "beta-2\ngamma\ndelta")
            self.assertEqual(hunks[1]["after"], "zeta")
            self.assertEqual(hunks[2]["before"], "gamma\ndelta\nepsilon-new")
            self.assertEqual(path.read_text(encoding="utf-8"), "alpha\nbeta\ngamma\ndelta\nepsilon\n")

    def test_node_failure_commits_only_successful_prefix(self) -> None:
        """Verify a node failure commits the successful prefix and skips later nodes.
        验证节点失败时只提交成功前缀并跳过后续节点。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            self.write_file(path, "alpha\nbeta\ngamma\ndelta\ndelta\nepsilon\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "prefix",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "beta-1\nbeta-2",
                        },
                        {
                            "id": "broken",
                            "type": "edit",
                            "start_line": 4,
                            "end_line": 4,
                            "old_content": "delta",
                            "new_content": "delta-new",
                        },
                        {
                            "id": "skipped",
                            "type": "edit",
                            "start_line": 5,
                            "end_line": 5,
                            "old_content": "epsilon",
                            "new_content": "epsilon-new",
                        },
                    ],
                }
            )
            self.assertIn("old_content_not_unique", content)
            self.assertIn("commit_scope: `prefix`", content)
            self.assertIn("prefix", content)
            self.assertIn("skipped", content)
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                "alpha\nbeta-1\nbeta-2\ngamma\ndelta\ndelta\nepsilon\n",
            )

    def test_missing_old_content_is_reported_as_mismatch(self) -> None:
        """Verify an absent old content reports mismatch rather than non-unique content.
        验证原内容不存在时报告不匹配，而不是报告非唯一匹配。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            original = "alpha\nbeta\n"
            self.write_file(path, original)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "missing",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "not-present",
                            "new_content": "changed",
                        }
                    ],
                }
            )
            self.assertIn("old_content_mismatch", content)
            self.assertNotIn("old_content_not_unique", content)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_preview_node_failure_keeps_staged_prefix_off_disk(self) -> None:
        """Verify no_apply simulates a prefix but never writes it after a later failure.
        验证 no_apply 会模拟成功前缀，但后续失败时绝不把前缀写入磁盘。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            original = "alpha\nbeta\ngamma\n"
            self.write_file(path, original)
            content = self.call_edit(
                {
                    "PWD": directory,
                    "file": "sample.txt",
                    "no_apply": True,
                    "nodes": [
                        {
                            "id": "preview-prefix",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "beta-1\nbeta-2",
                        },
                        {
                            "id": "preview-broken",
                            "type": "edit",
                            "start_line": 3,
                            "end_line": 3,
                            "old_content": "not-present",
                            "new_content": "gamma-new",
                        },
                    ],
                }
            )
            self.assertIn("old_content_mismatch", content)
            self.assertIn("commit_scope: `none`", content)
            self.assertIn("committed: `false`", content)
            self.assertIn("committed_prefix_nodes: `none`", content)
            self.assertIn("staged_prefix_nodes:", content)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_invalid_json_final_content_does_not_write(self) -> None:
        """Verify final JSON validation rejects invalid staged content without writing.
        验证最终 JSON 校验失败时不会写入无效暂存内容。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.json"
            original = '{"enabled": true}\n'
            self.write_file(path, original)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "invalid-json",
                            "type": "edit",
                            "start_line": 1,
                            "end_line": 1,
                            "old_content": '{"enabled": true}',
                            "new_content": '{"enabled": }',
                        }
                    ],
                }
            )
            self.assertIn("final_content_validation_failed", content)
            self.assertIn("commit_scope: `none`", content)
            self.assertIn("- detail: `JSON decoder:", content)
            self.assertEqual(content.count("# FILE EDIT ERROR"), 1)
            self.assertNotIn("stack traceback", content.lower())
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_deletion_maps_following_original_node_to_new_range(self) -> None:
        """Verify deletion uses an empty replacement and remaps the following node.
        验证删除通过空替换实现，并把后续节点映射到新的实际范围。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            self.write_file(path, "alpha\nbeta\ngamma\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "remove",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "",
                        },
                        {
                            "id": "following",
                            "type": "edit",
                            "start_line": 3,
                            "end_line": 3,
                            "old_content": "gamma",
                            "new_content": "gamma-new",
                        },
                    ],
                }
            )
            self.assertIn("remove", content)
            self.assertIn("final `none`", content)
            self.assertIn("final_anchor_line: `L2`", content)
            self.assertIn("original `L3-L3` -> final `L2-L2`", content)
            self.assertEqual(path.read_text(encoding="utf-8"), "alpha\ngamma-new\n")

    def test_empty_file_append_writes_content(self) -> None:
        """Verify append is the explicit operation for an empty file.
        验证空文件通过显式 append 操作追加内容。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "empty.txt"
            self.write_file(path, "")
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [{"id": "tail", "type": "append", "new_content": "first"}],
                }
            )
            self.assertIn("tail", content)
            self.assertIn("original `append` -> final `L1-L1`", content)
            self.assertEqual(path.read_text(encoding="utf-8"), "first")

    def test_unknown_root_hash_field_is_rejected(self) -> None:
        """Verify runtime rejects an obsolete root hash field even without schema mediation.
        验证即使绕过 Schema，运行时也会拒绝废弃的根级 hash 字段。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            self.write_file(path, "alpha\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "hash": "obsolete",
                    "nodes": [
                        {
                            "id": "edit",
                            "type": "edit",
                            "start_line": 1,
                            "end_line": 1,
                            "old_content": "alpha",
                            "new_content": "changed",
                        }
                    ],
                }
            )
            self.assertIn("invalid_request", content)
            self.assertIn("unsupported root field", content)
            self.assertEqual(path.read_text(encoding="utf-8"), "alpha\n")

    def test_nodes_must_be_an_array_at_runtime(self) -> None:
        """Verify direct runtime calls reject object-shaped nodes before execution.
        验证绕过 Schema 直接调用运行时时，会在执行前拒绝对象形状的 nodes。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.txt"
            original = "alpha\n"
            self.write_file(path, original)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": {"unexpected": {"type": "append", "new_content": "x"}},
                }
            )
            self.assertIn("invalid_nodes_argument", content)
            self.assertIn("contiguous array", content)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_cr_only_file_preserves_logical_lines_and_newline_style(self) -> None:
        """Verify classic-Mac CR-only files remain line-oriented after editing.
        验证旧 Mac 风格的 CR-only 文件编辑后仍保持逻辑行和换行风格。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cr-only.txt"
            original = b"alpha\rbeta\r"
            path.write_bytes(original)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "replace-beta",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "gamma",
                        }
                    ],
                }
            )
            self.assertIn("APPLIED", content)
            self.assertEqual(path.read_bytes(), b"alpha\rgamma\r")

    def test_crlf_file_preserves_windows_newline_style(self) -> None:
        """Verify CRLF files retain CRLF after a guarded line replacement.
        验证 CRLF 文件经过内容护栏编辑后仍保持 CRLF 换行。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "crlf.txt"
            path.write_bytes(b"alpha\r\nbeta\r\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "replace-beta",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "gamma",
                        }
                    ],
                }
            )
            self.assertIn("APPLIED", content)
            self.assertEqual(path.read_bytes(), b"alpha\r\ngamma\r\n")

    def test_adjacent_edit_nodes_are_valid(self) -> None:
        """Verify adjacent non-overlapping ranges are accepted and applied in order.
        验证相邻但不重叠的范围会被接受，并按顺序应用。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "adjacent.txt"
            self.write_file(path, "alpha\nbeta\ngamma\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "first",
                            "type": "edit",
                            "start_line": 1,
                            "end_line": 1,
                            "old_content": "alpha",
                            "new_content": "alpha-new",
                        },
                        {
                            "id": "second",
                            "type": "edit",
                            "start_line": 2,
                            "end_line": 2,
                            "old_content": "beta",
                            "new_content": "beta-new",
                        },
                    ],
                }
            )
            self.assertIn("APPLIED", content)
            self.assertNotIn("overlapping_nodes", content)
            self.assertEqual(path.read_text(encoding="utf-8"), "alpha-new\nbeta-new\ngamma\n")

    def test_multiple_append_nodes_preserve_request_order(self) -> None:
        """Verify append nodes remain in their input order after edit-node sorting.
        验证 append 节点在编辑节点排序后仍保持请求中的顺序。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "append-order.txt"
            self.write_file(path, "root\n")
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {"id": "second", "type": "append", "new_content": "second"},
                        {"id": "first", "type": "append", "new_content": "first"},
                    ],
                }
            )
            self.assertIn("APPLIED", content)
            self.assertEqual(path.read_text(encoding="utf-8"), "root\nsecond\nfirst")

    def test_non_unique_diagnostic_limits_candidate_ranges(self) -> None:
        """Verify repeated content diagnostics report totals without unbounded output.
        验证重复内容诊断会报告总数，同时避免无上限输出候选范围。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "repeated.txt"
            self.write_file(path, "repeat\n" * 25)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "repeated",
                            "type": "edit",
                            "start_line": 1,
                            "end_line": 1,
                            "old_content": "repeat",
                            "new_content": "changed",
                        }
                    ],
                }
            )
            self.assertIn("old_content_not_unique", content)
            self.assertIn("match_count: `25`", content)
            self.assertIn("candidates_omitted: `5`", content)
            self.assertNotIn("L21-L21", content)

    def test_unique_content_at_wrong_declared_range_reports_actual_range(self) -> None:
        """Verify a unique match outside the declared range is diagnosed precisely.
        验证唯一匹配位置与声明范围不符时会精确报告实际范围。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "wrong-range.txt"
            original = "alpha\nbeta\n"
            self.write_file(path, original)
            content = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "wrong-range",
                            "type": "edit",
                            "start_line": 1,
                            "end_line": 1,
                            "old_content": "beta",
                            "new_content": "changed",
                        }
                    ],
                }
            )
            self.assertIn("old_content_mismatch", content)
            self.assertIn("L2-L2", content)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_duplicate_id_and_append_field_guards_reject_before_write(self) -> None:
        """Verify duplicate IDs and invalid append fields are rejected structurally.
        验证重复 ID 和非法 append 字段会在结构阶段被拒绝。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "shape-guards.txt"
            original = "alpha\n"
            self.write_file(path, original)
            duplicate = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {"id": "same", "type": "append", "new_content": "one"},
                        {"id": "same", "type": "append", "new_content": "two"},
                    ],
                }
            )
            self.assertIn("duplicate_node_id", duplicate)
            invalid_append = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "invalid-append",
                            "type": "append",
                            "start_line": 1,
                            "new_content": "two",
                        }
                    ],
                }
            )
            self.assertIn("invalid_node_fields", invalid_append)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_node_and_content_limits_are_enforced(self) -> None:
        """Verify node-count and request-content byte limits reject before execution.
        验证节点数量和请求内容字节上限会在执行前拒绝请求。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "limits.txt"
            original = "alpha\n"
            self.write_file(path, original)
            too_many = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {"id": f"append-{index}", "type": "append", "new_content": "x"}
                        for index in range(51)
                    ],
                }
            )
            self.assertIn("too_many_nodes", too_many)
            too_large = self.call_edit(
                {
                    "file": str(path),
                    "nodes": [
                        {
                            "id": "too-large",
                            "type": "edit",
                            "start_line": 1,
                            "end_line": 1,
                            "old_content": "alpha",
                            "new_content": "x" * 131072,
                        }
                    ],
                }
            )
            self.assertIn("request_content_too_large", too_large)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

    def test_legacy_files_and_mode_fields_are_rejected(self) -> None:
        """Verify removed batch and mode fields cannot bypass the new contract.
        验证已移除的批量字段和 mode 字段不能绕过新协议。
        """
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "legacy.txt"
            original = "alpha\n"
            self.write_file(path, original)
            files_content = self.call_edit(
                {
                    "file": str(path),
                    "files": [{"file": str(path)}],
                    "nodes": [{"id": "edit", "type": "append", "new_content": "x"}],
                }
            )
            self.assertIn("multiple_files_not_supported", files_content)
            mode_content = self.call_edit(
                {
                    "file": str(path),
                    "mode": "replace_range",
                    "nodes": [{"id": "edit", "type": "append", "new_content": "x"}],
                }
            )
            self.assertIn("invalid_request", mode_content)
            self.assertEqual(path.read_text(encoding="utf-8"), original)

if __name__ == "__main__":
    unittest.main()
