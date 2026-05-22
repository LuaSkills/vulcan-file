--[[
vulcan-file-edit
Preview or apply one small text edit while preserving a stable text contract and optional host change_set output.
在保持稳定文本契约与可选宿主 change_set 输出的前提下，预览或应用一次小范围文本编辑。
]]

-- Visible Markdown title used for edit error payloads.
-- 编辑错误结果使用的可见 Markdown 标题。
local ERROR_TITLE = "FILE EDIT ERROR"

-- Visible Markdown title used for edit success payloads.
-- 编辑成功结果使用的可见 Markdown 标题。
local RESULT_TITLE = "FILE EDIT RESULT"

-- Visible section title used for preview blocks.
-- 预览区块使用的可见标题。
local PREVIEW_TITLE = "Preview"

-- Supported edit modes accepted by this tool.
-- 本工具接受的编辑模式集合。
local SUPPORTED_MODES = {
    overwrite = true,
    append = true,
    replace_range = true,
    insert_before = true,
    insert_after = true,
}

-- Error codes that indicate the caller passed invalid tool arguments.
-- 表示调用方传入无效工具参数的错误码集合。
local PARAMETER_ERROR_CODES = {
    invalid_file = true,
    file_is_directory = true,
    file_not_found = true,
    environment_variable_not_found = true,
    invalid_environment_variable_reference = true,
    invalid_mode = true,
    invalid_content = true,
    empty_content_noop = true,
    invalid_apply_argument = true,
    invalid_start_line_argument = true,
    invalid_end_line_argument = true,
    invalid_line_argument = true,
    line_out_of_bounds = true,
    invalid_range = true,
}

-- Load the shared file helper module from the current entry directory.
-- 从当前入口目录加载共享文件辅助模块。
--
-- Parameters:
--     None.
-- 参数：
--     无。
--
-- Returns:
--     table: Shared helper table used by create and edit entries.
-- 返回值：
--     table：create 与 edit 入口共用的辅助表。
local function load_shared_file_helpers()
    local entry_dir = tostring(vulcan.context.entry_dir or ".")
    local helper_path = vulcan.path.join(entry_dir, "shared_file.lua")
    local chunk, load_error = loadfile(helper_path)
    if not chunk then
        error("Failed to load shared_file.lua: " .. tostring(load_error))
    end

    local ok, helpers = pcall(chunk)
    if not ok or type(helpers) ~= "table" then
        error("shared_file.lua did not return a helper table: " .. tostring(helpers))
    end
    return helpers
end

-- Build one tool-local Markdown error payload through the shared helper.
-- 通过共享辅助构造一个工具本地 Markdown 错误结果。
--
-- Parameters:
--     helpers: Shared helper table.
--     error_code: Stable error identifier.
--     message: Human-readable error message.
--     details: Optional key-value details rendered as bullet lines.
-- 参数：
--     helpers：共享辅助表。
--     error_code：稳定错误标识。
--     message：可读错误信息。
--     details：以项目符号行渲染的可选键值详情。
--
-- Returns:
--     string: Markdown error payload.
-- 返回值：
--     string：Markdown 错误结果文本。
local function render_error(helpers, error_code, message, details)
    return helpers.render_error(ERROR_TITLE, PARAMETER_ERROR_CODES, error_code, message, details)
end

-- Validate the common edit request fields and normalize the target path to absolute form.
-- 校验通用编辑请求字段，并将目标路径规范化为绝对路径。
--
-- Parameters:
--     helpers: Shared helper table.
--     args: Raw entry argument table from LuaSkills runtime.
-- 参数：
--     helpers：共享辅助表。
--     args：LuaSkills 运行时传入的原始参数表。
--
-- Returns:
--     table|nil: Normalized request table on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     table|nil：成功时返回规范化后的请求表。
--     string|nil：失败时返回 Markdown 错误文本。
local function validate_request(helpers, args)
    local request = type(args) == "table" and args or {}
    if type(request.file) ~= "string" or helpers.trim(request.file) == "" then
        return nil, render_error(helpers, "invalid_file", "file must be a non-empty string")
    end
    if type(request.mode) ~= "string" or not SUPPORTED_MODES[request.mode] then
        return nil, render_error(helpers, "invalid_mode", "mode must be overwrite, append, replace_range, insert_before, or insert_after")
    end
    if type(request.content) ~= "string" then
        return nil, render_error(helpers, "invalid_content", "content must be a string")
    end
    if (request.mode == "append" or request.mode == "insert_before" or request.mode == "insert_after") and request.content == "" then
        return nil, render_error(helpers, "empty_content_noop", "append and insert modes require non-empty content")
    end

    local file_path, environment_error = helpers.expand_environment_path(ERROR_TITLE, PARAMETER_ERROR_CODES, helpers.trim(request.file), "file")
    if environment_error then
        return nil, environment_error
    end
    local apply_error = helpers.validate_optional_boolean(ERROR_TITLE, PARAMETER_ERROR_CODES, request.apply, "apply")
    if apply_error then
        return nil, apply_error
    end

    return {
        file = file_path,
        mode = request.mode,
        content = request.content,
        start_line = request.start_line,
        end_line = request.end_line,
        line = request.line,
        apply = request.apply == true,
    }, nil
