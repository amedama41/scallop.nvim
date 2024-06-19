local M = {}

---@class ScallopHooks
---@field init_terminal nil|fun(bufnr: integer)

---@class ScallopOptions
---@field prompt_pattern string
---@field cleanup_key_sequence string
---@field floating_border string|string[]
---@field edit_filetype string
---@field edit_win_options table<string, any>
---@field hooks ScallopHooks

M.configs = {
  options = {
    prompt_pattern = '',
    cleanup_key_sequence = '<C-k><C-u>',
    floating_border = 'rounded',
    edit_filetype = 'bash',
    edit_win_options = {},
    hooks = {
      init_terminal = nil,
    },
  }
}

function M.setup(configs)
  M.configs = vim.tbl_deep_extend('force', M.configs, configs)
end

return M
