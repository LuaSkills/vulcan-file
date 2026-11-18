---
name: file-workflow
description: "Use for raw text reads, small edits, and previewing file changes before writing or deleting."
---

# Vulcan File

Use `vulcan-file` when you need to work with raw file contents directly instead of understanding code structure or searching text.

Prefer these choices:

- Need to create one brand-new file or a small batch of brand-new files: use `vulcan_file_create`; pass `no_apply=true` only when you need a preview without writing.
- Already know the file path and approximate lines: use `vulcan_file_read`.
- Do not know where the target file is yet: use `vulcan_file_list` first to get one low-token file map.
- Need one small text change or a few coordinated text changes: use `vulcan_file_edit`; pass `no_apply=true` only when you need a preview without writing.
- Need to remove regular files and the host should receive delete metadata: use `vulcan_file_delete`; pass `no_apply=true` only when you need a preview without deleting.
- If the host or caller provides root-level `PWD`, relative `file` or `path` values resolve from that directory. Without a valid `PWD`, pass absolute paths.

Batch limits:

- `create`, `read`, and `delete` accept either one root-level file request or one `files` array.
- Those batch modes support at most 10 items per call.
- `vulcan_file_edit` accepts one file and up to 50 nodes; use its `nodes` array for multiple positions in that file.
- `no_apply` is shared by the whole request.

Avoid these choices:

- Do not guess line numbers with `vulcan_file_read` when text search or anchor discovery is needed; use `vulcan_codekit_rg` first.
- Prefer `vulcan-codekit` when you need functions, classes, or source structure.
- Use `vulcan_codekit_patch` for whole-function or whole-method replacement.
- Do not force large refactors through text-only edits before reading structural context.
- `vulcan_file_delete` does not support directory removal; pass only regular files.

## References

- [create](references/create.md)
- [delete](references/delete.md)
- [edit](references/edit.md)
- [list](references/list.md)
- [read](references/read.md)