end

-- Read one existing file or return an empty baseline for overwrite-based file creation.
-- 读取一个现有文件，或为基于 overwrite 的文件创建返回空基线。
--
-- Parameters:
--     helpers: Shared helper table.
--     file_path: Absolute target file path.
--     mode: Requested edit mode.
-- 参数：
--     helpers：共享辅助表。
--     file_path：绝对目标文件路径。
--     mode：请求的编辑模式。
--
-- Returns:
--     string|nil: Original file content on success.
--     string|nil: Markdown error text on failure.
--     boolean|nil: True when the file existed before the edit.
-- 返回值：
--     string|nil：成功时返回原始文件内容。
--     string|nil：失败时返回 Markdown 错误文本。
--     boolean|nil：编辑前文件存在时返回 true。
local function read_existing_file(helpers, file_path, mode)
    if vulcan.fs.exists(file_path) then
        if vulcan.fs.is_dir(file_path) then
            return nil, render_error(helpers, "file_is_directory", "file must point to a regular file", {
                file = file_path,
            }), nil
        end
        local ok, content = pcall(vulcan.fs.read, file_path)
        if not ok then
            return nil, render_error(helpers, "file_read_failed", tostring(content), {
                file = file_path,
            }), nil
        end
        return tostring(content or ""), nil, true
    end

    if mode == "overwrite" then
        return "", nil, false
    end
    return nil, render_error(helpers, "file_not_found", "file does not exist", {
        file = file_path,
    }), nil
end

-- Validate one 1-based line number for insert operations.
-- 校验插入操作使用的 1-based 行号。
--
-- Parameters:
--     helpers: Shared helper table.
--     value: Candidate line number.
--     line_count: Total number of lines in the original file.
-- 参数：
--     helpers：共享辅助表。
--     value：候选行号。
--     line_count：原始文件总行数。
--
-- Returns:
--     number|nil: Validated line number on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     number|nil：成功时返回校验通过的行号。
--     string|nil：失败时返回 Markdown 错误文本。
local function validate_insert_line(helpers, value, line_count)
    if line_count < 1 then
        return nil, render_error(helpers, "line_out_of_bounds", "insert_before and insert_after require an existing anchor line; use append or overwrite for empty files", {
            total_lines = tostring(line_count),
            allowed_range = "none",
        })
    end
    local line, argument_error = helpers.parse_integer_argument(ERROR_TITLE, PARAMETER_ERROR_CODES, value, "line")
    if argument_error then
        return nil, argument_error
    end
    if line < 1 or line > line_count then
        return nil, render_error(helpers, "line_out_of_bounds", "line must point to an existing 1-based anchor line", {
            line = tostring(line),
            total_lines = tostring(line_count),
            allowed_range = "1-" .. tostring(line_count),
        })
    end
    return line, nil
end

