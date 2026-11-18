# `vulcan_file_list`

Use this tool when you do not know where the target file is yet, or when you need to narrow the candidate file set first.

Good fits:

- You want one low-token file-name map before entering an unfamiliar directory.
- You already know the extension or filename shape and want to filter candidates quickly.
- You want to avoid ad hoc shell loops, sorting, or ignore-rule handling.

Not a good fit:

- Use `vulcan_codekit_rg` when you need to search file contents.
- Use `vulcan-codekit` when you need functions, classes, Markdown headings, or other structure.
- Use `vulcan_file_read` directly when the exact file and line area are already known.

Parameter choices:

- `PWD`: optional shared project or workspace root. When it points to an existing directory, relative `path` values resolve from that root and omitting `path` starts the scan from `PWD`. For those queries, the header and listed paths are relative to `PWD`.
- `path`: pass the narrowest plausible directory; `${env:NAME}` placeholders are supported. Without a valid `PWD`, this path must already be absolute.
- `pattern`: when the extension or filename shape is known, pass one basename-only glob such as `*.rs`, `*.lua`, or `Cargo.*`; it matches only the filename, not the relative path, so do not pass `src/*.lua` or `**/*.md`; use `path` to narrow directories.
- `recursive`: recursive by default; set `false` when you only want direct children.
- `noignore`: set `true` only when ignored or generated files are intentionally needed; it disables both `.gitignore` / `.ignore` file rules and built-in high-noise directory skips.
- `limit`: raise it only when the result is truncated and you still need more candidates; the default is 1000 and the maximum is 100000.

Output marks directories with `[D]` and files with `[F]`. Every file includes its path and size; sizes use 1024-based B, KB, MB, or GB units. A non-regular entry with no size metadata shows `size unavailable`. With `PWD=/workspace/project` and `path=src`, output is relative to `PWD`:

```text
[FileList:src Pattern:* Recursive:true Ignore:true Files:2 Truncated:false Ignored:0]
[D] src/
[F] src/main.rs (1.5 KB)
[D] src/discover/
[F] src/discover/mod.rs (820 B)
```

By default, the tool reads a common subset of `.gitignore` and `.ignore` rules in each directory and skips built-in high-noise directories such as `.git`, `target`, `node_modules`, `output`, `dist`, and `build`. It is not a full Git ignore engine; complex escapes and some advanced negation cases are not guaranteed to match Git exactly.
