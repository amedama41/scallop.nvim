local source = {}

local default_option = {
  history_filepath = "~/.bash_history",
}

---@param items { label: string, kind: number }[]
---@param lines string[]
---@param duplicated table<string, boolean>
local function to_item(items, lines, duplicated)
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line and not duplicated[line] then
      duplicated[line] = true
      items[#items + 1] = { label = line, kind = 1 }
    end
  end
end

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_keyword_pattern()
  return '.*'
end

function source:complete(params, callback)
  local option = vim.tbl_extend("keep", params.option, default_option)
  local history_filepath = vim.fn.expand(option.history_filepath)

  local currpos = vim.api.nvim_win_get_cursor(0)
  local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  table.remove(buffer_lines, currpos[1])
  local items = {}
  local duplicated = {}
  to_item(items, buffer_lines, duplicated)

  local fd = vim.loop.fs_open(history_filepath, "r", 0)
  if fd == nil then
    return callback({ items = items })
  end

  local stat = vim.loop.fs_fstat(fd)
  if stat == nil then
    vim.loop.fs_close(stat)
    return callback{ items = items }()
  end

  vim.loop.fs_read(fd, stat.size, nil, function(err, data)
    vim.loop.fs_close(fd)
    if err ~= nil then
      callback{ items = items }()
    end
    local lines = vim.split(data, "\n", { plain = true })
    to_item(items, lines, duplicated)
    callback({ items = items })
  end)
end

return source
