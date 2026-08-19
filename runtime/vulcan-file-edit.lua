--[=[
vulcan-file-edit
Apply one-file multi-node edits with original-content guards, staged offsets, and optional host change_set output.
使用原始内容护栏、暂存偏移和可选宿主 change_set 输出，对单个文件执行多节点编辑。
]=]

-- Visible Markdown title used for edit error payloads.
-- 编辑错误结果使用的可见 Markdown 标题。
local ERROR_TITLE = "FILE EDIT ERROR"

-- Visible Markdown title used for edit success payloads.
-- 编辑成功结果使用的可见 Markdown 标题。
local RESULT_TITLE = "FILE EDIT RESULT"

-- Maximum number of nodes accepted by one single-file request.
-- 单个单文件请求允许接收的最大节点数量。
local MAX_NODES = 50

-- Maximum number of request-content bytes accepted before execution.
-- 执行前允许的请求内容最大字节数。
local MAX_REQUEST_CONTENT_BYTES = 131072

-- Maximum number of candidate ranges rendered in one uniqueness diagnostic.
-- 单次唯一性诊断允许渲染的最大候选范围数量。
local MAX_DIAGNOSTIC_CANDIDATES = 20

-- Default line tolerance; zero preserves strict declared-range matching.
-- 默认行号容差；零值保持严格的声明范围匹配。
local DEFAULT_LINE_TOLERANCE = 0

-- Error codes that indicate invalid arguments or request-level rejection.
-- 表示参数无效或请求级拒绝的错误码集合。
local PARAMETER_ERROR_CODES = {
    invalid_request = true,
    invalid_file = true,
    file_is_directory = true,
    file_not_found = true,
    file_read_failed = true,
    invalid_pwd_argument = true,
    relative_path_requires_pwd = true,
    invalid_apply_argument = true,
    invalid_no_apply_argument = true,
    invalid_line_tolerance_argument = true,
    multiple_files_not_supported = true,
    invalid_nodes_argument = true,
    empty_nodes = true,
    duplicate_node_id = true,
    too_many_nodes = true,
    request_content_too_large = true,
    invalid_node = true,
    invalid_node_type = true,
    invalid_node_fields = true,
    invalid_edit_range = true,
    invalid_start_line_argument = true,
    invalid_end_line_argument = true,
    edit_on_empty_file = true,
    empty_append = true,
    overlapping_nodes = true,
}

-- Load the shared file helper module from the current entry directory.
-- 从当前入口目录加载共享文件辅助模块。
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
local function render_error(helpers, error_code, message, details)
    return helpers.render_error(ERROR_TITLE, PARAMETER_ERROR_CODES, error_code, message, details)
end

-- Return whether a value is a non-empty string.
-- 判断一个值是否为非空字符串。
local function is_non_empty_string(value)
    return type(value) == "string" and value ~= ""
end

-- Return whether a node contains any field outside its declared field set.
-- 判断节点是否包含声明字段集合之外的字段。
local function validate_node_fields(helpers, node, allowed_fields, node_index)
    for key in pairs(node) do
        if not allowed_fields[key] then
            return render_error(helpers, "invalid_node_fields", "node contains a field that is not valid for its type", {
                node_index = tostring(node_index),
                field = tostring(key),
            })
        end
    end
    return nil
end

-- Validate that the nodes value is a contiguous array before using ipairs.
-- 在使用 ipairs 前验证 nodes 是连续数组，拒绝字符串键和稀疏数字键。
local function validate_nodes_array(helpers, nodes)
    local count = #nodes
    for key in pairs(nodes) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > count then
            return render_error(helpers, "invalid_nodes_argument", "nodes must be a contiguous array of edit or append node objects", {
                field = tostring(key),
            })
        end
    end
    for index = 1, count do
        if nodes[index] == nil then
            return render_error(helpers, "invalid_nodes_argument", "nodes must be a contiguous array of edit or append node objects", {
                node_index = tostring(index),
            })
        end
    end
    return nil
end

-- Parse one positive integer without silently accepting malformed values.
-- 解析一个正整数，不静默接受格式错误的值。
local function parse_positive_line(helpers, value, field_name, node_index)
    local line, argument_error = helpers.parse_integer_argument(ERROR_TITLE, PARAMETER_ERROR_CODES, value, field_name)
    if argument_error then
        return nil, render_error(helpers, "invalid_edit_range", "node line range contains an invalid integer", {
            node_index = tostring(node_index),
            field = field_name,
            detail = argument_error,
        })
    end
    if line < 1 then
        return nil, render_error(helpers, "invalid_edit_range", "node line numbers must be positive integers", {
            node_index = tostring(node_index),
            field = field_name,
            value = tostring(line),
        })
    end
    return line, nil
end

-- Parse the optional non-negative line tolerance used for stale line numbers.
-- 解析用于处理过期行号的可选非负行号容差。
local function parse_line_tolerance(helpers, value)
    if value == nil then
        return DEFAULT_LINE_TOLERANCE, nil
    end
    local tolerance, argument_error = helpers.parse_integer_argument(ERROR_TITLE, PARAMETER_ERROR_CODES, value, "line_tolerance")
    if argument_error then
        return nil, argument_error
    end
    if tolerance < 0 then
        return nil, render_error(helpers, "invalid_line_tolerance_argument", "line_tolerance must be a non-negative integer", {
            value = tostring(tolerance),
        })
    end
    return tolerance, nil
