# vulcan-file

面向 Vulcan 的 AI 原生文件操作 LuaSkill。

`vulcan-file` 为 AI Agent 提供一组小而稳定的文件工具，用来替代反复手写的 shell 片段：低 token 文件发现、精确带行号读取，以及默认预览的文本编辑。

## 什么时候使用

当 Agent 需要直接处理原文文件时使用 `vulcan-file`：

- 读取前先低成本查找候选文件。
- 已知道文件与大致行号后读取精确原文。
- 一次读取多个不相邻片段。
- 查看目标上下文后做小范围文本编辑。
- 避免为文件列表、行号、范围读取、简单编辑手写平台相关脚本。

当任务需要 AST 结构、函数/类归属、正则命中到结构的映射，或完整函数替换时，应优先使用 Vulcan CodeKit。

## 工具

### `vulcan-file-list`

当还不知道目标文件时使用。它返回紧凑的按目录分组文件地图，支持文件名 glob，并默认遵守 `.gitignore`、`.ignore` 和内建高噪声目录忽略规则。

### `vulcan-file-read`

当已经知道目标文件和大致行号时使用。核心参数是 `lines_rule`，格式为 `start,count`：

```text
5,10
25,30
```

表示从第 5 行读取 10 行，再从第 25 行读取 30 行。

### `vulcan-file-edit`

当已经读取目标上下文，需要做小范围文本编辑时使用。默认只返回预览，只有传入 `apply=true` 才会写入。

支持模式：

- `overwrite`
- `append`
- `replace_range`
- `insert_before`
- `insert_after`

## 验证

```powershell
python .\scripts\validate_skill.py
python .\scripts\package_skill.py
```

发布包会生成在 `dist/` 下：

- `vulcan-file-v<version>-skill.zip`
- `vulcan-file-v<version>-checksums.txt`

## 说明

- 仓库根目录就是 skill 根目录。
- 安装后的 skill id 来自包根目录名：`vulcan-file`。
- 运行时代码不依赖外部命令行工具。
- 输出面向 AI Agent 设计：紧凑、行号稳定，并明确提示参数错误。
