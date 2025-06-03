local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
local vim = vim
local state = require("treedivers.state").state

local M = {}

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

        local line = string.format("%s(%s) %s %s", prefix, node.displayKey, icon, node.name)
        table.insert(lines, line)

        local prefix_width = vim.fn.strdisplaywidth(prefix)
        local key_width = vim.fn.strdisplaywidth("(" .. node.displayKey .. ")")
        local icon_width = vim.fn.strdisplaywidth(icon) + 1
        local name_width = vim.fn.strdisplaywidth(node.name) + 2

        table.insert(highlights, {
            line = linenr[1],
            ranges = {
                { start = prefix_width,                                  len = key_width,  hl = "Identifier" },
                { start = prefix_width + key_width + 1,                  len = icon_width, hl = icon_hl },
                { start = prefix_width + key_width + 1 + icon_width + 1, len = name_width, hl = icon_hl },
            }
        })

        linenr[1] = linenr[1] + 1

        if node.type == 'directory' and state.expanded_dirs[node.path] and node.children then
            flatten_tree(node.children, indent + 1, lines, highlights, linenr)
        end
    end
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

return M