end

-- Copy an array-style line table without sharing mutable entries.
-- 复制数组形式的行表，避免共享可变元素。
local function copy_lines(lines)
    local copied = {}
    for index, line in ipairs(lines or {}) do
        copied[index] = line
    end
    return copied
end

-- Return the exact line slice represented by an inclusive range.
-- 返回闭合行号范围对应的精确行切片。
local function slice_lines(lines, start_line, end_line)
    local result = {}
    if not start_line or not end_line or start_line > end_line then
        return result
    end
    for index = start_line, end_line do
        table.insert(result, tostring(lines[index] or ""))
    end
    return result
end

-- Compare two logical line arrays without trimming or case folding.
-- 比较两个逻辑行数组，不执行 trim 或大小写折叠。
local function lines_equal(left, right)
    if #left ~= #right then
        return false
    end
    for index = 1, #left do
        if tostring(left[index] or "") ~= tostring(right[index] or "") then
            return false
        end
    end
    return true
end

-- Find all exact contiguous occurrences of a logical line sequence.
-- 查找逻辑行序列的全部精确连续匹配位置。
local function find_line_occurrences(lines, target)
    local positions = {}
    if #target == 0 or #target > #lines then
        return positions
    end
    local last_start = #lines - #target + 1
    for start_line = 1, last_start do
        local candidate = slice_lines(lines, start_line, start_line + #target - 1)
        if lines_equal(candidate, target) then
            table.insert(positions, start_line)
        end
    end
    return positions
end

-- Resolve one globally unique match against the declared range and tolerance window.
-- 将全局唯一匹配与声明范围及容差窗口进行解析。
local function resolve_unique_match_range(node, original_line_count, old_line_count, occurrences, line_tolerance)
    local tolerance = tonumber(line_tolerance) or DEFAULT_LINE_TOLERANCE
    local allowed_start = math.max(1, node.start_line - tolerance)
    local allowed_end = math.min(original_line_count, node.end_line + tolerance)
    if #occurrences ~= 1 then
        return nil, nil, "unresolved", allowed_start, allowed_end
    end
    local matched_start = occurrences[1]
    local matched_end = matched_start + old_line_count - 1
    if matched_start < allowed_start or matched_end > allowed_end then
        return nil, nil, "outside_tolerance", allowed_start, allowed_end
    end
    local match_mode = matched_start == node.start_line and matched_end == node.end_line and "strict" or "tolerant"
    return matched_start, matched_end, match_mode, allowed_start, allowed_end
end

-- Format one inclusive line range for human-readable diagnostics.
-- 将闭合行号范围格式化为可读诊断文本。
local function format_range(start_line, end_line)
    if not start_line or not end_line or start_line > end_line then
        return "none"
    end
    return string.format("L%d-L%d", start_line, end_line)
end

-- Render logical lines as text using the selected newline sequence.
-- 使用指定换行序列将逻辑行渲染为文本。
local function render_lines(helpers, lines, newline)
    return helpers.join_lines(lines or {}, false, newline)
end

-- Return a compact representation of previous node deltas.
-- 返回前置节点行数增减量的紧凑表示。
local function build_shifted_by(applied_nodes)
    local shifted = {}
    for _, result in ipairs(applied_nodes or {}) do
        if tonumber(result.delta) and tonumber(result.delta) ~= 0 then
            table.insert(shifted, {
                id = result.id,
                delta = tonumber(result.delta),
            })
        end
    end
    return shifted
end

-- Calculate the current staged range of a not-yet-applied edit node.
-- 计算尚未应用编辑节点在当前暂存内容中的范围。
local function calculate_mapped_range(node, applied_nodes)
    local shift = 0
    for _, result in ipairs(applied_nodes or {}) do
        local matched_original_end = result.matched_original_end_line or result.original_end_line
        if matched_original_end < node.start_line then
            shift = shift + (tonumber(result.delta) or 0)
        end
    end
    return node.start_line + shift, node.end_line + shift
end

-- Build a stable list of skipped node descriptors after a node-level failure.
-- 构造节点级失败后稳定的未执行节点描述列表。
local function build_skipped_nodes(nodes, failed_index, applied_nodes)
    local skipped = {}
    for index = failed_index + 1, #nodes do
        local node = nodes[index]
        local current_start, current_end = nil, nil
        if node.type == "edit" then
            current_start, current_end = calculate_mapped_range(node, applied_nodes)
        end
        table.insert(skipped, {
            id = node.id,
            node_index = node.original_index,
            type = node.type,
            original_range = node.type == "edit" and format_range(node.start_line, node.end_line) or "append",
            current_range = node.type == "edit" and format_range(current_start, current_end) or "end-of-file",
            reason = "not executed after the previous node failed",
        })
    end
    return skipped
end

-- Convert skipped node descriptors into a compact Markdown value.
-- 将未执行节点描述转换为紧凑的 Markdown 值。
local function describe_skipped_nodes(skipped)
    local values = {}
    for _, node in ipairs(skipped or {}) do
        table.insert(values, string.format("%s(%s, current=%s)", tostring(node.id), tostring(node.original_range), tostring(node.current_range)))
    end
    return #values > 0 and table.concat(values, "; ") or "none"
end

-- Replace one inclusive range in a mutable line table.
-- 在可变行表中替换一个闭合范围。
local function replace_line_range(lines, start_line, end_line, replacement)
    for index = end_line, start_line, -1 do
        table.remove(lines, index)
    end
    for index = #replacement, 1, -1 do
        table.insert(lines, start_line, replacement[index])
    end
end

-- Read one existing regular file and return its original text.
-- 读取一个已存在的普通文件并返回原始文本。
local function read_existing_file(helpers, file_path)
    if not vulcan.fs.exists(file_path) then
        return nil, render_error(helpers, "file_not_found", "file does not exist; edit only accepts existing files", {
            file = file_path,
        })
    end
    if vulcan.fs.is_dir(file_path) then
        return nil, render_error(helpers, "file_is_directory", "file must point to a regular file", {
            file = file_path,
        })
    end
    local ok, content = pcall(vulcan.fs.read, file_path)
    if not ok then
        return nil, render_error(helpers, "file_read_failed", tostring(content), {
            file = file_path,
        })
    end
    return tostring(content or ""), nil
end

-- Normalize and structurally validate the root single-file request.
-- 规范化并执行根级单文件请求的结构校验。
local function validate_request_shape(helpers, args)
    local raw = type(args) == "table" and args or {}
    if raw.apply ~= nil then
        return nil, render_error(helpers, "invalid_apply_argument", "apply is no longer supported; use no_apply=true to preview without writing")
    end
    if raw.files ~= nil then
        return nil, render_error(helpers, "multiple_files_not_supported", "edit accepts one file per request; use nodes for multiple positions in that file")
    end
    for _, forbidden in ipairs({ "mode", "content", "start_line", "end_line", "line" }) do
        if raw[forbidden] ~= nil then
            return nil, render_error(helpers, "invalid_request", "legacy edit fields are not accepted; use file plus nodes", {
                field = forbidden,
            })
        end
    end
    -- Reject root fields outside the published single-file request contract.
    -- 拒绝公开单文件请求契约之外的根字段，避免仅依赖外层 Schema 防护。
    local allowed_root_fields = {
        PWD = true,
        file = true,
        line_tolerance = true,
        no_apply = true,
        nodes = true,
    }
    for field_name in pairs(raw) do
        if not allowed_root_fields[field_name] then
            return nil, render_error(helpers, "invalid_request", "request contains an unsupported root field", {
                field = tostring(field_name),
            })
        end
    end

    local no_apply_error = helpers.validate_optional_boolean(ERROR_TITLE, PARAMETER_ERROR_CODES, raw.no_apply, "no_apply")
    if no_apply_error then
        return nil, no_apply_error
    end
    local line_tolerance, line_tolerance_error = parse_line_tolerance(helpers, raw.line_tolerance)
    if line_tolerance_error then
        return nil, line_tolerance_error
    end
    local pwd_root, pwd_error = helpers.resolve_pwd_root(ERROR_TITLE, PARAMETER_ERROR_CODES, raw.PWD)
    if pwd_error then
        return nil, pwd_error
    end
    if type(raw.file) ~= "string" or helpers.trim(raw.file) == "" then
        return nil, render_error(helpers, "invalid_file", "file must be a non-empty string")
    end
    if type(raw.nodes) ~= "table" then
        return nil, render_error(helpers, "invalid_nodes_argument", "nodes must be an array of edit or append node objects")
    end
    local nodes_array_error = validate_nodes_array(helpers, raw.nodes)
    if nodes_array_error then
        return nil, nodes_array_error
    end
    if #raw.nodes < 1 then
        return nil, render_error(helpers, "empty_nodes", "nodes must contain at least one node")
    end
    if #raw.nodes > MAX_NODES then
        return nil, render_error(helpers, "too_many_nodes", "nodes exceed the per-request limit", {
            limit = tostring(MAX_NODES),
            actual_count = tostring(#raw.nodes),
        })
    end

    local file_path, environment_error = helpers.expand_environment_path(ERROR_TITLE, PARAMETER_ERROR_CODES, helpers.trim(raw.file), "file", pwd_root)
    if environment_error then
        return nil, environment_error
    end

    local nodes = {}
    local seen_ids = {}
    local content_bytes = 0
    for index, raw_node in ipairs(raw.nodes) do
        if type(raw_node) ~= "table" then
            return nil, render_error(helpers, "invalid_node", "each node must be an object", {
                node_index = tostring(index),
            })
        end
        if not is_non_empty_string(raw_node.id) then
            return nil, render_error(helpers, "invalid_node", "each node must have a non-empty id", {
                node_index = tostring(index),
            })
        end
        if seen_ids[raw_node.id] then
            return nil, render_error(helpers, "duplicate_node_id", "node ids must be unique within one request", {
                node_id = raw_node.id,
                first_node_index = tostring(seen_ids[raw_node.id]),
                duplicate_node_index = tostring(index),
            })
        end
        seen_ids[raw_node.id] = index
        if raw_node.type ~= "edit" and raw_node.type ~= "append" then
            return nil, render_error(helpers, "invalid_node_type", "node type must be edit or append", {
                node_id = raw_node.id,
                node_index = tostring(index),
            })
        end

        local node
        if raw_node.type == "edit" then
            local field_error = validate_node_fields(helpers, raw_node, {
                id = true,
                type = true,
                start_line = true,
                end_line = true,
                old_content = true,
                new_content = true,
            }, index)
            if field_error then
                return nil, field_error
            end
            local start_line, start_error = parse_positive_line(helpers, raw_node.start_line, "start_line", index)
            if start_error then
                return nil, start_error
            end
            local end_line, end_error = parse_positive_line(helpers, raw_node.end_line, "end_line", index)
            if end_error then
                return nil, end_error
            end
            if end_line < start_line then
                return nil, render_error(helpers, "invalid_edit_range", "end_line must be greater than or equal to start_line", {
                    node_id = raw_node.id,
                    node_index = tostring(index),
                    start_line = tostring(start_line),
                    end_line = tostring(end_line),
                })
            end
            if not is_non_empty_string(raw_node.old_content) then
                return nil, render_error(helpers, "invalid_node", "edit.old_content must be a non-empty string", {
                    node_id = raw_node.id,
                    node_index = tostring(index),
                })
            end
            if type(raw_node.new_content) ~= "string" then
                return nil, render_error(helpers, "invalid_node", "edit.new_content must be a string and may be empty for deletion", {
                    node_id = raw_node.id,
                    node_index = tostring(index),
                })
            end
            node = {
                id = raw_node.id,
                type = "edit",
                start_line = start_line,
                end_line = end_line,
                old_content = raw_node.old_content,
                new_content = raw_node.new_content,
                original_index = index,
            }
            content_bytes = content_bytes + #raw_node.old_content + #raw_node.new_content
        else
            local field_error = validate_node_fields(helpers, raw_node, {
                id = true,
                type = true,
                new_content = true,
            }, index)
            if field_error then
                return nil, field_error
            end
            if type(raw_node.new_content) ~= "string" or raw_node.new_content == "" then
                return nil, render_error(helpers, "empty_append", "append.new_content must be a non-empty string", {
                    node_id = raw_node.id,
                    node_index = tostring(index),
                })
            end
            node = {
                id = raw_node.id,
                type = "append",
                new_content = raw_node.new_content,
                original_index = index,
            }
            content_bytes = content_bytes + #raw_node.new_content
        end
        if content_bytes > MAX_REQUEST_CONTENT_BYTES then
            return nil, render_error(helpers, "request_content_too_large", "request content exceeds the per-request byte limit", {
                limit = tostring(MAX_REQUEST_CONTENT_BYTES),
                actual_bytes = tostring(content_bytes),
                node_id = raw_node.id,
            })
        end
        table.insert(nodes, node)
    end

    return {
        file = file_path,
        line_tolerance = line_tolerance,
        no_apply = raw.no_apply == true,
        nodes = nodes,
        content_bytes = content_bytes,
    }, nil
end

-- Read the file and complete request-level range and overlap validation.
-- 读取文件并完成请求级范围与重叠校验。
local function prepare_request(helpers, request)
    local original_content, read_error = read_existing_file(helpers, request.file)
    if read_error then
        return nil, read_error
    end
    local newline = helpers.detect_newline_sequence(original_content)
    local original_lines, had_final_newline = helpers.split_lines_with_final_newline(original_content)
    local edit_nodes = {}
    local append_nodes = {}
    for _, node in ipairs(request.nodes) do
        if node.type == "edit" then
            if #original_lines == 0 then
                return nil, render_error(helpers, "edit_on_empty_file", "empty files have no edit anchor; use an append node", {
                    node_id = node.id,
                    node_index = tostring(node.original_index),
                })
            end
            if node.end_line > #original_lines and request.line_tolerance == 0 then
                return nil, render_error(helpers, "invalid_edit_range", "edit range must be inside the original file line range", {
                    node_id = node.id,
                    node_index = tostring(node.original_index),
                    requested_range = format_range(node.start_line, node.end_line),
                    original_line_count = tostring(#original_lines),
                })
            end
            table.insert(edit_nodes, node)
        else
            table.insert(append_nodes, node)
        end
    end
    table.sort(edit_nodes, function(left, right)
        if left.start_line == right.start_line then
            return left.original_index < right.original_index
        end
        return left.start_line < right.start_line
    end)
    for index = 2, #edit_nodes do
        local previous = edit_nodes[index - 1]
        local current = edit_nodes[index]
        if current.start_line <= previous.end_line then
            return nil, render_error(helpers, "overlapping_nodes", "overlapping edit nodes reject the complete request", {
                first_node_id = previous.id,
                first_range = format_range(previous.start_line, previous.end_line),
                second_node_id = current.id,
                second_range = format_range(current.start_line, current.end_line),
                overlap_range = format_range(current.start_line, math.min(previous.end_line, current.end_line)),
                commit_scope = "none",
            })
        end
    end
    local ordered_nodes = {}
    for _, node in ipairs(edit_nodes) do
        table.insert(ordered_nodes, node)
    end
    for _, node in ipairs(append_nodes) do
        table.insert(ordered_nodes, node)
    end
    request.nodes = ordered_nodes
    request.original_content = original_content
    request.original_lines = original_lines
    request.had_final_newline = had_final_newline
    request.newline = newline
    return request, nil
end

-- Build a node result with original, current, final, and shift metadata.
-- 构造包含原始、当前、最终范围和偏移元数据的节点结果。
local function build_node_result(node, current_start, current_end, new_line_count, applied_nodes, matched_start_line, matched_end_line, match_mode)
    local matched_start = node.type == "edit" and (matched_start_line or node.start_line) or current_start
    local matched_end = node.type == "edit" and (matched_end_line or node.end_line) or (current_start - 1)
    local old_line_count = node.type == "edit" and (matched_end - matched_start + 1) or 0
    local delta = node.type == "edit" and (new_line_count - old_line_count) or new_line_count
    local final_start = current_start
    local final_end = new_line_count > 0 and (current_start + new_line_count - 1) or (current_start - 1)
    return {
        id = node.id,
        type = node.type,
        original_index = node.original_index,
        original_start_line = node.type == "edit" and node.start_line or nil,
        original_end_line = node.type == "edit" and node.end_line or nil,
        matched_original_start_line = node.type == "edit" and matched_start or nil,
        matched_original_end_line = node.type == "edit" and matched_end or nil,
        match_mode = node.type == "edit" and (match_mode or "strict") or nil,
        current_start_line = current_start,
        current_end_line = current_end,
        start_line = final_start,
        end_line = final_end,
        final_range = format_range(final_start, final_end),
        final_anchor_line = new_line_count == 0 and current_start or nil,
        old_line_count = old_line_count,
        new_line_count = new_line_count,
        delta = delta,
        shifted_by = build_shifted_by(applied_nodes),
        new_content = node.new_content,
        changed_span = {
            start_line = final_start,
            end_line = final_end,
            original_start_line = matched_start,
            original_end_line = matched_end,
            inserted_line_count = new_line_count,
        },
    }
end

-- Validate final content with validators that are reliable for the file type.
-- 使用对目标文件类型可靠的校验器验证最终内容。
--
-- Return only one bounded diagnostic line so callers do not nest a complete Markdown error block.
-- 只返回一条有长度上限的诊断行，避免调用方再次嵌套完整 Markdown 错误块。
--
-- Parameters:
--     helpers: Shared file helpers providing trim.
--     value: Raw decoder error value.
-- 参数：
--     helpers：提供 trim 的共享文件辅助表。
--     value：解码器返回的原始错误值。
--
-- Returns:
--     string: One-line, Markdown-safe, bounded diagnostic detail.
-- 返回值：
--     string：单行、Markdown 安全且有长度上限的诊断详情。
local function compact_error_detail(helpers, value)
    local text = tostring(value or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local candidate = helpers.trim(line)
        if candidate ~= "" then
            candidate = candidate:gsub("`", "'")
            if #candidate > 240 then
                return candidate:sub(1, 237) .. "..."
            end
            return candidate
        end
    end
    return "JSON decoder returned no diagnostic detail"
end

-- Validate final JSON content and return a concise detail for the outer error renderer.
-- 校验最终 JSON 内容，并向外层错误渲染器返回简洁详情。
local function validate_final_content(helpers, file_path, content)
    if tostring(file_path):lower():match("%.json$") then
        if not vulcan.json or type(vulcan.json.decode) ~= "function" then
            return "JSON validation is unavailable in the host runtime"
        end
        local ok, decoded = pcall(vulcan.json.decode, content)
        if not ok then
            return "JSON decoder: " .. compact_error_detail(helpers, decoded)
        end
        if decoded == nil and content ~= "null" then
            return "JSON decoder returned null for non-null content"
        end
    end
    return nil
end

-- Build one canonical host file record containing one hunk per node.
-- 构造每个节点一个 hunk 的 canonical 宿主文件记录。
local function build_multi_modify_record(helpers, request, final_content, node_results)
    local record = {
        change = "modify",
        path = request.file,
        hunks = {},
    }
    for _, result in ipairs(node_results or {}) do
        local single = helpers.build_modify_file_record(request.file, request.original_content, final_content, result.changed_span)
        if type(single) == "table" and type(single.hunks) == "table" then
            for _, hunk in ipairs(single.hunks) do
                hunk.node_id = result.id
                hunk.original_range = result.type == "edit" and format_range(result.original_start_line, result.original_end_line) or "append"
                hunk.matched_original_range = result.type == "edit" and format_range(result.matched_original_start_line, result.matched_original_end_line) or "append"
                hunk.match_mode = result.match_mode or "none"
                hunk.final_range = result.final_range
                hunk.delta = result.delta
                hunk.shifted_by = result.shifted_by
                table.insert(record.hunks, hunk)
            end
        end
    end
    if #record.hunks == 0 then
        return nil
    end
    return record
end

-- Build the optional host change_set projection for the current disk state.
-- 为当前磁盘状态构造可选的宿主 change_set 投影。
local function build_host_result(helpers, capability, request, final_content, node_results, apply, summary)
    local record = build_multi_modify_record(helpers, request, final_content, node_results)
    if not record then
        return nil
    end
    return helpers.build_change_set_host_result(capability, apply, summary, { record })
end

-- Describe one node's shift sources in Markdown.
-- 将一个节点的偏移来源描述为 Markdown。
local function describe_shift(node_result)
    if not node_result.shifted_by or #node_result.shifted_by == 0 then
        return "前置节点未造成行号偏移"
    end
    local parts = {}
    local total = 0
    for _, item in ipairs(node_result.shifted_by) do
        total = total + (tonumber(item.delta) or 0)
        table.insert(parts, string.format("%s(%+d行)", tostring(item.id), tonumber(item.delta) or 0))
    end
    return string.format("受 %s 影响，累计偏移 %+d 行", table.concat(parts, "、"), total)
end

-- Render one node preview against the final staged content.
-- 根据最终暂存内容渲染一个节点预览。
local function render_node_preview(helpers, request, final_content, node_result)
    local mode = node_result.type == "append" and "append" or "replace_range"
    return helpers.render_operation_preview(mode, node_result.new_content, request.original_content, final_content, node_result.changed_span, "Preview " .. tostring(node_result.id), helpers.DEFAULT_MAX_PREVIEW_LINES, final_content)
end

-- Render a successful full or preview result with sorted final ranges.
-- 渲染包含排序后最终范围的完整成功或预览结果。
local function render_success(helpers, request, final_content, node_results, status, commit_scope)
    local original_lines = request.original_lines
    local final_lines = select(1, helpers.split_lines_with_final_newline(final_content))
    local lines = {
        "# " .. RESULT_TITLE,
        "",
        "- status: `" .. status .. "`",
        "- commit_scope: `" .. commit_scope .. "`",
        "- committed: `" .. tostring(commit_scope ~= "none") .. "`",
        "- file: `" .. request.file .. "`",
        "- line_tolerance: `" .. tostring(request.line_tolerance) .. "`",
        "- original_lines: `" .. tostring(#original_lines) .. "`",
        "- final_lines: `" .. tostring(#final_lines) .. "`",
        "- node_order: `original_start_line ascending; append nodes last`",
        "",
        "## Node Summary",
    }
    for index, result in ipairs(node_results) do
        table.insert(lines, string.format("%d. `%s` (%s): original `%s` -> final `%s`, delta `%+d`", index, result.id, result.type, result.type == "edit" and format_range(result.original_start_line, result.original_end_line) or "append", result.final_range, result.delta))
        table.insert(lines, "   - shift: " .. describe_shift(result))
        if result.match_mode == "tolerant" then
            table.insert(lines, string.format("   - tolerant_match: declared `%s`, matched `%s` within ±%d lines", format_range(result.original_start_line, result.original_end_line), format_range(result.matched_original_start_line, result.matched_original_end_line), request.line_tolerance))
        end
        if result.final_anchor_line then
            table.insert(lines, "   - final_anchor_line: `L" .. tostring(result.final_anchor_line) .. "`")
        end
    end
    table.insert(lines, "")
    table.insert(lines, "## Previews")
    for _, result in ipairs(node_results) do
        table.insert(lines, "")
        table.insert(lines, render_node_preview(helpers, request, final_content, result))
    end
    return table.concat(lines, "\n")
end

-- Render a node-level failure with committed, failed, and skipped state.
-- 渲染包含已提交、失败和未执行状态的节点级错误。
local function render_node_failure(helpers, request, error_code, message, failed_node, failed_index, applied_nodes, staged_lines, commit_scope, match_count, candidates, candidates_omitted)
    local current_start, current_end = nil, nil
    local actual_content = "none"
    if failed_node.type == "edit" then
        current_start, current_end = calculate_mapped_range(failed_node, applied_nodes)
        actual_content = render_lines(helpers, slice_lines(staged_lines, current_start, current_end), request.newline)
    end
    local skipped = build_skipped_nodes(request.nodes, failed_index, applied_nodes)
    local applied_descriptions = {}
    for _, result in ipairs(applied_nodes) do
        table.insert(applied_descriptions, string.format("%s(%s, final=%s, delta=%+d)", result.id, result.type, result.final_range, result.delta))
    end
    local details = {
        file = request.file,
        failed_node_id = failed_node.id,
        failed_node_index = tostring(failed_node.original_index),
        failed_node_intent = failed_node.type == "edit" and ("edit " .. format_range(failed_node.start_line, failed_node.end_line)) or "append",
        original_range = failed_node.type == "edit" and format_range(failed_node.start_line, failed_node.end_line) or "append",
        line_tolerance = tostring(request.line_tolerance),
        search_range = failed_node.type == "edit" and format_range(math.max(1, failed_node.start_line - request.line_tolerance), math.min(#request.original_lines, failed_node.end_line + request.line_tolerance)) or "end-of-file",
        mapped_current_range = failed_node.type == "edit" and format_range(current_start, current_end) or "end-of-file",
        actual_content_at_mapped_range = actual_content,
        match_count = match_count and tostring(match_count) or "not evaluated",
        candidates = candidates and table.concat(candidates, ", ") or "none",
        candidates_omitted = tostring(candidates_omitted or 0),
        committed_prefix_nodes = commit_scope == "prefix" and table.concat(applied_descriptions, "; ") or "none",
        staged_prefix_nodes = #applied_descriptions > 0 and table.concat(applied_descriptions, "; ") or "none",
        skipped_nodes = describe_skipped_nodes(skipped),
        commit_scope = commit_scope,
        committed = tostring(commit_scope ~= "none"),
        file_state = commit_scope == "prefix" and "successful prefix is on disk" or "original file remains on disk",
    }
    return render_error(helpers, error_code, message, details)
end

-- Render a final-validation or write failure with staged execution state.
-- 渲染最终校验或写入失败时的暂存执行状态。
local function render_global_failure(helpers, request, error_code, message, applied_nodes, commit_scope, detail)
    local applied_descriptions = {}
    for _, result in ipairs(applied_nodes or {}) do
        table.insert(applied_descriptions, string.format("%s(final=%s, delta=%+d)", result.id, result.final_range, result.delta))
    end
    return render_error(helpers, error_code, message, {
        file = request.file,
        committed_prefix_nodes = commit_scope == "prefix" and table.concat(applied_descriptions, "; ") or "none",
        staged_prefix_nodes = #applied_descriptions > 0 and table.concat(applied_descriptions, "; ") or "none",
        skipped_nodes = "none",
        commit_scope = commit_scope,
        committed = tostring(commit_scope ~= "none"),
        file_state = error_code == "write_failed" and "disk state uncertain; re-read file before retry" or (commit_scope == "none" and "original file remains on disk" or "partial file state; inspect I/O diagnostics"),
        detail = detail or "none",
    })
end

-- Apply a staged prefix or complete content through the shared atomic writer.
-- 通过共享原子写入器提交暂存前缀或完整内容。
local function commit_content(helpers, request, content)
    return helpers.write_file(ERROR_TITLE, PARAMETER_ERROR_CODES, request.file, content, request.original_content)
end

-- Execute all nodes with structural preflight, node-level partial commit, and final validation.
-- 执行全部节点，落实结构预检、节点级部分提交和最终校验。
local function execute_request(helpers, request)
    local staged_lines = copy_lines(request.original_lines)
    local staged_final_newline = request.had_final_newline
    local applied_nodes = {}

    for index, node in ipairs(request.nodes) do
        if node.type == "edit" then
            local normalized_old = helpers.normalize_newlines(node.old_content, request.newline)
            local old_lines = select(1, helpers.split_lines_with_final_newline(normalized_old))
            local occurrences = find_line_occurrences(request.original_lines, old_lines)
            local match_start, match_end, match_mode = resolve_unique_match_range(node, #request.original_lines, #old_lines, occurrences, request.line_tolerance)
            if #occurrences ~= 1 then
                local prefix_content = helpers.join_lines(staged_lines, staged_final_newline, request.newline)
                local commit_scope = "none"
                if not request.no_apply and #applied_nodes > 0 then
                    local write_error = commit_content(helpers, request, prefix_content)
                    if write_error then
                        return render_global_failure(helpers, request, "write_failed", "failed to commit the successful node prefix", applied_nodes, "none", write_error), nil
                    end
                    commit_scope = "prefix"
                end
                local candidates = {}
                -- Render only a bounded prefix while retaining the complete match count.
                -- 只渲染有上限的候选前缀，同时保留完整匹配总数。
                for occurrence_index, position in ipairs(occurrences) do
                    if occurrence_index <= MAX_DIAGNOSTIC_CANDIDATES then
                        table.insert(candidates, format_range(position, position + #old_lines - 1))
                    end
                end
                local candidates_omitted = math.max(0, #occurrences - #candidates)
                local code
                local message
                if #occurrences == 0 then
                    code = "old_content_mismatch"
                    message = "old_content does not occur in the original file"
                else
                    code = "old_content_not_unique"
                    message = "old_content must occur exactly once in the original file"
                end
                local failure = render_node_failure(helpers, request, code, message, node, index, applied_nodes, staged_lines, commit_scope, #occurrences, candidates, candidates_omitted)
                local host = nil
                if #applied_nodes > 0 then
                    local capability = helpers.resolve_host_result_capability()
                    host = build_host_result(helpers, capability, request, prefix_content, applied_nodes, commit_scope == "prefix", commit_scope == "prefix" and "Applied successful node prefix; later node failed." or "Previewed successful node prefix; later node failed.")
                end
                return failure, host
            end
            if not match_start then
                local prefix_content = helpers.join_lines(staged_lines, staged_final_newline, request.newline)
                local commit_scope = "none"
                if not request.no_apply and #applied_nodes > 0 then
                    local write_error = commit_content(helpers, request, prefix_content)
                    if write_error then
                        return render_global_failure(helpers, request, "write_failed", "failed to commit the successful node prefix", applied_nodes, "none", write_error), nil
                    end
                    commit_scope = "prefix"
                end
                local failure = render_node_failure(helpers, request, "old_content_mismatch", "old_content is unique but is outside the declared range and line_tolerance window", node, index, applied_nodes, staged_lines, commit_scope, #occurrences, { format_range(occurrences[1], occurrences[1] + #old_lines - 1) }, 0)
                local host = nil
                if #applied_nodes > 0 then
                    local capability = helpers.resolve_host_result_capability()
                    host = build_host_result(helpers, capability, request, prefix_content, applied_nodes, commit_scope == "prefix", commit_scope == "prefix" and "Applied successful node prefix; later node failed." or "Previewed successful node prefix; later node failed.")
                end
                return failure, host
            end
            local matched_node = {
                start_line = match_start,
                end_line = match_end,
            }
            local current_start, current_end = calculate_mapped_range(matched_node, applied_nodes)
            for _, applied in ipairs(applied_nodes) do
                local applied_start = applied.matched_original_start_line or applied.original_start_line
                local applied_end = applied.matched_original_end_line or applied.original_end_line
                if applied_start <= match_end and match_start <= applied_end then
                    return render_error(helpers, "overlapping_nodes", "resolved original content ranges overlap; the complete request is rejected", {
                        first_node_id = applied.id,
                        first_range = format_range(applied_start, applied_end),
                        second_node_id = node.id,
                        second_range = format_range(match_start, match_end),
                        overlap_range = format_range(math.max(applied_start, match_start), math.min(applied_end, match_end)),
                        commit_scope = "none",
                    }), nil
                end
            end
            local current_lines = slice_lines(staged_lines, current_start, current_end)
            if not lines_equal(current_lines, old_lines) then
                -- This is an internal staging invariant failure, so fail closed without prefix commit.
                -- 这是内部暂存一致性护栏失败，必须失败关闭且不得提交前缀。
                local prefix_content = helpers.join_lines(staged_lines, staged_final_newline, request.newline)
                local failure = render_node_failure(helpers, request, "staged_content_mismatch", "the mapped staged range no longer contains the expected original content; no content was written", node, index, applied_nodes, staged_lines, "none", #occurrences, nil, 0)
                local host = nil
                if #applied_nodes > 0 then
                    local capability = helpers.resolve_host_result_capability()
                    host = build_host_result(helpers, capability, request, prefix_content, applied_nodes, false, "Previewed successful node prefix; internal consistency check failed.")
                end
                return failure, host
            end
            local normalized_new = helpers.normalize_newlines(node.new_content, request.newline)
            local new_lines = helpers.split_insert_content(normalized_new)
            replace_line_range(staged_lines, current_start, current_end, new_lines)
            local result = build_node_result(node, current_start, current_end, #new_lines, applied_nodes, match_start, match_end, match_mode)
            table.insert(applied_nodes, result)
        else
            local normalized_new = helpers.normalize_newlines(node.new_content, request.newline)
            local new_lines = helpers.split_insert_content(normalized_new)
            local current_start = #staged_lines + 1
            for _, line in ipairs(new_lines) do
                table.insert(staged_lines, line)
            end
            local _, append_had_final_newline = helpers.split_lines_with_final_newline(normalized_new)
            staged_final_newline = append_had_final_newline
            local result = build_node_result(node, current_start, current_start - 1, #new_lines, applied_nodes)
            table.insert(applied_nodes, result)
        end
    end

    local final_content = helpers.join_lines(staged_lines, staged_final_newline, request.newline)
    local final_validation_error = validate_final_content(helpers, request.file, final_content)
    if final_validation_error then
        return render_global_failure(helpers, request, "final_content_validation_failed", "final staged content failed validation; no file content was written", applied_nodes, "none", final_validation_error), nil
    end

    local apply = not request.no_apply
    local commit_scope = apply and "all" or "none"
    if apply then
        local write_error = commit_content(helpers, request, final_content)
        if write_error then
            return render_global_failure(helpers, request, "write_failed", "failed to commit the complete edited file", applied_nodes, "none", write_error), nil
        end
    end
    local status = apply and "APPLIED" or "PREVIEW_ONLY"
    local primary = render_success(helpers, request, final_content, applied_nodes, status, commit_scope)
    local capability = helpers.resolve_host_result_capability()
    local host_result = build_host_result(helpers, capability, request, final_content, applied_nodes, apply, apply and "Applied 1 file with multiple nodes." or "Previewed 1 file with multiple nodes.")
    return primary, host_result
end

-- Run the single-file edit entry and return the primary text plus optional host result.
-- 运行单文件编辑入口并返回主文本和可选宿主结果。
return function(args)
    local helpers = load_shared_file_helpers()
    local request, shape_error = validate_request_shape(helpers, args)
    if shape_error then
        return shape_error
    end
    local prepared_request, prepare_error = prepare_request(helpers, request)
    if prepare_error then
        return prepare_error
    end
    local primary, host_result = execute_request(helpers, prepared_request)
    return primary, nil, nil, host_result
end
