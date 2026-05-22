# `vulcan-file-read`

当你已经知道目标文件路径和大致行号，需要查看精确原文时，使用这个工具。

适合使用：

- 已经通过 `vulcan-file-list` 或 `vulcan-codekit-rg` 找到了候选文件。
- 需要确认某个行号附近的原文。
- 需要一次读取多个不相邻片段来对比上下文。
- 只想快速查看目录直接子项名称时，也可以把 `file` 传为目录路径。

不适合使用：

- 还不知道文本在哪里时，不要用这个工具逐页猜，先用 `vulcan-codekit-rg` 搜索。
- 需要源码结构、函数边界或类信息时，优先用 `vulcan-codekit`。
- 需要递归找文件时，使用 `vulcan-file-list`。

参数选择：

- `file`：传已经选定的文件路径；目录路径只用于快速查看直接子项名称；支持 `${env:NAME}` 环境变量占位符。
- `segments`：优先使用这个结构化数组参数；每项都使用 `{ "start": 起始行, "count": 行数 }`；不传时读取文件开头，行数来自宿主 `file_read` 预算，未提供预算时默认 200 行。
- `lines_rule`：旧版兼容参数，仅用于不能发送数组参数的客户端；格式仍然是 `start,count`，并使用字符串里的 `\n` 分隔多段规则；不要与 `segments` 同时传。
- `numbered`：默认保留行号，后续需要引用或编辑时保持默认即可；设为 `false` 只移除 `L<number>:` 行前缀，不移除文件头或多段分隔线。

推荐的结构化数组写法：

```json
{
  "file": "src/example.lua",
  "segments": [
    { "start": 5, "count": 10 },
    { "start": 25, "count": 30 }
  ]
}
```

旧版 `lines_rule` 的格式固定为：

```text
start,count
```

多段读取时每行一个规则：

```text
5,10
25,30
```

在 JSON 参数中，多段规则必须使用字符串里的换行转义 `\n`：

```json
{
  "file": "src/example.lua",
  "lines_rule": "5,10\n25,30"
}
```

这里的分隔符是真实换行符，不是字面字符串 `"newline"`。`segments` 与 `lines_rule` 不能同时传；如果客户端支持数组 schema，应优先使用 `segments`。

边界行为：

- `segments` 必须是非空数组，且每项都要同时提供正整数 `start` 与 `count`。
- `start` 与 `count` 必须是正整数。
- `start` 超过文件总行数时返回 `range_out_of_bounds`。
- `count` 超过文件尾部时自动截到 EOF，并在 header 中标记 `Clipped:true`。
- 多段重叠时不会合并，按请求顺序原样输出。
- 字面字符串 `"newline"` 会返回 `invalid_lines_rule`，需要改为 JSON 字符串中的 `\n`。
- 同时传 `segments` 与 `lines_rule` 会返回 `conflicting_range_arguments`。

返回内容会包含文件路径、总行数、字节数、换行风格、展示行范围、片段数量和是否截断到 EOF。
目录读取会返回目录路径、条目数量和 `Name` 单列列表。
