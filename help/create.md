# `vulcan-file-create`

Use this tool when you want to create one file that does not exist yet and you want a preview before writing it.

Good fits:

- The target file does not exist yet.
- The full target path and full file content are already known.
- You want a clear separation between creating a new file and editing an existing one.
- The host should receive one structured `change_set` create record when supported.
- The `file` path may use `${env:NAME}` placeholders.

Not a good fit:

- The target file already exists; use `vulcan-file-edit` instead.
- You only need to append or replace a small amount of text in one existing file; use `vulcan-file-edit` instead.
- You do not know where the file should be created yet; use `vulcan-file-list` or another search tool first.

`apply=false` by default, so the tool returns only a preview. The file is written only when `apply=true` is passed explicitly.

Boundary behavior:

- Existing targets return `file_already_exists`; they are never overwritten silently.
- Missing parent directories return `parent_directory_not_found`.
- Parent paths that exist but are not directories return `parent_path_not_directory`.
- `content=""` is valid and creates an empty file.
- The preview shows at most 80 lines of context; larger previews are marked with `preview truncated`.
