local source = {}

local default_option = {
  history_filepath = "~/.bash_history",
  max_display_command_length = 150,
}

function source.new()
  return setmetatable({}, { __index = source })
end

function source:get_keyword_pattern()
  return '.*'
end

function source:complete(params, callback)
  local option = vim.tbl_extend("keep", params.option, default_option)
  local history_filepath = vim.fn.expand(option.history_filepath)
  local max_display_command_length = option.max_display_command_length

  local items = {}
  local duplicated = {}
  local jobid = vim.fn.jobstart({ "tail", "-r", history_filepath }, {
    clear_env = true,
    detach = false,
    on_stdout = function(_, data, _)
      for _, line in pairs(data) do
        if line and not duplicated[line] then
          duplicated[line] = true
          local label = line
          if #label > max_display_command_length then
            label = line:sub(1, max_display_command_length) .. "..."
          end
          items[#items + 1] = { label = label, insertText = line, kind = 1 }
        end
      end
      callback({ items = items })
    end,
    stdout_buffered = true,
  })
  if jobid <= 0 then
    return callback()
  end
end

return source
