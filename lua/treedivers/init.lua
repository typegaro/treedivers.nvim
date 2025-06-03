local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

local tree = require("treedivers.tree")
local render = require("treedivers.render")
local state = require("treedivers.state").state

local M = {}

local TREE_WIDTH = 30

function M.build_root_tree()
    state.root_path = vim.fn.getcwd()
    state.key_bindings = {}
    state.global_actions = {}
    state.expanded_dirs = {}
    state.root_nodes = tree.build_tree(state.root_path, state.key_bindings, "")
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
    render.render_tree()
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

    vim.api.nvim_create_user_command("TreeDivers", function()
        M.toggle_tree()
    end, {})
end

return M
