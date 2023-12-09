local configs = require('scallop.configs')
local shell_histories = require('telescope.shell_histories')

local Scallop = {}
Scallop.__index = Scallop
Scallop.tabpage_handles = {}

function Scallop.new()
  local data = {
    terminal_job_id = -1,
    terminal_bufnr = -1,
    terminal_winid = -1,
    edit_bufnr = -1,
    edit_winid = -1,
    prev_winid = -1,
    options = vim.deepcopy(configs.configs.options),
  }

  local self = setmetatable({
    _data = data,
  }, Scallop)

  vim.t.scallop_data = data
  return self
end

function Scallop.from_data(data)
  return setmetatable({
    _data = data,
  }, Scallop)
end

function Scallop:save()
  vim.t.scallop_data = self._data
end

function Scallop:terminate()
  if self._data.terminal_job_id ~= -1 then
    vim.fn.jobstop(self._data.terminal_job_id)
  end

  if self._data.terminal_bufnr ~= -1 then
    vim.api.nvim_buf_delete(self._data.terminal_bufnr, { force = true })
    self._data.terminal_bufnr = -1
  end

  self:delete_edit_buffer()
end

function Scallop:jobsend(cmd, options)
  if self._data.terminal_job_id == -1 then
    return
  end

  if options.cleanup then
    cmd = vim.api.nvim_replace_termcodes(self._data.options.cleanup_key_sequence, true, true, true) .. cmd
  end
  if options.newline then
    cmd = cmd .. vim.api.nvim_replace_termcodes("<CR>", true, true, true)
  end

  vim.fn.chansend(self._data.terminal_job_id, cmd)
end

function Scallop:open_terminal_window()
  if self._data.terminal_bufnr == -1 then
    self._data.terminal_bufnr = vim.fn.bufadd('')
  end

  self._data.terminal_winid = vim.api.nvim_open_win(self._data.terminal_bufnr, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = vim.o.columns - 6,
    height = vim.o.lines - 6,
    border = self._data.options.floating_border,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(self._data.terminal_winid),
    once = true,
    callback = function()
      local scallop_data = vim.t.scallop_data
      if scallop_data ~= nil then
        local scallop = Scallop.from_data(scallop_data)
        scallop:closed_terminal_window()
      end
    end,
  })
end

function Scallop:init_terminal_buffer(cwd)
  if cwd ~= nil and vim.fn.isdirectory(cwd) then
    self._data.terminal_job_id = vim.fn.termopen(vim.o.shell, { cwd = cwd })
  else
    self._data.terminal_job_id = vim.fn.termopen(vim.o.shell)
  end

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = self._data.terminal_bufnr,
    callback = function()
      local scallop_data = vim.t.scallop_data
      if scallop_data == nil then
        return
      end

      local scallop = Scallop.from_data(scallop_data)
      scallop:delete_edit_buffer()

      vim.fn.win_execute(scallop._data.terminal_winid, 'stopinsert', 'silent')

      vim.t.scallop_data = nil
    end,
  })

  local keymap_opt = { buffer = self._data.terminal_bufnr }

  vim.keymap.set('n', 'q', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:close_terminal()
  end, keymap_opt)

  vim.keymap.set('n', 'e', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:start_edit()
  end, keymap_opt)

  vim.keymap.set('n', '<C-n>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:jump_to_prompt('forward')
  end, keymap_opt)

  vim.keymap.set('n', '<C-p>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:jump_to_prompt('backward')
  end, keymap_opt)
end

function Scallop:start_terminal(cwd)
  self._data.prev_winid = vim.fn.win_getid()
  if self._data.terminal_bufnr == -1 then
    self:open_terminal_window()
    self:init_terminal_buffer(cwd)
    self:save()
  elseif self._data.terminal_winid == -1 then
    self:open_terminal_window()
    self:save()
    if cwd ~= nil and vim.fn.isdirectory(cwd) then
      self:terminal_cd(cwd)
    end
  else
    vim.fn.win_gotoid(self._data.terminal_winid)
    if cwd ~= nil and vim.fn.isdirectory(cwd) then
      self:terminal_cd(cwd)
    end
  end
end

function Scallop:terminal_cd(directory)
  if not vim.fn.isdirectory(directory) then
    return
  end

  local cwd = self:get_terminal_cwd()
  if vim.fs.normalize(cwd) == vim.fs.normalize(directory) then
    return
  end

  self:jobsend(' cd ' .. vim.fn.shellescape(directory), { cleanup = true, newline = true })
end

function Scallop:get_terminal_cwd()
  if vim.fn.executable('lsof') then
    local cmd = { 'lsof', '-a', '-d', 'cwd', '-p', tostring(vim.fn.jobpid(self._data.terminal_job_id)) }
    local stdout = vim.fn.system(table.concat(cmd, ' '))
    local cwd = vim.fn.matchstr(stdout, 'cwd\\s\\+\\S\\+\\s\\+\\S\\+\\s\\+\\S\\+\\s\\+\\S\\+\\s\\+\\zs.\\+\\ze\\n')
    if vim.fn.isdirectory(cwd) then
      return cwd
    end
  end
  return vim.fn.getcwd(self._data.terminal_winid)
