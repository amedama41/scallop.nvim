local M = {}

M.configs = {
  options = {
    prompt_pattern = '',
    history_filepath = '',
    history_filter = function(_) return true end,
    cleanup_key_sequence = '<C-k><C-u>',
    floating_border = 'rounded',
    edit_filetype = 'bash',
    edit_win_options = {},
  },
  mappings = {
    normal = {
    },
    insert = {
    },
  }
}

local function merge(dest, source)
  for k, v in pairs(source) do
    if type(v) == 'table' then
      if type(dest[k]) == 'table' then
        merge(dest[k], source[k])
      else
        dest[k] = source[k]
      end
    else
      dest[k] = v
    end
  end
end

function M.setup(configs)
  merge(M.configs, configs)
end

return M