-- Validate one 1-based closed line range for replace_range operations.
-- 校验 replace_range 操作使用的 1-based 闭区间行范围。
--
-- Parameters:
--     helpers: Shared helper table.
--     start_value: Candidate start_line value.
--     end_value: Candidate end_line value.
--     line_count: Total number of lines in the original file.
-- 参数：
--     helpers：共享辅助表。
--     start_value：候选 start_line 值。
--     end_value：候选 end_line 值。
--     line_count：原始文件总行数。
--
-- Returns:
--     number|nil: Validated start line.
--     number|nil: Validated end line.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     number|nil：校验通过的起始行号。
--     number|nil：校验通过的结束行号。
--     string|nil：失败时返回 Markdown 错误文本。
local function validate_replace_range(helpers, start_value, end_value, line_count)
    if start_value == nil or end_value == nil then
        return nil, nil, render_error(helpers, "invalid_range", "replace_range requires start_line and end_line")
    end
    local start_line, start_error = helpers.parse_integer_argument(ERROR_TITLE, PARAMETER_ERROR_CODES, start_value, "start_line")
    if start_error then
        return nil, nil, start_error
    end
    local end_line, end_error = helpers.parse_integer_argument(ERROR_TITLE, PARAMETER_ERROR_CODES, end_value, "end_line")
    if end_error then
        return nil, nil, end_error
    end
    if start_line < 1 or end_line < start_line or end_line > line_count then
        return nil, nil, render_error(helpers, "invalid_range", "start_line/end_line must describe an existing 1-based line range")
    end
    return start_line, end_line, nil
end

