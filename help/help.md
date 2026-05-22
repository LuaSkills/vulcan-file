# Vulcan File

Use `vulcan-file` when you need to work with raw file contents directly instead of understanding code structure or searching text.

Prefer these choices:

- Need to create one brand-new file: use `vulcan-file-create`, preview first, then set `apply=true`.
- Already know the file path and approximate lines: use `vulcan-file-read`.
- Do not know where the target file is yet: use `vulcan-file-list` first to get one low-token file map.
- Need one small text change: use `vulcan-file-edit`, preview first, then set `apply=true`.

Avoid these choices:

- Do not guess line numbers with `vulcan-file-read` when text search or anchor discovery is needed; use `vulcan-codekit-rg` first.
- Prefer `vulcan-codekit` when you need functions, classes, or source structure.
- Use `vulcan-codekit-patch` for whole-function or whole-method replacement.
- Do not force large refactors through text-only edits before reading structural context.
