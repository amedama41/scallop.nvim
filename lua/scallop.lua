local configs = require('scallop.configs')
local shell_histories = require('telescope.shell_histories')

---@class Scallop
---@field private _terminal_job_id integer
---@field private _terminal_bufnr integer
---@field private _terminal_winid integer
---@field private _edit_bufnr integer
---@field private _edit_winid integer
---@field private _prev_winid integer
---@field private _options table
---@field package _living boolean
---@field private _tabpage_handle unknown
local Scallop = {}
Scallop.__index = Scallop
---@type table<unknown, Scallop>
Scallop.tabpage_scallops = {}

function Scallop.new()
  local self = setmetatable({
    _terminal_job_id = -1,
    _terminal_bufnr = -1,
    _terminal_winid = -1,
    _edit_bufnr = -1,
    _edit_winid = -1,
    _prev_winid = -1,
    _options = vim.deepcopy(configs.configs.options),
    _living = true,
    _tabpage_handle = vim.api.nvim_get_current_tabpage(),
  }, Scallop)

  Scallop.tabpage_scallops[self._tabpage_handle] = self

  return self
end

function Scallop:terminate()
  if self._terminal_job_id ~= -1 then
    vim.fn.jobstop(self._terminal_job_id)
    self._terminal_job_id = -1
  end

  if self._terminal_bufnr ~= -1 then
    vim.api.nvim_buf_delete(self._terminal_bufnr, { force = true })
    self._terminal_bufnr = -1
  end

  self:delete_edit_buffer()

  self._living = false
  Scallop.tabpage_scallops[self._tabpage_handle] = nil
end

---@private
---@param cmd string
---@param options { cleanup: boolean, newline: boolean }
function Scallop:jobsend(cmd, options)
  if self._terminal_job_id == -1 then
    return
  end

  if options.cleanup then
    cmd = vim.api.nvim_replace_termcodes(self._options.cleanup_key_sequence, true, true, true) .. cmd
  end
  if options.newline then
    cmd = cmd .. vim.api.nvim_replace_termcodes("<CR>", true, true, true)
  end

  vim.fn.chansend(self._terminal_job_id, cmd)
end

---@private
---@private
function Scallop:open_terminal_window()
  if self._terminal_bufnr == -1 then
    self._terminal_bufnr = vim.fn.bufadd('')
  end

  self._terminal_winid = vim.api.nvim_open_win(self._terminal_bufnr, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = vim.o.columns - 6,
    height = vim.o.lines - 6,
    border = self._options.floating_border,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(self._terminal_winid),
    once = true,
    callback = function()
      if self._living then
        self:closed_terminal_window()
      end
    end,
  })
end

---@private
---@param cwd? string
function Scallop:init_terminal_buffer(cwd)
  if cwd ~= nil and vim.fn.isdirectory(cwd) then
    self._terminal_job_id = vim.fn.termopen(vim.o.shell, { cwd = cwd })
  else
    self._terminal_job_id = vim.fn.termopen(vim.o.shell)
  end

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = self._terminal_bufnr,
    callback = function()
      if not self._living then
        return
      end

      vim.fn.win_execute(self._terminal_winid, 'stopinsert', 'silent')

      self._terminal_job_id = -1
      self:terminate()
    end,
  })

  local keymap_opt = { buffer = self._terminal_bufnr }

  vim.keymap.set('n', 'q', function()
    if self._living then
      self:close_terminal()
    end
  end, keymap_opt)

  vim.keymap.set('n', 'e', function()
    if self._living then
      self:start_edit()
    end
  end, keymap_opt)

  vim.keymap.set('n', '<C-n>', function()
    if self._living then
      self:jump_to_prompt('forward')
    end
  end, keymap_opt)

  vim.keymap.set('n', '<C-p>', function()
    if self._living then
      self:jump_to_prompt('backward')
    end
  end, keymap_opt)
end

---@package
---@param cwd? string
function Scallop:start_terminal(cwd)
  self._prev_winid = vim.fn.win_getid()
  if self._terminal_bufnr == -1 then
    self:open_terminal_window()
    self:init_terminal_buffer(cwd)
  elseif self._terminal_winid == -1 then
    self:open_terminal_window()
    if cwd ~= nil and vim.fn.isdirectory(cwd) then
      self:terminal_cd(cwd)
    end
  else
    vim.fn.win_gotoid(self._terminal_winid)
    if cwd ~= nil and vim.fn.isdirectory(cwd) then
      self:terminal_cd(cwd)
    end
  end
end

---@private
---@param directory string
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

---@private
---@return string
function Scallop:get_terminal_cwd()
  if vim.fn.executable('lsof') then
    local cmd = { 'lsof', '-a', '-d', 'cwd', '-p', tostring(vim.fn.jobpid(self._terminal_job_id)) }
    local stdout = vim.fn.system(table.concat(cmd, ' '))
    local cwd = vim.fn.matchstr(stdout, 'cwd\\s\\+\\S\\+\\s\\+\\S\\+\\s\\+\\S\\+\\s\\+\\S\\+\\s\\+\\zs.\\+\\ze\\n')
    if vim.fn.isdirectory(cwd) then
      return cwd
    end
  end
  return vim.fn.getcwd(self._terminal_winid)