-- Apply the requested edit to text and return the new content together with changed span metadata.
-- 对文本应用请求的编辑，并返回新内容与变更区间元数据。
--
-- Parameters:
--     helpers: Shared helper table.
--     request: Normalized edit request.
--     original_content: Original file content.
-- 参数：
--     helpers：共享辅助表。
--     request：规范化后的编辑请求。
--     original_content：原始文件内容。
--
-- Returns:
--     string|nil: Edited file content on success.
--     table|nil: Changed span metadata on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     string|nil：成功时返回编辑后的文件内容。
--     table|nil：成功时返回变更区间元数据。
--     string|nil：失败时返回 Markdown 错误文本。
local function build_edited_content(helpers, request, original_content)
    local newline = helpers.detect_newline_sequence(original_content)
    local normalized_insert = helpers.normalize_newlines(request.content, newline)
    local original_lines, had_final_newline = helpers.split_lines_with_final_newline(original_content)
    local edit_lines = helpers.split_insert_content(normalized_insert)

    if request.mode == "overwrite" then
        local inserted_line_count = #helpers.split_insert_content(normalized_insert)
        return normalized_insert, {
            start_line = 1,
            end_line = math.max(1, inserted_line_count),
            original_start_line = 1,
            original_end_line = math.max(1, #original_lines),
            inserted_line_count = inserted_line_count,
        }, nil
    end

    if request.mode == "append" then
        local prefix = original_content
        if prefix ~= "" and not helpers.ends_with(prefix:gsub("\r\n", "\n"), "\n") then
            prefix = prefix .. newline
        end
        return prefix .. normalized_insert, {
            start_line = #original_lines + 1,
            end_line = #original_lines + math.max(1, #edit_lines),
            original_start_line = #original_lines + 1,
            original_end_line = #original_lines,
            inserted_line_count = #edit_lines,
        }, nil
    end

    if request.mode == "replace_range" then
        local start_line, end_line, range_error = validate_replace_range(helpers, request.start_line, request.end_line, #original_lines)
        if range_error then
            return nil, nil, range_error
        end
        for index = end_line, start_line, -1 do
            table.remove(original_lines, index)
        end
        for index = #edit_lines, 1, -1 do
            table.insert(original_lines, start_line, edit_lines[index])
        end
        return helpers.join_lines(original_lines, had_final_newline, newline), {
            start_line = start_line,
            end_line = start_line + math.max(0, #edit_lines - 1),
            original_start_line = start_line,
            original_end_line = end_line,
            inserted_line_count = #edit_lines,
        }, nil
    end

    local line, line_error = validate_insert_line(helpers, request.line, #original_lines)
    if line_error then
        return nil, nil, line_error
    end
    local insert_index = request.mode == "insert_before" and line or line + 1
    for index = #edit_lines, 1, -1 do
        table.insert(original_lines, insert_index, edit_lines[index])
    end
    return helpers.join_lines(original_lines, had_final_newline, newline), {
        start_line = insert_index,
        end_line = insert_index + math.max(0, #edit_lines - 1),
        original_start_line = line,
        original_end_line = line,
        inserted_line_count = #edit_lines,
    }, nil
end

-- Render the final edit result while preserving the current Markdown contract.
-- 在保持当前 Markdown 契约的前提下渲染最终编辑结果。
--
-- Parameters:
--     helpers: Shared helper table.
--     request: Normalized edit request.
--     original_content: Original file content.
--     edited_content: Edited file content.
--     changed_span: Changed span metadata.
-- 参数：
--     helpers：共享辅助表。
--     request：规范化后的编辑请求。
--     original_content：原始文件内容。
--     edited_content：编辑后的文件内容。
--     changed_span：变更区间元数据。
--
-- Returns:
--     string: Markdown success payload.
-- 返回值：
--     string：Markdown 成功结果文本。
local function render_result(helpers, request, original_content, edited_content, changed_span)
    local status = request.apply and "APPLIED" or "PREVIEW_ONLY"
    local original_lines = select(1, helpers.split_lines_with_final_newline(original_content))
    local edited_lines = select(1, helpers.split_lines_with_final_newline(edited_content))
    local original_start_line = changed_span.original_start_line or changed_span.start_line
    local original_end_line = changed_span.original_end_line or changed_span.end_line
    local original_span = "none"
    if original_start_line >= 1 and original_start_line <= original_end_line and original_end_line <= #original_lines then
        original_span = string.format("L%d-L%d", original_start_line, original_end_line)
    end
    local edited_span = "none"
    if (changed_span.inserted_line_count or 0) > 0 then
        edited_span = string.format("L%d-L%d", changed_span.start_line, changed_span.end_line)
    end
    local lines = {
        "# " .. RESULT_TITLE,
        "",
        "- status: `" .. status .. "`",
        "- file: `" .. request.file .. "`",
        "- mode: `" .. request.mode .. "`",
        "- original_lines: `" .. tostring(#original_lines) .. "`",
        "- edited_lines: `" .. tostring(#edited_lines) .. "`",
        "- original_span: `" .. original_span .. "`",
        "- edited_span: `" .. edited_span .. "`",
        "- changed_span: `original " .. original_span .. " -> edited " .. edited_span .. "`",
        "",
        helpers.render_operation_preview(request.mode, request.content, original_content, edited_content, changed_span, PREVIEW_TITLE, helpers.DEFAULT_MAX_PREVIEW_LINES),
    }
    return table.concat(lines, "\n")
end

-- Determine which canonical host change type should represent the edit result.
-- 判断哪个 canonical 宿主变更类型最适合表示本次编辑结果。
--
-- Parameters:
--     request: Normalized edit request.
--     existed_before: Whether the file existed before the edit.
-- 参数：
--     request：规范化后的编辑请求。
--     existed_before：编辑前文件是否存在。
--
-- Returns:
--     string: Either create or modify.
-- 返回值：
--     string：create 或 modify。
local function determine_change_type(request, existed_before)
    if request.mode == "overwrite" and existed_before ~= true then
        return "create"
    end
    return "modify"
end

-- Run the edit entry with shared helpers and optional host change_set output.
-- 使用共享辅助与可选宿主 change_set 输出执行编辑入口。
--
-- Parameters:
--     args: Raw entry argument table from LuaSkills runtime.
-- 参数：
--     args：LuaSkills 运行时传入的原始参数表。
--
-- Returns:
--     string: Markdown primary result for AI and text consumers.
--     nil: No overflow mode is used by this tool.
--     nil: No template hint is used by this tool.
--     table|nil: Optional host structured change_set result.
-- 返回值：
--     string：面向 AI 与文本消费方的 Markdown 主结果。
--     nil：本工具不使用 overflow mode。
--     nil：本工具不使用 template hint。
--     table|nil：可选的宿主结构化 change_set 结果。
return function(args)
    local helpers = load_shared_file_helpers()
    local request, validation_error = validate_request(helpers, args)
    if validation_error then
        return validation_error
    end

    local capability = helpers.resolve_host_result_capability()
    local original_content, read_error, existed_before = read_existing_file(helpers, request.file, request.mode)
    if read_error then
        return read_error
    end

    local edited_content, changed_span, edit_error = build_edited_content(helpers, request, original_content)
    if edit_error then
        return edit_error
    end

    if request.apply then
        local write_error = helpers.write_file(ERROR_TITLE, PARAMETER_ERROR_CODES, request.file, edited_content, original_content)
        if write_error then
            return write_error
        end
    end

    local change_type = determine_change_type(request, existed_before)
    local host_result = helpers.build_edit_host_result(capability, request.file, original_content, edited_content, changed_span, request.apply, change_type)
    return render_result(helpers, request, original_content, edited_content, changed_span), nil, nil, host_result
end
