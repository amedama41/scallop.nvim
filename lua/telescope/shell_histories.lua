local ok_pickers, pickers = pcall(require, 'telescope.pickers')
local ok_finders, finders = pcall(require, 'telescope.finders')
local ok_config, config = pcall(require, 'telescope.config')
local ok_actions, actions = pcall(require, 'telescope.actions')
local ok_action_state, action_state = pcall(require, 'telescope.actions.state')

if not (ok_pickers and ok_finders and ok_config and ok_actions and ok_action_state) then
  return function()
  end
end

local shell_history_path = '/Users/Macbook/.bash_history'

local shell_histories = function(opts)
  opts = opts or {}
  pickers.new(opts, {
    prompt_title = 'scallop shell histories',
    finder = finders.new_oneshot_job({ 'cat', shell_history_path }),
    sorter = config.values.generic_sorter(opts),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.cmd('ScallopEdit ' .. selection[1])
      end)
      return true
    end,
  }):find()
end

return shell_histories