end

---@private
---@param direction string
function Scallop:jump_to_prompt(direction)
  if self._options.prompt_pattern == '' then
    return
  end

  local flags = nil
  if direction == 'forward' then
    flags = 'enWz'
  else
    flags = 'benWz'
  end

  local search_pos = vim.api.nvim_buf_call(self._terminal_bufnr, function()
    return vim.fn.searchpos('^' .. self._options.prompt_pattern, flags)
  end)

  if search_pos[1] ~= 0 then
    vim.api.nvim_win_set_cursor(self._terminal_winid, search_pos)
  end
end

---@private
function Scallop:close_terminal()
  if self._terminal_winid ~= -1 then
    vim.api.nvim_win_close(self._terminal_winid, true)
    self:closed_terminal_window()
  end
end

---@private
function Scallop:closed_terminal_window()
  self._terminal_winid = -1
  self:close_edit()
  vim.fn.win_gotoid(self._prev_winid)
end

---@private
function Scallop:open_edit_window()
  if self._edit_bufnr == -1 then
    self._edit_bufnr = vim.fn.bufadd('scallop-edit@' .. vim.fn.bufname(self._terminal_bufnr))
  end

  self._edit_winid = vim.api.nvim_open_win(self._edit_bufnr, true, {
    relative = 'editor',
    row = 1 + vim.o.columns - 6,
    col = 1,
    width = vim.fn.winwidth(self._terminal_winid),
    height = 1,
    border = self._options.floating_border,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(self._edit_winid),
    once = true,
    callback = function()
      if self._living then
        self:closed_edit_window()
      end
    end,
  })
end

