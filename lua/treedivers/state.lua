local M = {}

M.state = {
    root_path = "",
    root_nodes = {},
    expanded_dirs = {},
    key_bindings = {},
    global_actions = {},
    tree_buf = nil,
    tree_win = nil,
}

return M
