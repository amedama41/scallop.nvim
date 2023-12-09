local ok_pickers, pickers = pcall(require, 'telescope.pickers')
local ok_config, config = pcall(require, 'telescope.config')
local ok_actions, actions = pcall(require, 'telescope.actions')
local ok_action_state, action_state = pcall(require, 'telescope.actions.state')

if not (ok_pickers and ok_config and ok_actions and ok_action_state) then
  return function()
  end
end

local async_oneshot_finder = require "telescope.finders.async_oneshot_finder"
local make_entry = require "telescope.make_entry"

local shell_histories = function(edit_histories, history_filepath, opts, callback)
  history_filepath = vim.fn.expand(history_filepath)
  opts = opts or {}

  local entry_maker = opts.entry_maker or make_entry.gen_from_string(opts)
  local edit_history_entries = {}
  for _, v in ipairs(edit_histories) do
    if v ~= "" then
      table.insert(edit_history_entries, entry_maker(v))
    end
  end

  pickers.new(opts, {
    prompt_title = 'scallop shell histories',
    finder = async_oneshot_finder {

      results = edit_history_entries,

      fn_command = function()
        return {
          command = "tail",
          args = { "-r", history_filepath },
        }
      end,
    },
    sorter = config.values.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        callback(selection[1])
      end)
      return true
    end,
  }):find()
end

return shell_histories
