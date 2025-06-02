local uv = vim.loop
local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

---@class Node
---@field name string
---@field path string  -- Relative to root
---@field abs_path string -- Absolute path
---@field type 'file' | 'directory'
---@field key string
---@field displayKey string
---@field children Node[]?

local M = {}

local TREE_WIDTH = 30

local state = {
    root_path = "",
    root_nodes = {},
    expanded_dirs = {},
    key_bindings = {},
    global_actions = {},
    tree_buf = nil,
    tree_win = nil,
}

local function generate_key_pool()
    local keys = {}
    for i = 97, 122 do
        keys[#keys + 1] = string.char(i)
    end
    return keys
end

local function is_key_free_normal(full_key)
    local maps = vim.api.nvim_get_keymap('n')
    for _, map in ipairs(maps) do
        if map.lhs == full_key then
            return false
        end
    end
    return vim.fn.maparg(full_key, "n") == ""
end

local function generate_unique_key(existing_keys)
    local pool = generate_key_pool()
    math.randomseed(os.time())
    for _ = 1, 1000 do
        local key = ""
        for _ = 1, 2 do
            key = key .. pool[math.random(#pool)]
        end
        local full_key = "<leader>" .. key
        if not existing_keys[full_key] and is_key_free_normal(full_key) then
            return full_key, key
        end
    end
    return nil, nil
end

local function register_keymap(key, action)
    vim.keymap.set("n", key, action, { noremap = true, silent = true })
end

local function build_tree(path, existing_keys, relative_prefix)
    local nodes = {}
    local handle = uv.fs_scandir(path)
    if not handle then return nodes end

    while true do
        local name, type = uv.fs_scandir_next(handle)
        if not name then break end

        local abs_path = path .. "/" .. name
        local rel_path = relative_prefix .. name

        local full_key, displayKey = generate_unique_key(existing_keys)
        if full_key then
            existing_keys[full_key] = true

            local node = {
                name = name,
                path = rel_path,
                abs_path = abs_path,
                type = type,
                key = full_key,
                displayKey = displayKey,
                children = nil,
            }

            table.insert(nodes, node)

            local action
            if type == 'file' then
                action = function()
                    vim.cmd.edit(abs_path)
                end
            else
                action = function()
                    if state.expanded_dirs[node.path] then
                        state.expanded_dirs[node.path] = false
                    else
                        state.expanded_dirs[node.path] = true
                        if not node.children then
                            node.children = build_tree(abs_path, existing_keys, rel_path .. "/")
                        end
                    end
                    M.render_tree()
                end
            end

            state.global_actions[full_key] = action

            register_keymap(full_key, action)
        end
    end

    table.sort(nodes, function(a, b)
        if a.type == b.type then return a.name < b.name end
        return a.type == 'directory'
    end)

    return nodes
end

local function flatten_tree(nodes, indent, lines, highlights, linenr)
    for _, node in ipairs(nodes) do
        local prefix = string.rep("  ", indent)
        local icon = " "
        local icon_hl = "Normal"

        if node.type == 'directory' then
            icon = " "
            icon_hl = "Directory"
        elseif devicons_ok then
            local ext = node.name:match("^.+%.(.+)$")
            icon, icon_hl = devicons.get_icon(node.name, ext or "", { default = true })
            icon = icon or " "
            icon_hl = icon_hl or "Normal"
        end

        local line = string.format("%s%s %s (%s)", prefix, icon, node.name, node.displayKey)
        table.insert(lines, line)

        table.insert(highlights, {
            line = linenr[1],
            ranges = {
                { start = #prefix,             len = #icon,                hl = icon_hl },
                { start = #prefix + #icon + 1, len = #node.name,           hl = icon_hl },
                { start = line:find("%(") - 1, len = #node.displayKey + 2, hl = "Identifier" },
            }
        })

        linenr[1] = linenr[1] + 1

        if node.type == 'directory' and state.expanded_dirs[node.path] and node.children then
            flatten_tree(node.children, indent + 1, lines, highlights, linenr)
        end
    end
end

function M.build_root_tree()
    -- Initialize root path here, as it might change (e.g., cwd can be different at runtime)
    state.root_path = vim.fn.getcwd()
    state.key_bindings = {}
    state.global_actions = {}
    state.expanded_dirs = {}
    state.root_nodes = build_tree(state.root_path, state.key_bindings, "")
end

function M.render_tree()
    if not (state.tree_buf and vim.api.nvim_buf_is_valid(state.tree_buf)) then return end

    local lines, highlights = {}, {}
    flatten_tree(state.root_nodes, 0, lines, highlights, { 0 })

    vim.api.nvim_buf_set_option(state.tree_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(state.tree_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(state.tree_buf, "modifiable", false)

    for _, hl in ipairs(highlights) do
        for _, r in ipairs(hl.ranges) do
            vim.api.nvim_buf_add_highlight(state.tree_buf, -1, r.hl, hl.line, r.start, r.start + r.len)
        end
    end
end

function M.show_tree()
    if state.tree_win and vim.api.nvim_win_is_valid(state.tree_win) then
        vim.api.nvim_set_current_win(state.tree_win)
    else
        local prev_win = vim.api.nvim_get_current_win()
        vim.cmd("topleft vnew")
        vim.cmd("vertical resize " .. TREE_WIDTH)

        state.tree_win = vim.api.nvim_get_current_win()
        state.tree_buf = vim.api.nvim_get_current_buf()

        vim.bo[state.tree_buf].buftype = "nofile"
        vim.bo[state.tree_buf].bufhidden = "wipe"
        vim.bo[state.tree_buf].swapfile = false

        vim.api.nvim_set_current_win(prev_win)
    end

    M.build_root_tree()
    M.render_tree()
end

function M.toggle_tree()
    if state.tree_win and vim.api.nvim_win_is_valid(state.tree_win) then
        vim.api.nvim_win_close(state.tree_win, true)
        state.tree_win, state.tree_buf = nil, nil
    else
        M.show_tree()
    end
end

function M.setup()
    if devicons_ok then
        devicons.setup { default = true, color_icons = true }
    end

    -- Create user command once during setup
    vim.api.nvim_create_user_command("TreeDivers", function()
        M.toggle_tree()
    end, {})
end

return M
