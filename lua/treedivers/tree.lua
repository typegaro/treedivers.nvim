local uv = vim.loop
local keymap = require("treedivers.keymap")
local state = require("treedivers.state").state

local M = {}

function M.build_tree(path, existing_keys, relative_prefix)
    local nodes = {}
    local handle = uv.fs_scandir(path)
    if not handle then return nodes end

    while true do
        local name, type = uv.fs_scandir_next(handle)
        if not name then break end

        local abs_path = path .. "/" .. name
        local rel_path = relative_prefix .. name

        local full_key, displayKey = keymap.generate_unique_key(existing_keys)
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
                            node.children = M.build_tree(abs_path, existing_keys, rel_path .. "/")
                        end
                    end
                    require("treedivers.render").render_tree()
                end
            end

            state.global_actions[full_key] = action
            keymap.register_keymap(full_key, action)
        end
    end

    table.sort(nodes, function(a, b)
        if a.type == b.type then return a.name < b.name end
        return a.type == 'directory'
    end)

    return nodes
end

return M
