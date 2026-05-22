"""
Validate tool usage contract text and runtime guardrails.
校验工具使用契约文本与运行时保护逻辑。
"""

from __future__ import annotations

from pathlib import Path


"""
Return the repository root for contract fixture reads.
返回用于读取契约夹具的仓库根目录。

Returns:
    Path: Absolute repository root path.
返回值：
    Path：仓库根目录的绝对路径。
"""
def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


"""
Read one repository file as UTF-8 text.
以 UTF-8 文本读取一个仓库文件。

Parameters:
    relative_path: File path relative to the repository root.
参数：
    relative_path：相对于仓库根目录的文件路径。

Returns:
    str: File content.
返回值：
    str：文件内容。
"""
def read_text(relative_path: str) -> str:
    return (repo_root() / relative_path).read_text(encoding="utf-8")


"""
Assert that a text block contains one required fragment.
断言文本块包含一个必需片段。

Parameters:
    text: Source text to inspect.
    fragment: Required fragment that must appear in the source text.
参数：
    text：需要检查的源文本。
    fragment：必须出现在源文本中的必需片段。

Returns:
    None: Raises AssertionError when the fragment is missing.
返回值：
    None：缺少片段时抛出 AssertionError。
"""
def assert_contains(text: str, fragment: str) -> None:
    if fragment not in text:
        raise AssertionError(f"Missing required fragment: {fragment}")


"""
Validate the manifest-level public tool contract.
校验清单层面的公开工具契约。

Returns:
    None: Raises AssertionError on contract drift.
返回值：
    None：契约漂移时抛出 AssertionError。
"""
def test_skill_manifest_contract() -> None:
    skill_yaml = read_text("skill.yaml")
    assert_contains(skill_yaml, "version: 0.1.3")
    assert_contains(skill_yaml, "input_schema_file: schemas/read.input.schema.json")
    assert_contains(skill_yaml, "input_schema_file: schemas/list.input.schema.json")
    assert_contains(skill_yaml, "input_schema_file: schemas/edit.input.schema.json")

    read_schema = read_text("schemas/read.input.schema.json")
    assert_contains(read_schema, '"segments"')
    assert_contains(read_schema, '"type": "array"')
    assert_contains(read_schema, '"lines_rule"')


"""
Validate runtime guardrails for ambiguous arguments.
校验歧义参数的运行时保护逻辑。

Returns:
    None: Raises AssertionError on missing guardrails.
返回值：
    None：缺少保护逻辑时抛出 AssertionError。
"""
def test_runtime_guardrails() -> None:
    read_runtime = read_text("runtime/vulcan-file-read.lua")
    list_runtime = read_text("runtime/vulcan-file-list.lua")
    edit_runtime = read_text("runtime/vulcan-file-edit.lua")

    assert_contains(read_runtime, "literal word newline")
    assert_contains(read_runtime, "5,10\\\\n25,30")
    assert_contains(read_runtime, "segments and lines_rule cannot be provided together")
    assert_contains(read_runtime, "segments must be an array of {start, count} objects")
    assert_contains(list_runtime, "validate_basename_pattern")
    assert_contains(list_runtime, "pattern must be a basename-only glob")
    assert_contains(edit_runtime, "line_out_of_bounds")
    assert_contains(edit_runtime, "allowed_range")


"""
Validate user-facing README and help guidance.
校验面向用户的 README 与 help 指引。

Returns:
    None: Raises AssertionError on missing guidance.
返回值：
    None：缺少指引时抛出 AssertionError。
"""
def test_documentation_guidance() -> None:
    docs = "\n".join(
        [
            read_text("README.md"),
            read_text("README.zh-CN.md"),
            read_text("help/read.md"),
            read_text("help/list.md"),
            read_text("help/edit.md"),
        ]
    )

    assert_contains(docs, '"segments": [')
    assert_contains(docs, '{ "start": 5, "count": 10 }')
    assert_contains(docs, '"lines_rule": "5,10\\n25,30"')
    assert_contains(docs, "legacy fallback")
    assert_contains(docs, "旧版兼容")
    assert_contains(docs, 'not the literal word `"newline"`')
    assert_contains(docs, "不是字面字符串")
    assert_contains(docs, "src/*.lua")
    assert_contains(docs, "not a full Git ignore engine")
    assert_contains(docs, "默认 200 行")
    assert_contains(docs, "唯一允许在文件不存在时创建新文件")
    assert_contains(docs, "line_out_of_bounds")


"""
Run all contract tests without requiring pytest.
运行全部契约测试且不要求安装 pytest。

Returns:
    None: Raises AssertionError on any failed contract check.
返回值：
    None：任意契约检查失败时抛出 AssertionError。
"""
def main() -> None:
    test_skill_manifest_contract()
    test_runtime_guardrails()
    test_documentation_guidance()


if __name__ == "__main__":
    main()
