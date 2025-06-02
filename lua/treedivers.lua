local uv = vim.loop
local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

---@class Node
---@field name string
---@field path string
---@field type 'file' | 'directory'
---@field key string
---@field displayKey string
---@field children Node[]?

local M = {}

local tree_buf, tree_win = nil, nil
local TREE_WIDTH = 30

local global_actions = {}
local expanded_dirs = {}
local root_path = ""
local root_nodes = {}

-- Generate keys from 'a' to 'z'
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

-- Build the directory/file tree recursively with a shared existing_keys table
local function build_tree(path, existing_keys)
    local nodes = {}
    local handle = uv.fs_scandir(path)
    if not handle then return nodes end

    while true do
        local name, type = uv.fs_scandir_next(handle)
        if not name then break end

        local full_path = path
        if not full_path:match("/$") then
            full_path = full_path .. "/"
        end
        full_path = full_path .. name

        local key, displayKey = generate_unique_key(existing_keys)
        if key then
            existing_keys[key] = true

            local node = {
                name = name,
                path = full_path,
                type = type,
                key = key,
                displayKey = displayKey,
                children = type == 'directory' and {} or nil,
            }

            table.insert(nodes, node)

            global_actions[key] = (type == 'file')
                and function() vim.cmd.edit(full_path) end
                or function()
                    expanded_dirs[full_path] = not expanded_dirs[full_path]
                    -- Ricostruisci l'intero albero da root con la stessa existing_keys
                    root_nodes = build_tree(root_path, existing_keys)
                    M.render_tree()

                    -- Riassegna le keymap globali
                    for key, action in pairs(global_actions) do
                        vim.keymap.set("n", key, action, { noremap = true, silent = true })
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

-- Flatten nodes into lines and highlight metadata; pass existing_keys for consistency
local function flatten_tree(nodes, indent, lines, highlights, linenr, existing_keys)
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
                { start = #prefix,             len = #icon,                hl = icon_hl }, -- icona colorata
                { start = #prefix + #icon + 1, len = #node.name,           hl = icon_hl }, -- nome file stesso colore icona
                { start = line:find("%(") - 1, len = #node.displayKey + 2, hl = "Identifier" },
            }
        })

        linenr[1] = linenr[1] + 1

        if node.type == 'directory' and expanded_dirs[node.path] then
            node.children = build_tree(node.path, existing_keys)
            flatten_tree(node.children, indent + 1, lines, highlights, linenr, existing_keys)
        end
    end
end

-- Build the tree from the current directory with a fresh existing_keys table
function M.build_root_tree()
    root_path = vim.fn.getcwd()
    global_actions = {}
    local existing_keys = {}
    root_nodes = build_tree(root_path, existing_keys)
end

-- Render lines and apply highlights, passing a fresh existing_keys for flatten_tree
function M.render_tree()
    if not (tree_buf and vim.api.nvim_buf_is_valid(tree_buf)) then return end

    local lines, highlights = {}, {}
    flatten_tree(root_nodes, 0, lines, highlights, { 0 }, {})

    vim.api.nvim_buf_set_option(tree_buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(tree_buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(tree_buf, "modifiable", false)

    -- Apply highlights
    for _, hl in ipairs(highlights) do
        for _, r in ipairs(hl.ranges) do
            vim.api.nvim_buf_add_highlight(tree_buf, -1, r.hl, hl.line, r.start, r.start + r.len)
        end
    end
end

-- Create or reuse the tree window
function M.show_tree()
    if tree_win and vim.api.nvim_win_is_valid(tree_win) then
        vim.api.nvim_set_current_win(tree_win)
    else
        local prev_win = vim.api.nvim_get_current_win()

        vim.cmd("topleft vnew")
        vim.cmd("vertical resize " .. TREE_WIDTH)

        tree_win = vim.api.nvim_get_current_win()
        tree_buf = vim.api.nvim_get_current_buf()

        vim.bo[tree_buf].buftype = "nofile"
        vim.bo[tree_buf].bufhidden = "wipe"
        vim.bo[tree_buf].swapfile = false

        vim.api.nvim_set_current_win(prev_win)
    end

    M.build_root_tree()
    M.render_tree()

    -- Mappature globali (non limitate al buffer)
    for key, action in pairs(global_actions) do
        vim.keymap.set("n", key, action, { noremap = true, silent = true })
    end
end

-- Toggle the tree window on/off
function M.toggle_tree()
    if tree_win and vim.api.nvim_win_is_valid(tree_win) then
        vim.api.nvim_win_close(tree_win, true)
        tree_win, tree_buf = nil, nil
    else
        M.show_tree()
    end
end

-- Plugin setup
function M.setup()
    if devicons_ok then
        devicons.setup { default = true, color_icons = true }
    end

    vim.api.nvim_create_user_command("TreeDivers", function()
        M.toggle_tree()
    end, {})
end

return M
