# vulcan-file

AI-native file operations LuaSkill for Vulcan.

Chinese version: [README.zh-CN.md](README.zh-CN.md)

`vulcan-file` gives AI agents a small, predictable file toolkit for everyday repository work. It focuses on the operations agents repeatedly need but often implement with ad-hoc shell snippets: compact file discovery, exact line-numbered reads, and preview-first text edits.

## When To Use

Use `vulcan-file` when an agent needs to work with raw files directly:

- Find candidate files cheaply before reading them.
- Read exact source text after a file and line area are known.
- Read multiple non-adjacent snippets in one call.
- Make small text edits after inspecting the target lines.
- Avoid shell-specific loops for listing, line numbering, range extraction, and simple edits.

Prefer Vulcan CodeKit instead when the task needs AST structure, function/class ownership, regex-to-structure mapping, or whole-function patching.

## Tools

### `vulcan-file-list`

Use this before reading when the target file is not known yet.

It returns a compact directory-grouped file map, supports filename globs, and respects `.gitignore`, `.ignore`, and built-in high-noise directory ignores by default.

Typical use cases:

- Scan a project tree with low token cost.
- Filter candidates by extension, such as `*.rs`, `*.lua`, or `Cargo.*`.
- Avoid scanning generated directories such as `target`, `node_modules`, `output`, `dist`, and `build`.

### `vulcan-file-read`

Use this after the agent already knows the target file and approximate line area.

The main argument is `lines_rule`, a compact `start,count` format:

```text
5,10
25,30
```

This reads 10 lines starting at line 5, then 30 lines starting at line 25. Each segment is rendered with stable line numbers, and requests that run past EOF are clipped clearly.

### `vulcan-file-edit`

Use this for small text edits after the target context has been read.

The tool previews by default and writes only when `apply=true` is passed. Supported modes:

- `overwrite`
- `append`
- `replace_range`
- `insert_before`
- `insert_after`

The result includes the original span, edited span, preview diff, and clear parameter-error feedback when the call shape is wrong.

## Skill Package Layout

```text
vulcan-file/
├─ skill.yaml
├─ dependencies.yaml
├─ README.md
├─ README.zh-CN.md
├─ runtime/
│  ├─ vulcan-file-read.lua
│  ├─ vulcan-file-list.lua
│  └─ vulcan-file-edit.lua
├─ help/
│  ├─ help.md
│  ├─ read.md
│  ├─ list.md
│  └─ edit.md
├─ overflow_templates/
├─ resources/
├─ licenses/
├─ scripts/
└─ .github/workflows/
```

## Validation

Local validation:

```powershell
python .\scripts\validate_skill.py
python .\scripts\package_skill.py
```

The packaging script generates release artifacts under `dist/`:

- `vulcan-file-v<version>-skill.zip`
- `vulcan-file-v<version>-checksums.txt`

Optional source metadata:

```powershell
python .\scripts\package_skill.py --emit-source-yaml
```

The generated metadata points to the matching `LuaSkills/vulcan-file` GitHub release assets unless `--base-url` is provided.

## Release Flow

Releases are tag-driven. A pushed tag matching `v*` triggers the release workflow, and the tag must match `skill.yaml.version`.

Recommended local release steps:

```powershell
python .\scripts\validate_skill.py
python .\scripts\package_skill.py
.\scripts\tag_release.ps1 0.1.0
```

Or on Unix-like shells:

```bash
python ./scripts/validate_skill.py
python ./scripts/package_skill.py
./scripts/tag_release.sh 0.1.0
```

## Notes

- The repository root is the skill root.
- The installed skill id is derived from the package root directory name: `vulcan-file`.
- Runtime code has no external tool dependency.
- Runtime output is designed for AI agents: compact, line-stable, and explicit about parameter mistakes.