end

function Scallop:jump_to_prompt(direction)
  if self._data.options.prompt_pattern == '' then
    return
  end

  local flags = nil
  if direction == 'forward' then
    flags = 'enWz'
  else
    flags = 'benWz'
  end

  local search_pos = vim.api.nvim_buf_call(self._data.terminal_bufnr, function()
    return vim.fn.searchpos('^' .. self._data.options.prompt_pattern, flags)
  end)

  if search_pos[1] ~= 0 then
    vim.api.nvim_win_set_cursor(self._data.terminal_winid, search_pos)
  end
end

function Scallop:close_terminal()
  if self._data.terminal_winid ~= -1 then
    vim.api.nvim_win_close(self._data.terminal_winid, true)
    vim.fn.win_gotoid(self._data.prev_winid)
    self:closed_terminal_window()
  end
end

function Scallop:closed_terminal_window()
  self:close_edit()
  self._data.terminal_winid = -1
  self:save()
end

function Scallop:open_edit_window()
  if self._data.edit_bufnr == -1 then
    self._data.edit_bufnr = vim.fn.bufadd('scallop-edit@' .. vim.fn.bufname(self._data.terminal_bufnr))
  end

  self._data.edit_winid = vim.api.nvim_open_win(self._data.edit_bufnr, true, {
    relative = 'editor',
    row = 1 + vim.o.columns - 6,
    col = 1,
    width = vim.fn.winwidth(self._data.terminal_winid),
    height = 1,
    border = self._data.options.floating_border,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(self._data.edit_winid),
    once = true,
    callback = function()
      local scallop_data = vim.t.scallop_data
      if scallop_data ~= nil then
        local scallop = Scallop.from_data(scallop_data)
        scallop:closed_edit_window()
      end
    end,
  })
end

