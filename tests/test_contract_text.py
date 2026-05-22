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
Assert that one text block does not contain CJK ideographs.
断言一个文本块不包含中日韩统一表意文字。

Parameters:
    text: Source text to inspect.
    label: Human-readable file or block label for failure output.
参数：
    text：需要检查的源文本。
    label：失败输出中使用的人类可读文件或文本块标签。

Returns:
    None: Raises AssertionError when any CJK ideograph is found.
返回值：
    None：发现任意中日韩统一表意文字时抛出 AssertionError。
"""
def assert_no_cjk(text: str, label: str) -> None:
    for char in text:
        if "\u4e00" <= char <= "\u9fff":
            raise AssertionError(f"Help text must stay English-only: {label}")


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
    assert_contains(skill_yaml, "version: 0.1.8")
    assert_contains(skill_yaml, "input_schema_file: schemas/create.input.schema.json")
    assert_contains(skill_yaml, "input_schema_file: schemas/read.input.schema.json")
    assert_contains(skill_yaml, "input_schema_file: schemas/list.input.schema.json")
    assert_contains(skill_yaml, "input_schema_file: schemas/edit.input.schema.json")
    assert_contains(skill_yaml, "input_schema_file: schemas/delete.input.schema.json")

    create_schema = read_text("schemas/create.input.schema.json")
    assert_contains(create_schema, '"PWD"')
    assert_contains(create_schema, '"content"')
    assert_contains(create_schema, '"apply"')
    assert_contains(create_schema, '"files"')
    assert_contains(create_schema, '"maxItems": 10')

    read_schema = read_text("schemas/read.input.schema.json")
    assert_contains(read_schema, '"PWD"')
    assert_contains(read_schema, '"segments"')
    assert_contains(read_schema, '"type": "array"')
    assert_contains(read_schema, '"lines_rule"')
    assert_contains(read_schema, '"files"')
    assert_contains(read_schema, '"maxItems": 10')

    list_schema = read_text("schemas/list.input.schema.json")
    assert_contains(list_schema, '"PWD"')

    edit_schema = read_text("schemas/edit.input.schema.json")
    assert_contains(edit_schema, '"PWD"')
    assert_contains(edit_schema, '"files"')
    assert_contains(edit_schema, '"maxItems": 10')

    delete_schema = read_text("schemas/delete.input.schema.json")
    assert_contains(delete_schema, '"PWD"')
    assert_contains(delete_schema, '"files"')
    assert_contains(delete_schema, '"maxItems": 10')
    assert_contains(delete_schema, 'Directory paths are rejected')


"""
Validate runtime guardrails for ambiguous arguments.
校验歧义参数的运行时保护逻辑。

Returns:
    None: Raises AssertionError on missing guardrails.
返回值：
    None：缺少保护逻辑时抛出 AssertionError。
