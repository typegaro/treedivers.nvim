local uv = vim.loop
local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

---@class Node
---@field name string
---@field path string
---@field type 'file' | 'directory'
---@field key string
---@field displayKey string
---@field children Node[]|nil

local M = {}
local tree_buf = nil
local tree_win = nil
local TREE_WIDTH = 30
local global_actions = {}

local expanded_dirs = {}

local root_path = nil
local root_nodes = {}

-- Generate keys from 'a' to 'z'
local function generate_key_pool()
    local keys = {}
    for i = 97, 122 do table.insert(keys, string.char(i)) end
    return keys
end

-- Generate a unique leader key mapping not used by other mappings
local function generate_unique_key(existing_keys)
    local pool = generate_key_pool()
    math.randomseed(os.time())
    for _ = 1, 1000 do
        local key = ""
        for _ = 1, 2 do
            key = key .. pool[math.random(#pool)]
        end
        local full_key = "<leader>" .. key
        if not existing_keys[full_key] and vim.fn.maparg(full_key, "n") == "" then
            return full_key, key
        end
    end
    return nil, nil
end

-- Build the file/directory tree at a given path
local function build_tree(path, existing_keys)
    local nodes = {}
    local handle = uv.fs_scandir(path)
    if not handle then return nodes end

    while true do
        local name, type = uv.fs_scandir_next(handle)
        if not name then break end
        local full_path = path .. "/" .. name
        local key, displayKey = generate_unique_key(existing_keys)
        if key then
            existing_keys[key] = true
            local node = {
                name = name,
                path = full_path,
                type = type,
                key = key,
                displayKey = displayKey,
                children = type == 'directory' and {} or nil
            }
            table.insert(nodes, node)

            if type == 'file' then
                global_actions[key] = function()
                    vim.cmd("edit " .. full_path)
                end
            else
                global_actions[key] = function()
                    expanded_dirs[full_path] = not expanded_dirs[full_path]
                    M.render_tree()
                end
            end
        end
    end

    table.sort(nodes, function(a, b)
        if a.type == b.type then return a.name < b.name end
        return a.type == 'directory'
    end)

    return nodes
end

-- Flatten the tree nodes into lines for buffer display, handling indentation and icons
local function flatten_tree(nodes, indent, lines)
    for _, node in ipairs(nodes) do
        local prefix = string.rep("  ", indent)
        local icon

        if node.type == 'directory' then
            icon = "📁"
        else
            local ext = node.name:match("^.+%.(.+)$")
            local filetype = ext or ""
            icon = devicons_ok and devicons.get_icon(node.name, filetype) or "📄"
        end

        local line = prefix .. icon .. " " .. node.name .. " " .. "(" .. node.displayKey .. ")"
        table.insert(lines, line)

        if node.type == 'directory' and expanded_dirs[node.path] then
            -- Reload children if directory is expanded
            node.children = build_tree(node.path, {})
            flatten_tree(node.children, indent + 1, lines)
        end
    end
end

-- Build the root tree nodes from the current working directory
function M.build_root_tree()
    root_path = vim.fn.getcwd()
    global_actions = {} -- reset actions to avoid duplicates
    root_nodes = build_tree(root_path, {})
end

-- Render the tree buffer with the current nodes and setup key mappings
function M.render_tree()
    if not (tree_buf and vim.api.nvim_buf_is_valid(tree_buf)) then return end

    local lines = {}
    flatten_tree(root_nodes, 0, lines)

    vim.api.nvim_buf_set_option(tree_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(tree_buf, "modifiable", false)

    for key, action in pairs(global_actions) do
        vim.keymap.set("n", key, action, { noremap = true, silent = true })
    end
end

-- Show the tree window or create it if it doesn't exist
function M.show_tree()
    if tree_win and vim.api.nvim_win_is_valid(tree_win) then
        vim.api.nvim_set_current_win(tree_win)
    else
        local prev_win = vim.api.nvim_get_current_win()

        vim.cmd("topleft vnew")
        vim.cmd("vertical resize " .. TREE_WIDTH)
        tree_win = vim.api.nvim_get_current_win()
        tree_buf = vim.api.nvim_get_current_buf()

        vim.api.nvim_buf_set_option(tree_buf, "buftype", "nofile")
        vim.api.nvim_buf_set_option(tree_buf, "bufhidden", "wipe")
        vim.api.nvim_buf_set_option(tree_buf, "swapfile", false)

        vim.api.nvim_set_current_win(prev_win)
    end

    M.build_root_tree()
    M.render_tree()
end

-- Toggle the visibility of the tree window
function M.toggle_tree()
    if tree_win and vim.api.nvim_win_is_valid(tree_win) then
        local wins = vim.api.nvim_list_wins()
        if #wins == 1 then
            -- If the only window is the tree, close and reset
            vim.api.nvim_win_close(tree_win, true)
            tree_win = nil
            tree_buf = nil
        else
            -- Otherwise just close the tree window
            vim.api.nvim_win_close(tree_win, true)
            tree_win = nil
            tree_buf = nil
        end
    else
        M.show_tree()
    end
end

-- Setup function to initialize devicons and command
M.setup = function()
    if devicons_ok then
        require('nvim-web-devicons').setup {
            color_icons = true,
            default = true,
        }
    end

    vim.api.nvim_create_user_command("TreeDivers", function()
        M.toggle_tree()
    end, {})
end

return M
