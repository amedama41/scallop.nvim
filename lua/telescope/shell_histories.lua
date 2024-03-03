local ok_pickers, pickers = pcall(require, 'telescope.pickers')
local ok_actions, actions = pcall(require, 'telescope.actions')
local ok_action_state, action_state = pcall(require, 'telescope.actions.state')

if not (ok_pickers and ok_actions and ok_action_state) then
  return function()
  end
end

local sorters = require 'telescope.sorters'
local async_oneshot_finder = require "telescope.finders.async_oneshot_finder"
local make_entry = require "telescope.make_entry"

---@param edit_histories string[]
---@param history_filepath string
---@param history_filter fun(data: string): table|nil
---@param opts table
---@param callback fun(cmd: string)
local function shell_histories(edit_histories, history_filepath, history_filter, opts, callback)
  history_filepath = vim.fn.expand(history_filepath)
  opts = opts or {}

  local entry_maker = opts.entry_maker or make_entry.gen_from_string(opts)
  local filter_entry_maker = function(data)
    if not history_filter(data) then
      return nil
    end
    return entry_maker(data)
  end
  local edit_history_entries = {}
  local duplicated_map = {}
  for i = #edit_histories, 1, -1 do
    local v = edit_histories[i]
    if v ~= "" and duplicated_map[v] == nil then
      duplicated_map[v] = true
      local entry = filter_entry_maker(v)
      if entry then
        entry.index = #edit_histories - i + 1
      end
      table.insert(edit_history_entries, entry)
    end
  end

  pickers.new(opts, {
    prompt_title = 'scallop shell histories',
    finder = async_oneshot_finder {

      results = edit_history_entries,
      entry_maker = filter_entry_maker,

      fn_command = function()
        return {
          command = "tail",
          args = { "-r", history_filepath },
        }
      end,
    },
    sorter = sorters.get_substr_matcher(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local cmd = ""
        local selection = action_state.get_selected_entry()
        if selection ~= nil then
          cmd = selection[1]
        else
          local picker = action_state.get_current_picker(prompt_bufnr)
          cmd = vim.fn.getbufoneline(prompt_bufnr, 1):sub(#picker.prompt_prefix + 1)
        end
        actions.close(prompt_bufnr)
        callback(cmd)
      end)
      return true
    end,
  }):find()
end

return shell_histories
