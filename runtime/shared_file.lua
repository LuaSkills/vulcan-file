--[[
shared_file
Provide shared helpers for vulcan-file create and edit entries.
为 vulcan-file 的 create 与 edit 入口提供共享辅助能力。
]]

-- Default maximum number of preview lines rendered in one diff-style block.
-- 单个类 diff 预览区块默认最多渲染的行数。
local DEFAULT_MAX_PREVIEW_LINES = 80

-- Return whether one value is a non-empty string after trimming.
-- 返回一个值在去除首尾空白后是否为非空字符串。
--
-- Parameters:
--     value: Any value that will be converted to text.
-- 参数：
--     value：将被转换为文本的任意值。
--
-- Returns:
--     boolean: True when the converted text is not empty after trimming.
-- 返回值：
--     boolean：转换后的文本去除首尾空白后非空时返回 true。
local function has_trimmed_text(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "") ~= ""
end

-- Remove surrounding whitespace from one value converted to text.
-- 将一个值转换为文本后移除首尾空白。
--
-- Parameters:
--     value: Any value that will be rendered as text.
-- 参数：
--     value：将被渲染为文本的任意值。
--
-- Returns:
--     string: Trimmed text form of the input value.
-- 返回值：
--     string：输入值去除首尾空白后的文本形式。
local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Check whether one string starts with the given prefix.
-- 检查一个字符串是否以给定前缀开头。
--
-- Parameters:
--     text: Source text to inspect.
--     prefix: Prefix that must appear at the beginning.
-- 参数：
--     text：需要检查的源文本。
--     prefix：必须出现在开头的前缀。
--
-- Returns:
--     boolean: True when the text begins with the prefix.
-- 返回值：
--     boolean：当文本以前缀开头时返回 true。
local function starts_with(text, prefix)
    return tostring(text or ""):sub(1, #tostring(prefix or "")) == tostring(prefix or "")
end

-- Check whether one string ends with the given suffix.
-- 检查一个字符串是否以给定后缀结尾。
--
-- Parameters:
--     text: Source text to inspect.
--     suffix: Suffix that must appear at the end.
-- 参数：
--     text：需要检查的源文本。
--     suffix：必须出现在末尾的后缀。
--
-- Returns:
--     boolean: True when the text ends with the suffix.
-- 返回值：
--     boolean：当文本以后缀结尾时返回 true。
local function ends_with(text, suffix)
    return tostring(text or ""):sub(-#tostring(suffix or "")) == tostring(suffix or "")
end

-- Join two path fragments with the host path helper when it exists.
-- 当宿主路径辅助存在时优先使用它拼接两个路径片段。
--
-- Parameters:
--     left: Left path fragment.
--     right: Right path fragment.
-- 参数：
--     left：左侧路径片段。
--     right：右侧路径片段。
--
-- Returns:
--     string: Joined path text.
-- 返回值：
--     string：拼接后的路径文本。
local function join_path(left, right)
    if vulcan and vulcan.path and type(vulcan.path.join) == "function" then
        return vulcan.path.join(left, right)
    end
    local separator = package.config:sub(1, 1)
    return tostring(left or "") .. separator .. tostring(right or "")
end

-- Determine whether one path text is already absolute on common Windows and POSIX forms.
-- 判断一个路径文本是否已是常见 Windows 或 POSIX 绝对路径形式。
--
-- Parameters:
--     path: Path text to inspect.
-- 参数：
--     path：需要检查的路径文本。
--
-- Returns:
--     boolean: True when the path is absolute.
-- 返回值：
--     boolean：当路径为绝对路径时返回 true。
local function is_absolute_path(path)
    local text = tostring(path or "")
    if text:match("^[A-Za-z]:[\\/]") then
        return true
    end
    if text:match("^[\\/][\\/]") then
        return true
    end
    if starts_with(text, "/") then
        return true
    end
    return false
end

-- Resolve one caller path into an absolute path rooted at the current runtime cwd.
-- 将一个调用方路径解析为以当前运行时工作目录为基准的绝对路径。
--
-- Parameters:
--     path: Original caller path text.
-- 参数：
--     path：原始调用方路径文本。
--
-- Returns:
--     string: Absolute path text.
-- 返回值：
--     string：绝对路径文本。
local function resolve_absolute_path(path)
    local text = tostring(path or "")
    if is_absolute_path(text) then
        return text
    end
    local runtime_cwd = "."
    if vulcan and vulcan.runtime and type(vulcan.runtime.cwd) == "function" then
        runtime_cwd = tostring(vulcan.runtime.cwd() or ".")
    end
    return join_path(runtime_cwd, text)
end

-- Extract one parent directory path from a file path.
-- 从文件路径中提取父目录路径。
--
-- Parameters:
--     file_path: File path that should contain one final basename segment.
-- 参数：
--     file_path：应当包含最终文件名片段的文件路径。
--
-- Returns:
--     string|nil: Parent directory path when available, otherwise nil.
-- 返回值：
--     string|nil：存在父目录时返回目录路径，否则返回 nil。
local function extract_parent_dir(file_path)
    return tostring(file_path or ""):match("^(.*[\\/])[^\\/]+$")
end

-- Render one stable Markdown error payload for file tools.
-- 为文件工具渲染一个稳定的 Markdown 错误结果。
--
-- Parameters:
--     error_title: Visible Markdown title such as FILE EDIT ERROR.
--     parameter_error_codes: Set-like table of parameter error codes.
--     error_code: Stable error identifier.
--     message: Human-readable error message.
--     details: Optional key-value details rendered as bullet lines.
-- 参数：
--     error_title：可见的 Markdown 标题，例如 FILE EDIT ERROR。
--     parameter_error_codes：参数错误码集合表。
--     error_code：稳定错误标识。
--     message：可读错误信息。
--     details：作为项目符号渲染的可选键值详情。
--
-- Returns:
--     string: Markdown error payload.
-- 返回值：
--     string：Markdown 错误结果文本。
local function render_error(error_title, parameter_error_codes, error_code, message, details)
    local is_parameter_error = parameter_error_codes[tostring(error_code or "")] == true
    local lines = {
        "# " .. tostring(error_title or "FILE ERROR"),
        "",
        "- error: `" .. tostring(error_code or "unknown_error") .. "`",
        "- type: `" .. (is_parameter_error and "parameter_error" or "runtime_error") .. "`",
        "- message: " .. tostring(message or "unknown file error"),
    }
    if is_parameter_error then
        table.insert(lines, "- correction: adjust the tool arguments and call again")
    end
    for key, value in pairs(details or {}) do
        table.insert(lines, "- " .. tostring(key) .. ": `" .. tostring(value) .. "`")
    end
    return table.concat(lines, "\n")
end

-- Expand `${env:NAME}` placeholders before filesystem access and normalize the final path to absolute form.
-- 在访问文件系统前展开 `${env:NAME}` 占位符，并将最终路径规范为绝对路径。
--
-- Parameters:
--     error_title: Visible Markdown title for errors.
--     parameter_error_codes: Set-like table of parameter error codes.
--     path: Caller path text to expand.
--     field_name: Argument name used in error output.
-- 参数：
--     error_title：错误使用的可见 Markdown 标题。
--     parameter_error_codes：参数错误码集合表。
--     path：需要展开的调用方路径文本。
--     field_name：错误输出中使用的参数名。
--
-- Returns:
--     string|nil: Absolute expanded path on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     string|nil：成功时返回绝对展开路径。
--     string|nil：失败时返回 Markdown 错误文本。
local function expand_environment_path(error_title, parameter_error_codes, path, field_name)
    local source = tostring(path or "")
    local unresolved_variable = nil
    local expanded = source:gsub("%${env:([^}]+)}", function(variable_name)
        local normalized_name = trim(variable_name)
        if normalized_name == "" then
            unresolved_variable = variable_name
            return ""
        end
        local environment_value = os.getenv(normalized_name)
        if environment_value == nil then
            unresolved_variable = normalized_name
            return ""
        end
        return environment_value
    end)

    if unresolved_variable ~= nil then
        return nil, render_error(error_title, parameter_error_codes, "environment_variable_not_found", "environment variable referenced in path is not defined", {
            field = tostring(field_name or "path"),
            variable = tostring(unresolved_variable),
            path = source,
        })
    end
    if expanded:find("${env:", 1, true) ~= nil then
        return nil, render_error(error_title, parameter_error_codes, "invalid_environment_variable_reference", "environment variable path placeholder must use ${env:NAME} syntax", {
            field = tostring(field_name or "path"),
            path = source,
        })
    end
    local resolved = trim(expanded)
    if resolved == "" then
        return nil, render_error(error_title, parameter_error_codes, "invalid_file", "file must resolve to a non-empty string", {
            field = tostring(field_name or "path"),
        })
    end
    return resolve_absolute_path(resolved), nil
end

-- Validate an optional boolean argument and report type mistakes clearly.
-- 校验一个可选布尔参数，并清晰报告类型错误。
--
-- Parameters:
--     error_title: Visible Markdown title for errors.
--     parameter_error_codes: Set-like table of parameter error codes.
--     value: Candidate boolean value.
--     argument_name: Argument name rendered in the error message.
-- 参数：
--     error_title：错误使用的可见 Markdown 标题。
--     parameter_error_codes：参数错误码集合表。
--     value：待校验的布尔候选值。
--     argument_name：错误信息中展示的参数名。
--
-- Returns:
--     string|nil: Markdown error text when the value is invalid, otherwise nil.
-- 返回值：
--     string|nil：值非法时返回 Markdown 错误文本，否则返回 nil。
local function validate_optional_boolean(error_title, parameter_error_codes, value, argument_name)
    if value == nil or type(value) == "boolean" then
        return nil
    end
    return render_error(error_title, parameter_error_codes, "invalid_" .. tostring(argument_name) .. "_argument", argument_name .. " must be a boolean when provided", {
        argument = tostring(argument_name),
        value = tostring(value),
        actual_type = type(value),
    })
end

-- Parse one integer argument without silently accepting strings or fractional numbers.
-- 解析一个整数参数，避免静默接受字符串或小数。
--
-- Parameters:
--     error_title: Visible Markdown title for errors.
--     parameter_error_codes: Set-like table of parameter error codes.
--     value: Candidate integer value.
--     argument_name: Argument name rendered in the error message.
-- 参数：
--     error_title：错误使用的可见 Markdown 标题。
--     parameter_error_codes：参数错误码集合表。
--     value：待解析的整数候选值。
--     argument_name：错误信息中展示的参数名。
--
-- Returns:
--     number|nil: Parsed integer value on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     number|nil：成功时返回解析后的整数值。
--     string|nil：失败时返回 Markdown 错误文本。
local function parse_integer_argument(error_title, parameter_error_codes, value, argument_name)
    if type(value) ~= "number" or value ~= math.floor(value) then
        return nil, render_error(error_title, parameter_error_codes, "invalid_" .. tostring(argument_name) .. "_argument", argument_name .. " must be an integer number", {
            argument = tostring(argument_name),
            value = tostring(value),
            actual_type = type(value),
        })
    end
    return value, nil
end

-- Detect the newline sequence that should be preserved for generated content.
-- 检测生成内容时应保留的换行序列。
--
-- Parameters:
--     content: Existing file text used as the preservation baseline.
-- 参数：
--     content：作为保留基准的现有文件文本。
--
-- Returns:
--     string: `\r\n` when Windows newlines are detected, otherwise `\n`.
-- 返回值：
--     string：检测到 Windows 换行时返回 `\r\n`，否则返回 `\n`。
local function detect_newline_sequence(content)
    if tostring(content or ""):find("\r\n", 1, true) then
        return "\r\n"
    end
    return "\n"
end

-- Normalize incoming text to the selected newline sequence.
-- 将输入文本规范化为选定的换行序列。
--
-- Parameters:
--     content: Source text to normalize.
--     newline: Target newline sequence.
-- 参数：
--     content：待规范化的源文本。
--     newline：目标换行序列。
--
-- Returns:
--     string: Text with normalized newline characters.
-- 返回值：
--     string：换行字符已规范化后的文本。
local function normalize_newlines(content, newline)
    local normalized = tostring(content or ""):gsub("\r\n", "\n")
    if newline == "\r\n" then
        normalized = normalized:gsub("\n", "\r\n")
    end
    return normalized
end

-- Split text into logical lines while preserving the trailing-newline flag.
-- 将文本拆分为逻辑行，同时保留尾随换行标记。
--
-- Parameters:
--     content: Text content to split.
-- 参数：
--     content：需要拆分的文本内容。
--
-- Returns:
--     table: Array-style logical line table.
--     boolean: True when the original content ended with a newline.
-- 返回值：
--     table：数组形式的逻辑行表。
--     boolean：原内容以换行结尾时返回 true。
local function split_lines_with_final_newline(content)
    local normalized = tostring(content or ""):gsub("\r\n", "\n")
    local had_final_newline = normalized ~= "" and ends_with(normalized, "\n")
    if normalized == "" then
        return {}, false
    end
    if had_final_newline then
        normalized = normalized:sub(1, -2)
    end
    local lines = {}
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines, had_final_newline
end

-- Join logical lines back into text while preserving final-newline intent.
-- 将逻辑行重新拼接为文本，并保留末尾换行意图。
--
-- Parameters:
--     lines: Array-style logical lines.
--     final_newline: Whether the output should end with one newline.
--     newline: Target newline sequence.
-- 参数：
--     lines：数组形式的逻辑行。
--     final_newline：输出是否应以一个换行结尾。
--     newline：目标换行序列。
--
-- Returns:
--     string: Reconstructed text content.
-- 返回值：
--     string：重新构造后的文本内容。
local function join_lines(lines, final_newline, newline)
    local text = table.concat(lines or {}, newline)
    if final_newline and text ~= "" then
        text = text .. newline
    end
    return text
end

-- Split inserted content into logical lines for line-based operations.
-- 将插入内容拆分为用于按行操作的逻辑行。
--
-- Parameters:
--     content: Inserted or replacement text content.
-- 参数：
--     content：插入或替换的文本内容。
--
-- Returns:
--     table: Array-style logical line table.
-- 返回值：
--     table：数组形式的逻辑行表。
local function split_insert_content(content)
    local lines, had_final_newline = split_lines_with_final_newline(content)
    if #lines == 0 and had_final_newline then
        return { "" }
    end
    return lines
end

-- Build one same-directory sidecar path for temporary writes and rollback backups.
-- 构造一个同目录旁路路径，用于临时写入与回滚备份。
--
-- Parameters:
--     file_path: Target file path.
--     label: Short sidecar label such as tmp or bak.
-- 参数：
--     file_path：目标文件路径。
--     label：旁路短标签，例如 tmp 或 bak。
--
-- Returns:
--     string: Generated sidecar file path.
-- 返回值：
--     string：生成的旁路文件路径。
local function build_sidecar_file_path(file_path, label)
    local directory, file_name = tostring(file_path or ""):match("^(.*[\\/])([^\\/]+)$")
    directory = directory or ""
    file_name = file_name or tostring(file_path or "")
    local base_name, extension = file_name:match("^(.*)(%.[^%.]+)$")
    if not base_name then
        base_name = file_name
        extension = ""
    end
    local unique_suffix = string.format("%d_%d", os.time(), math.floor((os.clock() % 1) * 1000000))
    return directory .. base_name .. "." .. tostring(label or "tmp") .. "." .. unique_suffix .. extension
end

-- Remove one sidecar file and ignore cleanup failures.
-- 删除一个旁路文件并忽略清理失败。
--
-- Parameters:
--     file_path: Candidate sidecar file path.
-- 参数：
--     file_path：候选旁路文件路径。
--
-- Returns:
--     None.
-- 返回值：
--     无。
local function safe_remove_file(file_path)
    if type(file_path) ~= "string" or file_path == "" then
        return
    end
    if vulcan.fs.exists(file_path) then
        pcall(os.remove, file_path)
    end
end

-- Rename one file and normalize platform-specific failure messages.
-- 重命名一个文件，并规范化不同平台上的失败信息。
--
-- Parameters:
--     source_path: Existing source path.
--     target_path: Target path after the rename.
-- 参数：
--     source_path：现有源路径。
--     target_path：重命名后的目标路径。
--
-- Returns:
--     boolean: True on success.
--     string|nil: Failure message when the rename fails.
-- 返回值：
--     boolean：成功时返回 true。
--     string|nil：重命名失败时返回失败信息。
local function rename_file(source_path, target_path)
    local ok, renamed, message = pcall(os.rename, source_path, target_path)
    if not ok then
        return false, tostring(renamed)
    end
    if not renamed then
        return false, tostring(message or "rename failed")
    end
    return true, nil
end

-- Write file content through one temp-file swap with best-effort rollback.
-- 通过一次临时文件替换写入文件内容，并尽最大努力执行回滚。
--
-- Parameters:
--     error_title: Visible Markdown title for errors.
--     parameter_error_codes: Set-like table of parameter error codes.
--     file_path: Final target file path.
--     content: Final text content to persist.
--     original_content: Original file content used for rollback.
-- 参数：
--     error_title：错误使用的可见 Markdown 标题。
--     parameter_error_codes：参数错误码集合表。
--     file_path：最终目标文件路径。
--     content：需要落盘的最终文本内容。
--     original_content：用于回滚的原始文件内容。
--
-- Returns:
--     string|nil: Markdown error text on failure, otherwise nil.
-- 返回值：
--     string|nil：失败时返回 Markdown 错误文本，否则返回 nil。
local function write_file(error_title, parameter_error_codes, file_path, content, original_content)
    local temp_path = build_sidecar_file_path(file_path, "tmp")
    local backup_path = build_sidecar_file_path(file_path, "bak")
    local existed_before = vulcan.fs.exists(file_path)

    local temp_ok, temp_error = pcall(vulcan.fs.write, temp_path, content)
    if not temp_ok then
        safe_remove_file(temp_path)
        return render_error(error_title, parameter_error_codes, "temp_write_failed", tostring(temp_error), {
            file = file_path,
            temp_file = temp_path,
        })
    end

    if existed_before then
        local backed_up, backup_error = rename_file(file_path, backup_path)
        if not backed_up then
            safe_remove_file(temp_path)
            return render_error(error_title, parameter_error_codes, "backup_creation_failed", tostring(backup_error), {
                file = file_path,
                backup_file = backup_path,
            })
        end
    end

    local swapped, swap_error = rename_file(temp_path, file_path)
    if not swapped then
        safe_remove_file(temp_path)
        if existed_before then
            local restored = rename_file(backup_path, file_path)
            if not restored then
                pcall(vulcan.fs.write, file_path, original_content)
            end
        end
        return render_error(error_title, parameter_error_codes, "temp_swap_failed", tostring(swap_error), {
            file = file_path,
            temp_file = temp_path,
            backup_file = backup_path,
        })
    end

    if existed_before then
        safe_remove_file(backup_path)
    end
    return nil
end

-- Append one preview line while respecting the preview line budget.
-- 在遵守预览行数预算的前提下追加一行预览内容。
--
-- Parameters:
--     output: Output line table to mutate.
--     rendered_count: Number of lines already rendered.
--     line: Preview line text to append.
--     max_preview_lines: Maximum preview line budget.
-- 参数：
--     output：需要原地追加的输出行表。
--     rendered_count：已经渲染的行数。
--     line：需要追加的预览行文本。
--     max_preview_lines：允许的最大预览行预算。
--
-- Returns:
--     number: Updated rendered line count.
--     boolean: True when more lines may still be appended.
-- 返回值：
--     number：更新后的已渲染行数。
--     boolean：仍允许继续追加时返回 true。
local function append_preview_line(output, rendered_count, line, max_preview_lines)
    if rendered_count >= max_preview_lines then
        return rendered_count, false
    end
    table.insert(output, line)
    return rendered_count + 1, true
end

-- Render one inclusive context range from a line table into one preview block.
-- 将一个行表中的闭区间上下文渲染到预览区块中。
--
-- Parameters:
--     output: Output line table to mutate.
--     rendered_count: Number of lines already rendered.
--     lines: Source logical line table.
--     start_line: First 1-based line number to render.
--     end_line: Last 1-based line number to render.
--     prefix: Prefix such as space, plus, or minus.
--     max_preview_lines: Maximum preview line budget.
-- 参数：
--     output：需要原地追加的输出行表。
--     rendered_count：已经渲染的行数。
--     lines：源逻辑行表。
--     start_line：需要渲染的首个 1-based 行号。
--     end_line：需要渲染的最后一个 1-based 行号。
--     prefix：前缀，例如空格、加号或减号。
--     max_preview_lines：允许的最大预览行预算。
--
-- Returns:
--     number: Updated rendered line count.
--     boolean: True when rendering can continue.
-- 返回值：
--     number：更新后的已渲染行数。
--     boolean：仍可继续渲染时返回 true。
local function render_context_range(output, rendered_count, lines, start_line, end_line, prefix, max_preview_lines)
    local safe_start = math.max(1, start_line)
    local safe_end = math.min(#lines, end_line)
    for line_number = safe_start, safe_end do
        local keep_going
        rendered_count, keep_going = append_preview_line(output, rendered_count, string.format("%sL%d: %s", prefix, line_number, lines[line_number] or ""), max_preview_lines)
        if not keep_going then
            return rendered_count, false
        end
    end
    return rendered_count, true
end

-- Render one operation-oriented preview so inserts and deletions remain visually clear.
-- 渲染一个面向操作的预览，确保插入与删除在视觉上保持清晰。
--
-- Parameters:
--     request_mode: Edit mode such as overwrite or append.
--     request_content: Original requested content text used for empty-preview messaging.
--     original_content: Original file content.
--     edited_content: Edited file content.
--     changed_span: Span metadata describing old and new line ranges.
--     preview_title: Visible preview section title.
--     max_preview_lines: Maximum preview line budget.
-- 参数：
--     request_mode：编辑模式，例如 overwrite 或 append。
--     request_content：用于空预览提示的原始请求内容。
--     original_content：原始文件内容。
--     edited_content：编辑后的文件内容。
--     changed_span：描述旧行范围与新行范围的区间元数据。
--     preview_title：可见预览区标题。
--     max_preview_lines：允许的最大预览行预算。
--
-- Returns:
--     string: Markdown preview block.
-- 返回值：
--     string：Markdown 预览区块文本。
local function render_operation_preview(request_mode, request_content, original_content, edited_content, changed_span, preview_title, max_preview_lines)
    local original_lines = select(1, split_lines_with_final_newline(original_content))
    local edited_lines = select(1, split_lines_with_final_newline(edited_content))
    local original_start = changed_span.original_start_line or changed_span.start_line
    local original_end = changed_span.original_end_line or changed_span.end_line
    local edited_start = changed_span.start_line
    local edited_end = changed_span.end_line
    local before_context_start = original_start - 3
    local before_context_end = original_start - 1
    local after_context_start = original_end + 1
    local after_context_end = original_end + 3
    local output = {
        "## " .. tostring(preview_title or "Preview"),
        "",
        "```diff",
    }
    if request_mode == "insert_after" then
        before_context_start = original_start - 2
        before_context_end = original_start
    elseif request_mode == "insert_before" then
        after_context_start = original_start
        after_context_end = original_start + 2
    end

    local preview_limit = tonumber(max_preview_lines) or DEFAULT_MAX_PREVIEW_LINES
    local rendered = 0
    local keep_going
    rendered, keep_going = render_context_range(output, rendered, original_lines, before_context_start, before_context_end, " ", preview_limit)

    if keep_going and (request_mode == "replace_range" or request_mode == "overwrite") then
        rendered, keep_going = render_context_range(output, rendered, original_lines, original_start, original_end, "-", preview_limit)
    end

    if keep_going and (changed_span.inserted_line_count or 0) > 0 then
        rendered, keep_going = render_context_range(output, rendered, edited_lines, edited_start, edited_end, "+", preview_limit)
    end

    if keep_going and request_mode ~= "append" then
        rendered, keep_going = render_context_range(output, rendered, original_lines, after_context_start, after_context_end, " ", preview_limit)
    end

    if not keep_going then
        table.insert(output, "... preview truncated ...")
    end
    if rendered == 0 then
        if tostring(request_content or "") == "" then
            table.insert(output, "(no inserted lines)")
        else
            table.insert(output, "(no visible line changes)")
        end
    end
    table.insert(output, "```")
    return table.concat(output, "\n")
end

-- Build one contiguous context string from a logical line table around one range boundary.
-- 从逻辑行表中围绕某个区间边界构造一个连续上下文字符串。
--
-- Parameters:
--     lines: Source logical line table.
--     start_line: First 1-based line to include.
--     end_line: Last 1-based line to include.
--     newline: Newline sequence used to rejoin lines.
-- 参数：
--     lines：源逻辑行表。
--     start_line：需要包含的首个 1-based 行号。
--     end_line：需要包含的最后一个 1-based 行号。
--     newline：重新拼接时使用的换行序列。
--
-- Returns:
--     string: Joined contiguous context string, or an empty string when no lines are selected.
-- 返回值：
--     string：拼接后的连续上下文字符串；未选中任何行时返回空字符串。
local function build_context_string(lines, start_line, end_line, newline)
    if not lines or #lines == 0 then
        return ""
    end
    local safe_start = math.max(1, start_line or 1)
    local safe_end = math.min(#lines, end_line or 0)
    if safe_start > safe_end then
        return ""
    end
    local buffer = {}
    for line_number = safe_start, safe_end do
        table.insert(buffer, lines[line_number] or "")
    end
    return table.concat(buffer, newline or "\n")
end

-- Build ordered `{ line, content }` entries from one logical line table range.
-- 从一个逻辑行表区间构造有序的 `{ line, content }` 记录。
--
-- Parameters:
--     lines: Source logical line table.
--     start_line: First 1-based line to include.
--     end_line: Last 1-based line to include.
-- 参数：
--     lines：源逻辑行表。
--     start_line：需要包含的首个 1-based 行号。
--     end_line：需要包含的最后一个 1-based 行号。
--
-- Returns:
--     table: Array-style ordered line entry list.
-- 返回值：
--     table：数组形式的有序行记录列表。
local function build_line_entries(lines, start_line, end_line)
    local output = {}
    if not lines or #lines == 0 then
        return output
    end
    local safe_start = math.max(1, start_line or 1)
    local safe_end = math.min(#lines, end_line or 0)
    if safe_start > safe_end then
        return output
    end
    for line_number = safe_start, safe_end do
        table.insert(output, {
            line = line_number,
            content = tostring(lines[line_number] or ""),
        })
    end
    return output
end

-- Build one canonical modify file record for a host `change_set` result.
-- 为宿主 `change_set` 结果构造一个 canonical 的 modify 文件记录。
--
-- Parameters:
--     file_path: Absolute target file path.
--     original_content: Original file content.
--     edited_content: Edited file content.
--     changed_span: Span metadata describing old and new line ranges.
-- 参数：
--     file_path：绝对目标文件路径。
--     original_content：原始文件内容。
--     edited_content：编辑后的文件内容。
--     changed_span：描述旧行范围与新行范围的区间元数据。
--
-- Returns:
--     table: Canonical `change_set.files[]` modify record.
-- 返回值：
--     table：canonical `change_set.files[]` modify 记录。
local function build_modify_file_record(file_path, original_content, edited_content, changed_span)
    local newline = detect_newline_sequence(original_content ~= "" and original_content or edited_content)
    local original_lines = select(1, split_lines_with_final_newline(original_content))
    local edited_lines = select(1, split_lines_with_final_newline(edited_content))
    local original_start = changed_span.original_start_line or changed_span.start_line
    local original_end = changed_span.original_end_line or changed_span.end_line
    local edited_start = changed_span.start_line or 1
    local edited_end = changed_span.end_line or (changed_span.start_line or 1)
    local before_context = build_context_string(original_lines, original_start - 3, original_start - 1, newline)
    local after_context = build_context_string(original_lines, original_end + 1, original_end + 3, newline)
    local deleted_lines = build_line_entries(original_lines, original_start, original_end)
    local inserted_lines = {}
    if (changed_span.inserted_line_count or 0) > 0 then
        inserted_lines = build_line_entries(edited_lines, edited_start, edited_end)
    end
    if #deleted_lines == 0 and #inserted_lines == 0 then
        return nil
    end
    return {
        change = "modify",
        path = tostring(file_path or ""),
        hunks = {
            {
                before = before_context,
                delete = deleted_lines,
                insert = inserted_lines,
                after = after_context,
            },
        },
    }
end

-- Build one canonical create file record for a host `change_set` result.
-- 为宿主 `change_set` 结果构造一个 canonical 的 create 文件记录。
--
-- Parameters:
--     file_path: Absolute target file path.
--     content: Final created file content.
-- 参数：
--     file_path：绝对目标文件路径。
--     content：最终创建出的文件内容。
--
-- Returns:
--     table: Canonical `change_set.files[]` create record.
-- 返回值：
--     table：canonical `change_set.files[]` create 记录。
local function build_create_file_record(file_path, content)
    return {
        change = "create",
        path = tostring(file_path or ""),
        content = tostring(content or ""),
    }
end

-- Resolve one normalized snapshot of the current host structured-result capability.
-- 解析当前宿主结构化结果能力的标准化快照。
--
-- Parameters:
--     None.
-- 参数：
--     无。
--
-- Returns:
--     table: Capability snapshot with enabled, allows_change_set, and max_payload_bytes fields.
-- 返回值：
--     table：包含 enabled、allows_change_set 与 max_payload_bytes 字段的能力快照。
local function resolve_host_result_capability()
    local host_result = nil
    if vulcan and vulcan.context and type(vulcan.context.host_result) == "table" then
        host_result = vulcan.context.host_result
    end
    local enabled = type(host_result) == "table" and host_result.enabled == true
    local allowed_kinds = type(host_result) == "table" and host_result.allowed_kinds or nil
    local allow_change_set = true
    if type(allowed_kinds) == "table" then
        local saw_any = false
        allow_change_set = false
        for _, item in ipairs(allowed_kinds) do
            if type(item) == "string" and trim(item) ~= "" then
                saw_any = true
                if trim(item) == "change_set" then
                    allow_change_set = true
                end
            end
        end
        if not saw_any then
            allow_change_set = true
        end
    end
    local max_payload_bytes = nil
    if type(host_result) == "table" then
        local numeric_limit = tonumber(host_result.max_payload_bytes)
        if numeric_limit and numeric_limit > 0 then
            max_payload_bytes = math.floor(numeric_limit)
        end
    end
    return {
        enabled = enabled,
        allows_change_set = enabled and allow_change_set,
        max_payload_bytes = max_payload_bytes,
    }
end

-- Finalize one optional host `change_set` result while respecting host capability and payload size limits.
-- 在遵守宿主能力与载荷大小限制的前提下完成一个可选的宿主 `change_set` 结果。
--
-- Parameters:
--     capability: Capability snapshot from resolve_host_result_capability.
--     payload: Candidate `change_set` payload object.
-- 参数：
--     capability：来自 resolve_host_result_capability 的能力快照。
--     payload：候选 `change_set` 载荷对象。
--
-- Returns:
--     table|nil: Host result wrapper `{ kind = "change_set", payload = ... }` when accepted.
-- 返回值：
--     table|nil：被接受时返回 `{ kind = "change_set", payload = ... }` 宿主结果包装对象。
local function finalize_change_set_host_result(capability, payload)
    if type(capability) ~= "table" or capability.enabled ~= true or capability.allows_change_set ~= true then
        return nil
    end
    if type(payload) ~= "table" then
        return nil
    end
    if capability.max_payload_bytes ~= nil and vulcan and vulcan.json and type(vulcan.json.encode) == "function" then
        local ok, encoded = pcall(vulcan.json.encode, payload)
        if not ok or type(encoded) ~= "string" then
            return nil
        end
        if #encoded > capability.max_payload_bytes then
            return nil
        end
    end
    return {
        kind = "change_set",
        payload = payload,
    }
end

-- Build one host `change_set` wrapper for a single-file create operation.
-- 为单文件创建操作构造一个宿主 `change_set` 包装结果。
--
-- Parameters:
--     capability: Capability snapshot from resolve_host_result_capability.
--     file_path: Absolute target file path.
--     content: Final file content.
--     apply: Whether the operation has been written to disk.
-- 参数：
--     capability：来自 resolve_host_result_capability 的能力快照。
--     file_path：绝对目标文件路径。
--     content：最终文件内容。
--     apply：操作是否已经落盘。
--
-- Returns:
--     table|nil: Host result wrapper when accepted, otherwise nil.
-- 返回值：
--     table|nil：被接受时返回宿主结果包装对象，否则返回 nil。
local function build_create_host_result(capability, file_path, content, apply)
    local payload = {
        mode = apply and "applied" or "preview",
        summary = (apply and "Applied" or "Previewed") .. " creation of 1 file.",
        files = {
            build_create_file_record(file_path, content),
        },
    }
    return finalize_change_set_host_result(capability, payload)
end

-- Build one host `change_set` wrapper for a single-file edit operation.
-- 为单文件编辑操作构造一个宿主 `change_set` 包装结果。
--
-- Parameters:
--     capability: Capability snapshot from resolve_host_result_capability.
--     file_path: Absolute target file path.
--     original_content: Original file content.
--     edited_content: Edited file content.
--     changed_span: Span metadata describing old and new line ranges.
--     apply: Whether the operation has been written to disk.
--     change_type: Either create or modify.
-- 参数：
--     capability：来自 resolve_host_result_capability 的能力快照。
--     file_path：绝对目标文件路径。
--     original_content：原始文件内容。
--     edited_content：编辑后的文件内容。
--     changed_span：描述旧行范围与新行范围的区间元数据。
--     apply：操作是否已经落盘。
--     change_type：create 或 modify。
--
-- Returns:
--     table|nil: Host result wrapper when accepted, otherwise nil.
-- 返回值：
--     table|nil：被接受时返回宿主结果包装对象，否则返回 nil。
local function build_edit_host_result(capability, file_path, original_content, edited_content, changed_span, apply, change_type)
    local file_record = nil
    if change_type == "create" then
        file_record = build_create_file_record(file_path, edited_content)
    else
        file_record = build_modify_file_record(file_path, original_content, edited_content, changed_span)
    end
    if type(file_record) ~= "table" then
        return nil
    end
    local payload = {
        mode = apply and "applied" or "preview",
        summary = (apply and "Applied" or "Previewed") .. " 1 file edit.",
        files = {
            file_record,
        },
    }
    return finalize_change_set_host_result(capability, payload)
end

return {
    DEFAULT_MAX_PREVIEW_LINES = DEFAULT_MAX_PREVIEW_LINES,
    trim = trim,
    has_trimmed_text = has_trimmed_text,
    starts_with = starts_with,
    ends_with = ends_with,
    join_path = join_path,
    is_absolute_path = is_absolute_path,
    resolve_absolute_path = resolve_absolute_path,
    extract_parent_dir = extract_parent_dir,
    render_error = render_error,
    expand_environment_path = expand_environment_path,
    validate_optional_boolean = validate_optional_boolean,
    parse_integer_argument = parse_integer_argument,
    detect_newline_sequence = detect_newline_sequence,
    normalize_newlines = normalize_newlines,
    split_lines_with_final_newline = split_lines_with_final_newline,
    join_lines = join_lines,
    split_insert_content = split_insert_content,
    build_sidecar_file_path = build_sidecar_file_path,
    safe_remove_file = safe_remove_file,
    rename_file = rename_file,
    write_file = write_file,
    render_operation_preview = render_operation_preview,
    build_modify_file_record = build_modify_file_record,
    build_create_file_record = build_create_file_record,
    resolve_host_result_capability = resolve_host_result_capability,
    finalize_change_set_host_result = finalize_change_set_host_result,
    build_create_host_result = build_create_host_result,
    build_edit_host_result = build_edit_host_result,
}
