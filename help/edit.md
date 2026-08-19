# `vulcan-file-edit`

Use this tool when one existing file has one or more confirmed text changes. Read the target file first with `vulcan-file-read` and copy the complete original text for every edit node.

The request edits exactly one file. Multiple positions in that file belong in one `nodes` array so the runtime can preserve the original line coordinates and calculate later offsets.

## Request shape

```json
{
  "PWD": "/workspace/project",
  "file": "src/example.rs",
  "line_tolerance": 0,
  "no_apply": false,
  "nodes": [
    {
      "id": "replace-guard",
      "type": "edit",
      "start_line": 20,
      "end_line": 24,
      "old_content": "the complete original five lines",
      "new_content": "the replacement lines"
    },
    {
      "id": "append-helper",
      "type": "append",
      "new_content": "text added at the final file end"
    }
  ]
}
```

`PWD` remains the optional project root for relative file paths. `no_apply=true` runs the full preview and validation flow without writing. It applies to the whole request.

`line_tolerance` is an optional non-negative number of logical lines used when the supplied line numbers may be stale. It defaults to `0`, which requires the unique `old_content` block to match the declared `start_line`/`end_line` exactly. When it is greater than `0`, the runtime expands that range upward and downward by the given number of lines and accepts the edit only when the complete, globally unique `old_content` match fits inside the expanded range. For example, `line_tolerance=50` permits a match within 50 lines above or below the declared range.

## Node rules

- Every node needs a unique `id`.
- An `edit` node uses the original file's 1-based inclusive `start_line` and `end_line`.
- `old_content` must contain the complete original logical-line block, not only the word being changed.
- The old block must occur exactly once in the original file. With the default `line_tolerance=0`, it must match the declared original range; with a positive tolerance, its complete range may be inside the expanded search range.
- `new_content` replaces the range. An empty `new_content` deletes the range.
- An `append` node has only `id`, `type`, and non-empty `new_content`. It runs after all edit nodes and also works for an empty file.
- Edit nodes are sorted by original start line before execution. Append nodes stay after edits in their request order.
- Adjacent ranges are valid. Overlapping edit ranges reject the complete request before any write.
- When a node's content does not match or is not unique, successful earlier nodes are committed as a prefix; the failed and later nodes are not executed.
- Final JSON validation runs before a complete write. If it fails, the file remains unchanged.

## Insert migration

The old `insert_before` and `insert_after` modes are no longer accepted. Express them as a one-line `edit`:

- Insert before an anchor: `old_content` is the anchor line; `new_content` is the inserted text, a newline, and the original anchor line.
- Insert after an anchor: `old_content` is the anchor line; `new_content` is the original anchor line, a newline, and the inserted text.
- Empty files have no anchor; use `append`.

## Results and failure recovery

Results list nodes in original-line order and show both `original_range` and the final actual range. If earlier nodes changed line counts, the result explicitly lists the source node ids, each `delta`, and the cumulative shift. A tolerant match also reports the declared range, the actual matched original range, and the configured tolerance.

Multi-node previews label deleted lines with `[original]` coordinates and context or inserted lines with `[final]` coordinates. Host `change_set` hunks use original content for deletion and final content for before/after context.

Node-level failures report:

- committed prefix nodes with their final ranges and deltas, or staged prefix nodes when the request was preview-only;
- the failed node, its mapped current range, and the actual content currently at that range;
- later nodes that were not executed and their mapped ranges when available;
- `commit_scope` as `none`, `prefix`, or `all`.
- Internal staging failures use `commit_scope=none` and never write a successful prefix. Write failures report that disk state is uncertain; re-read the file before retrying.

After a prefix commit, re-read the file before retrying remaining edits. Do not reuse the old line numbers or old content without checking the new disk state.

Final JSON validation failures keep a single-line decoder detail; nested Markdown and stack traces are not returned inside `detail`.

The optional host `change_set` result is preserved. It contains one file record with one hunk per applied or previewed node, and hunk line numbers refer to the final staged or committed content. For a tolerant edit, the hunk keeps the declared `original_range` and also reports the actual `matched_original_range` plus `match_mode`.

Use `vulcan-codekit-patch` for whole-function or whole-method replacement when structural source understanding is required.