---@private
function Scallop:init_edit_buffer()
  vim.bo[self._edit_bufnr].bufhidden = 'hide'
  vim.bo[self._edit_bufnr].buftype = 'nowrite'
  vim.bo[self._edit_bufnr].buflisted = false
  vim.bo[self._edit_bufnr].swapfile = false
  vim.bo[self._edit_bufnr].filetype = self._options.edit_filetype

  local keymap_opt = { buffer = self._edit_bufnr }

  vim.keymap.set('n', '<CR>', function()
    if self._living then
      self:execute_command(false)
    end
  end, keymap_opt)
  vim.keymap.set('n', '<C-n>', function()
    if self._living then
      self:jump_to_prompt('forward')
    end
  end, keymap_opt)
  vim.keymap.set('n', '<C-p>', function()
    if self._living then
      self:jump_to_prompt('backward')
    end
  end, keymap_opt)
  vim.keymap.set('n', 'q', function()
    if self._living then
      self:close_edit()
    end
  end, keymap_opt)
  vim.keymap.set('n', '<C-q>', function()
    if self._living then
      self:close_terminal()
    end
  end, keymap_opt)
  vim.keymap.set('i', '<C-q>', function()
    if self._living then
      self:close_terminal()
    end
  end, keymap_opt)

  vim.keymap.set('i', '<CR>', function()
    if self._living then
      self:execute_command(false)
    end
  end, keymap_opt)
  vim.keymap.set('i', '<C-c>', function()
    if self._living then
      self:send_ctrl('<C-c>')
    end
  end, keymap_opt)
  vim.keymap.set('i', '<C-d>', function()
    if self._living then
      self:send_ctrl('<C-d>')
    end
  end, keymap_opt)
  vim.keymap.set('n', '<C-k>', function()
    if self._living then
      shell_histories(self:get_edit_all_lines(), self._options.history_filepath, { default_text = self:get_edit_line('.') }, function(cmd)
        vim.defer_fn(function() self:start_edit(cmd, true) end, 0)
      end)
    end
  end, keymap_opt)
  vim.keymap.set('i', '<C-k>', function()
    if self._living then
      shell_histories(self:get_edit_all_lines(), self._options.history_filepath, { default_text = self:get_edit_line('.') }, function(cmd)
        vim.defer_fn(function() self:start_edit(cmd, true) end, 0)
      end)
    end
  end, keymap_opt)

  vim.keymap.set('x', '<CR>', function()
    if self._living then
      self:execute_command(true)
      vim.fn.win_execute(self._edit_winid, "normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, true, true), 'silent')
    end
  end, keymap_opt)
end

---@private
function Scallop:delete_edit_buffer()
  if self._edit_bufnr ~= -1 then
    local current_win = vim.fn.win_getid()
    vim.api.nvim_buf_delete(self._edit_bufnr, { force = true })
    self._edit_bufnr = -1
    if current_win == self._edit_winid then
      vim.fn.win_gotoid(self._terminal_winid)
    end
  end
end

---@private
---@param pos string
---@return string
function Scallop:get_edit_line(pos)
  return vim.fn.getbufoneline(self._edit_bufnr, vim.fn.line(pos, self._edit_winid))
end

---@private
---@return string
function Scallop:get_select_lines()
  local first = vim.fn.line("v", self._edit_winid)
  local last = vim.fn.line(".", self._edit_winid)
  if first > last then
    first, last = last, first
  end
  return table.concat(vim.fn.getbufline(self._edit_bufnr, first, last), '\n')
end

---@private
---@return string[]
function Scallop:get_edit_all_lines()
  return vim.fn.getbufline(self._edit_bufnr, 1, "$")
end

---@package
---@param initial_cmd? string
---@param does_insert? boolean
function Scallop:start_edit(initial_cmd, does_insert)
  if self._edit_bufnr == -1 then
    self:open_edit_window()
    self:init_edit_buffer()
  elseif self._edit_winid == -1 then
    self:open_edit_window()
  else
    vim.fn.win_gotoid(self._edit_winid)
  end

  local cwd = self:get_terminal_cwd()
  vim.fn.win_execute(self._edit_winid, 'lcd ' .. cwd, 'silent')

  vim.fn.win_execute(self._edit_winid, 'startinsert!', 'silent')

  if initial_cmd ~= nil then
    local cursor_column = 0
    if does_insert then
      cursor_column = #initial_cmd
    end

    local current_line = self:get_edit_line('.')
    if #current_line == 0 then
      vim.api.nvim_put({ initial_cmd }, 'c', true, false)
      vim.api.nvim_win_set_cursor(self._edit_winid, { vim.fn.line('.', self._edit_winid), cursor_column })
    else
      vim.fn.appendbufline(self._edit_bufnr, vim.fn.line('$', self._edit_winid), initial_cmd)
      vim.api.nvim_win_set_cursor(self._edit_winid, { vim.fn.line('$', self._edit_winid), cursor_column })
    end
  end
end

---@private
---@param is_select boolean
function Scallop:execute_command(is_select)
  if self._edit_bufnr == -1 or self._edit_winid == -1 then
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
  vim.fn.win_execute(self._terminal_winid, 'normal! G', 'silent')

  local last_line = self:get_edit_line('$')
  if last_line ~= cmd then
    local append_line = vim.fn.line('$', self._edit_winid)
    if vim.fn.match(last_line, '^\\s*$') ~= -1 then
      append_line = math.max(append_line - 1, 0)
    end
    vim.fn.appendbufline(self._edit_bufnr, append_line, cmd)
  end

  last_line = self:get_edit_line('$')
  if vim.fn.match(last_line, '^\\s*$') == -1 then
    vim.fn.appendbufline(self._edit_bufnr, vim.fn.line('$', self._edit_winid), '')
  end

  vim.api.nvim_win_set_cursor(self._edit_winid, { vim.fn.line('$', self._edit_winid), 0 })

  local cwd = self:get_terminal_cwd()
  vim.fn.win_execute(self._edit_winid, 'lcd ' .. cwd, 'silent')
end

---@private
---@param ctrl string
function Scallop:send_ctrl(ctrl)
  if self._edit_bufnr == -1 or self._edit_winid == -1 then
    return
  end
  self:jobsend(vim.api.nvim_replace_termcodes(ctrl, true, true, true), { cleanup = false, newline = false })

  -- Scroll terminal to bottom
  vim.fn.win_execute(self._terminal_winid, 'normal! G', 'silent')
end

---@private
function Scallop:close_edit()
  if self._edit_winid ~= -1 then
    vim.fn.win_execute(self._edit_winid, 'stopinsert', 'silent')
    vim.api.nvim_win_close(self._edit_winid, true)
    self:closed_edit_window()
  end
end

---@private
function Scallop:closed_edit_window()
  self._edit_winid = -1

  if self._terminal_winid ~= -1 then
    vim.fn.win_gotoid(self._terminal_winid)
  end
end

local M = {}

---@package
---@param cwd? string
function M.start_terminal(cwd)
  local scallop = Scallop.tabpage_scallops[vim.api.nvim_get_current_tabpage()]
  if scallop == nil then
    scallop = Scallop.new()
  end
  scallop:start_terminal(cwd)
end

---@private
---@param cmd? string
---@param cwd? string
function M.start_terminal_edit(cmd, cwd)
  local scallop = Scallop.tabpage_scallops[vim.api.nvim_get_current_tabpage()]
  if scallop == nil then
    scallop = Scallop.new()
  end
  scallop:start_terminal(cwd)
  scallop:start_edit(cmd)
end

vim.api.nvim_create_autocmd('TabClosed', {
  group = vim.api.nvim_create_augroup('scallop-settings', { clear = true }),
  callback = function()
    local tabpage_livings = {}
    for tabpage, _ in pairs(Scallop.tabpage_scallops) do
      tabpage_livings[tabpage] = false
    end

    for _, tabpage in pairs(vim.api.nvim_list_tabpages()) do
      if tabpage_livings[tabpage] ~= nil then
        tabpage_livings[tabpage] = Scallop.tabpage_scallops[tabpage]._living
      end
    end

    for tabpage, living in pairs(tabpage_livings) do
      if not living then
        local scallop = Scallop.tabpage_scallops[tabpage]
        scallop:terminate()
      end
    end
  end,
})

return M
