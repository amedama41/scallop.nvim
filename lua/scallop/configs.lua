local M = {}

M.configs = {
  options = {
    prompt_pattern = '',
    history_filepath = '',
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
      merge(dest[k], source[k])
    else
      dest[k] = v
    end
  end
end

function M.setup(configs)
  merge(M.configs, configs)
end

return M
