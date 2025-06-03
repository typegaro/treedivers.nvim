local vim = vim

local M = {}

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

function M.generate_unique_key(existing_keys)
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

function M.register_keymap(key, action)
    vim.keymap.set("n", key, action, { noremap = true, silent = true })
end

return M