function Scallop:init_edit_buffer()
  vim.bo[self._data.edit_bufnr].bufhidden = 'hide'
  vim.bo[self._data.edit_bufnr].buftype = 'nowrite'
  vim.bo[self._data.edit_bufnr].buflisted = false
  vim.bo[self._data.edit_bufnr].swapfile = false
  vim.bo[self._data.edit_bufnr].filetype = self._data.options.edit_filetype

  local keymap_opt = { buffer = self._data.edit_bufnr }

  vim.keymap.set('n', '<CR>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:execute_command(false)
  end, keymap_opt)
  vim.keymap.set('n', '<C-n>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:jump_to_prompt('forward')
  end, keymap_opt)
  vim.keymap.set('n', '<C-p>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:jump_to_prompt('backward')
  end, keymap_opt)
  vim.keymap.set('n', 'q', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:close_edit()
  end, keymap_opt)
  vim.keymap.set('n', 'Q', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:close_terminal()
  end, keymap_opt)

  vim.keymap.set('i', '<CR>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:execute_command(false)
  end, keymap_opt)
  vim.keymap.set('i', '<C-c>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:send_ctrl('<C-c>')
  end, keymap_opt)
  vim.keymap.set('i', '<C-d>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:send_ctrl('<C-d>')
  end, keymap_opt)
  vim.keymap.set('n', '<C-k>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    shell_histories(scallop._data.options.history_filepath, { default_text = scallop:get_edit_line('.') }, function(cmd)
      vim.defer_fn(function() scallop:start_edit(cmd, true) end, 0)
    end)
  end, keymap_opt)
  vim.keymap.set('i', '<C-k>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    shell_histories(scallop._data.options.history_filepath, { default_text = scallop:get_edit_line('.') }, function(cmd)
      vim.defer_fn(function() scallop:start_edit(cmd, true) end, 0)
    end)
  end, keymap_opt)

  vim.keymap.set('x', '<CR>', function()
    local scallop = Scallop.from_data(vim.t.scallop_data)
    scallop:execute_command(true)
    vim.fn.win_execute(self._data.edit_winid, "normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, true, true), 'silent')
  end, keymap_opt)
end

function Scallop:delete_edit_buffer()
  if self._data.edit_bufnr ~= -1 then
    local current_win = vim.fn.win_getid()
    vim.api.nvim_buf_delete(self._data.edit_bufnr, { force = true })
    self._data.edit_bufnr = -1
    if current_win == self._data.edit_winid then
      vim.fn.win_gotoid(self._data.terminal_winid)
    end
  end
end

function Scallop:get_edit_line(pos)
  return vim.fn.getbufoneline(self._data.edit_bufnr, vim.fn.line(pos, self._data.edit_winid))
end

function Scallop:get_select_lines()
  local first = vim.fn.line("v", self._data.edit_winid)
  local last = vim.fn.line(".", self._data.edit_winid)
  if first > last then
    first, last = last, first
  end
  return table.concat(vim.fn.getbufline(self._data.edit_bufnr, first, last), '\n')
end

function Scallop:start_edit(initial_cmd, does_insert)
  if self._data.edit_bufnr == -1 then
    self:open_edit_window()
    self:init_edit_buffer()
    self:save()
  elseif self._data.edit_winid == -1 then
    self:open_edit_window()
    self:save()
  else
    vim.fn.win_gotoid(self._data.edit_winid)
  end

  local cwd = self:get_terminal_cwd()
  vim.fn.win_execute(self._data.edit_winid, 'lcd ' .. cwd, 'silent')

  vim.fn.win_execute(self._data.edit_winid, 'startinsert!', 'silent')

  if initial_cmd ~= nil then
    local cursor_column = 0
    if does_insert then
      cursor_column = #initial_cmd
    end

    local current_line = self:get_edit_line('.')
    if #current_line == 0 then
      vim.api.nvim_put({ initial_cmd }, 'c', true, false)
      vim.api.nvim_win_set_cursor(self._data.edit_winid, { vim.fn.line('.', self._data.edit_winid), cursor_column })
    else
      vim.fn.appendbufline(self._data.edit_bufnr, vim.fn.line('$', self._data.edit_winid), initial_cmd)
      vim.api.nvim_win_set_cursor(self._data.edit_winid, { vim.fn.line('$', self._data.edit_winid), cursor_column })
    end
  end
end

function Scallop:execute_command(is_select)
  if self._data.edit_bufnr == -1 or self._data.edit_winid == -1 then
    return
  end

  local cmd
  if is_select then
    cmd = self:get_select_lines()
  else
    cmd = self:get_edit_line('.')
  end
  self:jobsend(cmd, { cleanup = true, newline = true })

  -- Scroll terminal to bottom
  vim.fn.win_execute(self._data.terminal_winid, 'normal! G', 'silent')

  local last_line = self:get_edit_line('$')
  if last_line ~= cmd then
    local append_line = vim.fn.line('$', self._data.edit_winid)
    if vim.fn.match(last_line, '^\\s*$') ~= -1 then
      append_line = math.max(append_line - 1, 0)
    end
    vim.fn.appendbufline(self._data.edit_bufnr, append_line, cmd)
  end

  last_line = self:get_edit_line('$')
  if vim.fn.match(last_line, '^\\s*$') == -1 then
    vim.fn.appendbufline(self._data.edit_bufnr, vim.fn.line('$', self._data.edit_winid), '')
  end

  vim.api.nvim_win_set_cursor(self._data.edit_winid, { vim.fn.line('$', self._data.edit_winid), 0 })

  local cwd = self:get_terminal_cwd()
  vim.fn.win_execute(self._data.edit_winid, 'lcd ' .. cwd, 'silent')
end

function Scallop:send_ctrl(ctrl)
  if self._data.edit_bufnr == -1 or self._data.edit_winid == -1 then
    return
  end
  self:jobsend(vim.api.nvim_replace_termcodes(ctrl, true, true, true), { cleanup = false, newline = false })

  -- Scroll terminal to bottom
  vim.fn.win_execute(self._data.terminal_winid, 'normal! G', 'silent')
end

function Scallop:close_edit()
  if self._data.edit_winid ~= -1 then
    vim.api.nvim_win_close(self._data.edit_winid, true)
    vim.fn.win_gotoid(self._data.terminal_winid)
    self:closed_edit_window()
  end
end

function Scallop:closed_edit_window()
  self._data.edit_winid = -1
  self:save()

  if self._data.terminal_winid ~= -1 then
    vim.fn.win_gotoid(self._data.terminal_winid)
  end
end

local M = {}

function M.start_terminal(cwd)
  local scallop = nil
  local scallop_data = vim.t.scallop_data
  if scallop_data then
    scallop = Scallop.from_data(scallop_data)
  else
    scallop = Scallop.new()
    Scallop.tabpage_handles[vim.api.nvim_get_current_tabpage()] = true
  end
  scallop:start_terminal(cwd)
end

function M.start_terminal_edit(cmd, cwd)
  local scallop = nil
  local scallop_data = vim.t.scallop_data
  if scallop_data then
    scallop = Scallop.from_data(scallop_data)
  else
    scallop = Scallop.new()
    Scallop.tabpage_handles[vim.api.nvim_get_current_tabpage()] = true
  end
  scallop:start_terminal(cwd)
  scallop:start_edit(cmd)
end

vim.api.nvim_create_autocmd('TabClosed', {
  group = vim.api.nvim_create_augroup('scallop-settings', { clear = true }),
  callback = function()
    for tabpage, _ in pairs(Scallop.tabpage_handles) do
      Scallop.tabpage_handles[tabpage] = false
    end

    for _, tabpage in pairs(vim.api.nvim_list_tabpages()) do
      if Scallop.tabpage_handles[tabpage] ~= nil then
        Scallop.tabpage_handles[tabpage] = true
      end
    end

    for tabpage, living in pairs(Scallop.tabpage_handles) do
      if not living then
        local scallop_data = vim.t[tabpage].scallop_data
        if scallop_data ~= nil then
          local scallop = Scallop.from_data(scallop_data)
          scallop:terminate()
          vim.t[tabpage].scallop_data = nil
        end

        Scallop.tabpage_handles[tabpage] = nil
      end
    end
  end,
})

return M