"""
def test_runtime_guardrails() -> None:
    create_runtime = read_text("runtime/vulcan-file-create.lua")
    read_runtime = read_text("runtime/vulcan-file-read.lua")
    list_runtime = read_text("runtime/vulcan-file-list.lua")
    edit_runtime = read_text("runtime/vulcan-file-edit.lua")
    delete_runtime = read_text("runtime/vulcan-file-delete.lua")
    shared_runtime = read_text("runtime/shared_file.lua")

    assert_contains(read_runtime, "literal word newline")
    assert_contains(read_runtime, "5,10\\\\n25,30")
    assert_contains(read_runtime, "segments and lines_rule cannot be provided together")
    assert_contains(read_runtime, "segments must be an array of {start, count} objects")
    assert_contains(read_runtime, "conflicting_batch_arguments")
    assert_contains(read_runtime, "BatchFileRead Files:")
    assert_contains(list_runtime, "validate_basename_pattern")
    assert_contains(list_runtime, "pattern must be a basename-only glob")
    assert_contains(list_runtime, "relative_path_requires_pwd")
    assert_contains(edit_runtime, "line_out_of_bounds")
    assert_contains(edit_runtime, "conflicting_batch_arguments")
    assert_contains(edit_runtime, "invalid_pwd_argument")
    assert_contains(create_runtime, "file_already_exists")
    assert_contains(create_runtime, "parent_directory_not_found")
    assert_contains(create_runtime, "conflicting_batch_arguments")
    assert_contains(create_runtime, "invalid_pwd_argument")
    assert_contains(delete_runtime, "directory delete is not supported")
    assert_contains(delete_runtime, "directory_delete_unsupported")
    assert_contains(delete_runtime, "invalid_pwd_argument")
    assert_contains(shared_runtime, 'kind = "change_set"')
    assert_contains(shared_runtime, "allows_change_set")
    assert_contains(shared_runtime, "max_payload_bytes")
    assert_contains(shared_runtime, "MAX_BATCH_FILES = 10")
    assert_contains(shared_runtime, 'BINARY_FILE_PLACEHOLDER = "Binary file"')
    assert_contains(shared_runtime, "DELETE_TRUNCATE_LINE_LIMIT = 500")
    assert_contains(shared_runtime, "DELETE_TRUNCATED_EDGE_LINE_COUNT = 50")
    assert_contains(shared_runtime, "build_delete_file_record")
    assert_contains(shared_runtime, 'content_mode = "truncated"')
    assert_contains(shared_runtime, 'type(vulcan.fs.rename) == "function"')
    assert_contains(shared_runtime, 'type(vulcan.fs.remove) == "function"')
    assert_contains(shared_runtime, "translate_windows_device_path")
    assert_contains(shared_runtime, "resolve_pwd_root")
    assert_contains(shared_runtime, "relative_path_requires_pwd")
    assert_contains(shared_runtime, "PWD must be an absolute directory path")


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
            read_text("help/create.md"),
            read_text("help/read.md"),
            read_text("help/list.md"),
            read_text("help/edit.md"),
            read_text("help/delete.md"),
        ]
    )

    assert_contains(docs, '"segments": [')
    assert_contains(docs, '"files": [')
    assert_contains(docs, '{ "start": 5, "count": 10 }')
    assert_contains(docs, '"lines_rule": "5,10\\n25,30"')
    assert_contains(docs, "legacy fallback")
    assert_contains(docs, "旧版兼容")
    assert_contains(docs, 'not the literal word `"newline"`')
    assert_contains(docs, "不是字面字符串")
    assert_contains(docs, "src/*.lua")
    assert_contains(docs, "not a full Git ignore engine")
    assert_contains(docs, "默认 200 行")
    assert_contains(docs, "vulcan-file-create")
    assert_contains(docs, "vulcan-file-delete")
    assert_contains(docs, "file_already_exists")
    assert_contains(docs, "parent_directory_not_found")
    assert_contains(docs, "line_out_of_bounds")
    assert_contains(docs, "directory_delete_unsupported")
    assert_contains(docs, "Binary file")
    assert_contains(docs, 'content_mode="truncated"')
    assert_contains(docs, "content_head")
    assert_contains(docs, "content_tail")
    assert_contains(docs, "500")
    assert_contains(docs, "50")
    assert_contains(docs, "up to 10")
    assert_contains(docs, "最多 10")
    assert_contains(docs, "PWD")
    assert_contains(docs, "must already be absolute")
    assert_contains(docs, "必须本身就是绝对路径")


"""
Validate that all help markdown files stay English-only.
校验所有 help Markdown 文件保持纯英文。

Returns:
    None: Raises AssertionError when any help file contains CJK text.
返回值：
    None：任一 help 文件包含中日韩统一表意文字时抛出 AssertionError。
"""
def test_help_markdown_is_english_only() -> None:
    help_files = [
        "help/help.md",
        "help/create.md",
        "help/read.md",
        "help/list.md",
        "help/edit.md",
        "help/delete.md",
    ]
    for relative_path in help_files:
        assert_no_cjk(read_text(relative_path), relative_path)


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
    test_help_markdown_is_english_only()


if __name__ == "__main__":
    main()
