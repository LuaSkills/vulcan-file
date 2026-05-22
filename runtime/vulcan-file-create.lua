--[[
vulcan-file-create
Preview or create one brand-new file with an explicit create-only contract and optional host change_set output.
以显式仅创建契约和可选宿主 change_set 输出，预览或创建一个全新的文件。
]]

-- Visible Markdown title used for create error payloads.
-- 创建错误结果使用的可见 Markdown 标题。
local ERROR_TITLE = "FILE CREATE ERROR"

-- Visible Markdown title used for create success payloads.
-- 创建成功结果使用的可见 Markdown 标题。
local RESULT_TITLE = "FILE CREATE RESULT"

-- Visible section title used for preview blocks.
-- 预览区块使用的可见标题。
local PREVIEW_TITLE = "Preview"

-- Error codes that indicate the caller passed invalid create arguments.
-- 表示调用方传入无效创建参数的错误码集合。
local PARAMETER_ERROR_CODES = {
    invalid_file = true,
    environment_variable_not_found = true,
    invalid_environment_variable_reference = true,
    invalid_content = true,
    invalid_apply_argument = true,
    file_already_exists = true,
    parent_directory_not_found = true,
    parent_path_not_directory = true,
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

-- Validate the create request and normalize the target path to absolute form.
-- 校验创建请求，并将目标路径规范化为绝对路径。
--
-- Parameters:
--     helpers: Shared helper table.
--     args: Raw entry argument table from LuaSkills runtime.
-- 参数：
--     helpers：共享辅助表。
--     args：LuaSkills 运行时传入的原始参数表。
--
-- Returns:
--     table|nil: Normalized create request on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     table|nil：成功时返回规范化后的创建请求。
--     string|nil：失败时返回 Markdown 错误文本。
local function validate_request(helpers, args)
    local request = type(args) == "table" and args or {}
    if type(request.file) ~= "string" or helpers.trim(request.file) == "" then
        return nil, render_error(helpers, "invalid_file", "file must be a non-empty string")
    end
    if type(request.content) ~= "string" then
        return nil, render_error(helpers, "invalid_content", "content must be a string")
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
        content = request.content,
        apply = request.apply == true,
    }, nil
end

-- Verify that the target file does not already exist and that its parent directory is usable.
-- 校验目标文件尚不存在，且其父目录可用于写入。
--
-- Parameters:
--     helpers: Shared helper table.
--     file_path: Absolute target file path.
-- 参数：
--     helpers：共享辅助表。
--     file_path：绝对目标文件路径。
--
-- Returns:
--     string|nil: Parent directory path on success.
--     string|nil: Markdown error text on failure.
-- 返回值：
--     string|nil：成功时返回父目录路径。
--     string|nil：失败时返回 Markdown 错误文本。
local function validate_target_path(helpers, file_path)
    if vulcan.fs.exists(file_path) then
        return nil, render_error(helpers, "file_already_exists", "file already exists; use edit overwrite to replace an existing file", {
            file = file_path,
        })
    end
    local parent_dir = helpers.extract_parent_dir(file_path)
    if not parent_dir or parent_dir == "" then
        return nil, render_error(helpers, "invalid_file", "file must include a valid parent directory", {
            file = file_path,
        })
    end
    if not vulcan.fs.exists(parent_dir) then
        return nil, render_error(helpers, "parent_directory_not_found", "parent directory does not exist", {
            file = file_path,
            parent = parent_dir,
        })
    end
    if not vulcan.fs.is_dir(parent_dir) then
        return nil, render_error(helpers, "parent_path_not_directory", "parent path must point to a directory", {
            file = file_path,
            parent = parent_dir,
        })
    end
    return parent_dir, nil
end

-- Normalize one create request into final file content and span metadata reused by preview rendering.
-- 将一次创建请求规范化为最终文件内容与可复用的预览区间元数据。
--
-- Parameters:
--     helpers: Shared helper table.
--     request: Normalized create request.
-- 参数：
--     helpers：共享辅助表。
--     request：规范化后的创建请求。
--
-- Returns:
--     string: Final created file content.
--     table: Span metadata reused by the shared preview renderer.
-- 返回值：
--     string：最终创建出的文件内容。
--     table：供共享预览渲染器复用的区间元数据。
local function build_created_content(helpers, request)
    local created_content = tostring(request.content or "")
    local created_lines = helpers.split_insert_content(created_content)
    return created_content, {
        start_line = 1,
        end_line = math.max(1, #created_lines),
        original_start_line = 1,
        original_end_line = 0,
        inserted_line_count = #created_lines,
    }
end

-- Render the final create result while preserving a stable Markdown contract.
-- 在保持稳定 Markdown 契约的前提下渲染最终创建结果。
--
-- Parameters:
--     helpers: Shared helper table.
--     request: Normalized create request.
--     created_content: Final created file content.
--     changed_span: Span metadata reused by preview rendering.
--     parent_dir: Existing parent directory path.
-- 参数：
--     helpers：共享辅助表。
--     request：规范化后的创建请求。
--     created_content：最终创建出的文件内容。
--     changed_span：供预览复用的区间元数据。
--     parent_dir：已存在的父目录路径。
--
-- Returns:
--     string: Markdown success payload.
-- 返回值：
--     string：Markdown 成功结果文本。
local function render_result(helpers, request, created_content, changed_span, parent_dir)
    local status = request.apply and "APPLIED" or "PREVIEW_ONLY"
    local created_lines = select(1, helpers.split_lines_with_final_newline(created_content))
    local line_count = #created_lines
    local created_span = "none"
    if line_count > 0 then
        created_span = string.format("L1-L%d", line_count)
    end
    local lines = {
        "# " .. RESULT_TITLE,
        "",
        "- status: `" .. status .. "`",
        "- file: `" .. request.file .. "`",
        "- parent: `" .. tostring(parent_dir or "") .. "`",
        "- created_lines: `" .. tostring(line_count) .. "`",
        "- created_span: `" .. created_span .. "`",
        "",
        helpers.render_operation_preview("overwrite", request.content, "", created_content, changed_span, PREVIEW_TITLE, helpers.DEFAULT_MAX_PREVIEW_LINES),
    }
    return table.concat(lines, "\n")
end

-- Run the create entry with shared helpers and optional host change_set output.
-- 使用共享辅助与可选宿主 change_set 输出执行创建入口。
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

    local parent_dir, target_error = validate_target_path(helpers, request.file)
    if target_error then
        return target_error
    end

    local created_content, changed_span = build_created_content(helpers, request)
    if request.apply then
        local write_error = helpers.write_file(ERROR_TITLE, PARAMETER_ERROR_CODES, request.file, created_content, "")
        if write_error then
            return write_error
        end
    end

    local capability = helpers.resolve_host_result_capability()
    local host_result = helpers.build_create_host_result(capability, request.file, created_content, request.apply)
    return render_result(helpers, request, created_content, changed_span, parent_dir), nil, nil, host_result
end
