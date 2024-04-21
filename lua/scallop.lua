local configs = require('scallop.configs')
local shell_histories = require('telescope.shell_histories')

---@class Scallop
---@field private _active_terminal_index integer
---@field private _prev_terminal_index integer
---@field private _terminals { job_id: integer, bufnr: integer, edit_bufnr: integer }[]
---@field private _terminal_winid integer
---@field private _edit_winid integer
---@field private _edit_winwidth integer
---@field private _edit_winheight integer
---@field private _edit_numberwidth integer
---@field private _prev_winid integer
---@field private _options table
---@field package _living boolean
---@field private _tabpage_handle unknown
local Scallop = {}
Scallop.__index = Scallop
---@type table<unknown, Scallop>
Scallop.tabpage_scallops = {}

---Return edit buffer name
---@param job_id integer
---@return string
local function get_edit_buf_name(job_id)
  return 'scallop-edit@' .. vim.fn.jobpid(job_id)
end

function Scallop.new()
  local self = setmetatable({
    _active_terminal_index = 1,
    _prev_terminal_index = 1,
    _terminals = {
      {
        job_id = -1,
        bufnr = -1,
        edit_bufnr = -1,
      },
      {
        job_id = -1,
        bufnr = -1,
        edit_bufnr = -1,
      },
    },
    _terminal_winid = -1,
    _edit_winid = -1,
    _edit_winwidth = -1,
    _edit_winheight = -1,
    _edit_numberwidth = 0,
    _prev_winid = -1,
    _options = vim.deepcopy(configs.configs.options),
    _living = true,
    _tabpage_handle = vim.api.nvim_get_current_tabpage(),
  }, Scallop)

  Scallop.tabpage_scallops[self._tabpage_handle] = self

  return self
end

function Scallop:terminate()
  for _, terminal in pairs(self._terminals) do
    if terminal.job_id ~= -1 then
      vim.fn.jobstop(terminal.job_id)
      terminal.job_id = -1
    end

    if terminal.bufnr ~= -1 then
      vim.api.nvim_buf_delete(terminal.bufnr, { force = true })
      terminal.bufnr = -1
    end

    if terminal.edit_bufnr ~= -1 then
      vim.api.nvim_buf_delete(terminal.edit_bufnr, { force = true })
    end
  end

  self._active_terminal_index = 1
  self._prev_terminal_index = 1

  self._living = false
  Scallop.tabpage_scallops[self._tabpage_handle] = nil
end

---@private
function Scallop:switch_terminal()
  local current_active_index = self._active_terminal_index
  if self._prev_terminal_index == current_active_index then
    local next_index = (self._active_terminal_index + 1) % #self._terminals
    if next_index == 0 then
      next_index = #self._terminals
    end

    if next_index == current_active_index then
      return
    end

    self._active_terminal_index = next_index
    self._prev_terminal_index = current_active_index

    local terminal = self:active_terminal()
    terminal.bufnr = vim.fn.bufadd('')
    vim.api.nvim_win_set_buf(self._terminal_winid, terminal.bufnr)
    vim.api.nvim_win_call(self._terminal_winid, function()
      self:init_terminal_buffer()
    end)
  else
    self._active_terminal_index = self._prev_terminal_index
    self._prev_terminal_index = current_active_index
    local terminal = self:active_terminal()
    vim.api.nvim_win_set_buf(self._terminal_winid, terminal.bufnr)
  end

  if self._edit_winid ~= -1 then
    local terminal = self:active_terminal()
    if terminal.edit_bufnr == -1 then
      terminal.edit_bufnr = vim.fn.bufadd(get_edit_buf_name(terminal.job_id))
      vim.api.nvim_win_set_buf(self._edit_winid, terminal.edit_bufnr)
      self:set_edit_win_options()
      self:init_edit_buffer()
    else
      vim.api.nvim_win_set_buf(self._edit_winid, terminal.edit_bufnr)
      self:restore_edit_cursor(terminal.edit_bufnr)
    end
  end
end

---@private
function Scallop:active_terminal()
  return self._terminals[self._active_terminal_index]
end

---@private
function Scallop:set_active_terminal()
  if self._prev_terminal_index ~= self._active_terminal_index then
    self._active_terminal_index = self._prev_terminal_index
    self:set_prev_terminal()
    if self._terminal_winid ~= -1 then
      local terminal = self:active_terminal()
      vim.api.nvim_win_set_buf(self._terminal_winid, terminal.bufnr)
      if self._edit_winid ~= -1 then
        vim.api.nvim_win_set_buf(self._edit_winid, terminal.edit_bufnr)
        self:restore_edit_cursor(terminal.edit_bufnr)
      end
    end
  else
    self._active_terminal_index = 1
    self._prev_terminal_index = 1
  end
end

---@private
function Scallop:set_prev_terminal()
  local num_terminals = #self._terminals
  for i = 1, num_terminals do
    local index = (self._active_terminal_index - i + num_terminals) % num_terminals
    if index == 0 then
      index = num_terminals
    end
    if self._terminals[index].bufnr ~= -1 then
      self._prev_terminal_index = index
      return
    end
  end
  self._prev_terminal_index = self._active_terminal_index
end

---@private
---@param cmd string
---@param options { cleanup: boolean, newline: boolean }
function Scallop:jobsend(cmd, options)
  local terminal = self:active_terminal()
  if terminal.job_id == -1 then
    return
  end

  if options.cleanup then
    cmd = vim.api.nvim_replace_termcodes(self._options.cleanup_key_sequence, true, true, true) .. cmd
  end
  if options.newline then
    cmd = cmd .. vim.api.nvim_replace_termcodes("<CR>", true, true, true)
  end

  local cmd_len = #cmd
  local total_send_len = 0
  local failed = 0
  while total_send_len < cmd_len do
    local send_len = vim.fn.chansend(terminal.job_id, cmd:sub(total_send_len + 1, cmd_len))
    if send_len == 0 then
      failed = failed + 1
      if failed > 10 then
        break
      end
    else
      failed = 0
      total_send_len = total_send_len + send_len
    end
  end
end

---@private
---@private
function Scallop:open_terminal_window()
  local terminal = self:active_terminal()
  if terminal.bufnr == -1 then
    terminal.bufnr = vim.fn.bufadd('')
  end

  self._terminal_winid = vim.api.nvim_open_win(terminal.bufnr, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = vim.o.columns - 6,
    height = vim.o.lines - 6,
    border = self._options.floating_border,
    zindex = 11,
  })

  vim.wo[self._terminal_winid].list = false
  vim.wo[self._terminal_winid].wrap = false

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
  local terminal = self:active_terminal()
  terminal.job_id = vim.api.nvim_buf_call(terminal.bufnr, function()
    if cwd ~= nil and vim.fn.isdirectory(cwd) then
      return vim.fn.termopen(vim.o.shell, { cwd = cwd })
    else
      return vim.fn.termopen(vim.o.shell)
    end
  end)

  local this_terminal_index = self._active_terminal_index

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = terminal.bufnr,
    callback = function()
      if not self._living then
        return
      end

      local close_all_terminals = (self._prev_terminal_index == self._active_terminal_index)

      if close_all_terminals or self._terminal_winid == vim.api.nvim_get_current_win() then
        vim.fn.win_execute(self._terminal_winid, 'stopinsert', 'silent')
      end

      local bufnr = terminal.bufnr
      local edit_bufnr = terminal.edit_bufnr
      terminal.job_id = -1
      terminal.bufnr = -1
      terminal.edit_bufnr = -1

      if this_terminal_index == self._active_terminal_index then
        self:set_active_terminal()
      elseif this_terminal_index == self._prev_terminal_index then
        self:set_prev_terminal()
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
      if edit_bufnr ~= -1 then
        vim.api.nvim_buf_delete(edit_bufnr, { force = true })
      end

      if close_all_terminals then
        self:terminate()
      end
    end,
  })

  local keymap_opt = { buffer = terminal.bufnr }

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

  vim.keymap.set({ 'n', 'x' }, '<C-n>', function()
    if self._living then
      self:jump_to_prompt('forward')
    end
  end, keymap_opt)

  vim.keymap.set({ 'n', 'x' }, '<C-p>', function()
    if self._living then
      self:jump_to_prompt('backward')
    end
  end, keymap_opt)

  vim.keymap.set('n', '<C-^>', function()
    if self._living then
      self:switch_terminal()
    end
  end, keymap_opt)
end

---@package
---@param cwd? string
function Scallop:start_terminal(cwd)
  self._prev_winid = vim.fn.win_getid()
  local terminal = self:active_terminal()
  if terminal.bufnr == -1 then
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
  local terminal = self:active_terminal()
  if vim.fn.executable('lsof') then
    local cmd = { 'lsof', '-a', '-d', 'cwd', '-p', tostring(vim.fn.jobpid(terminal.job_id)) }
    local stdout = vim.fn.system(table.concat(cmd, ' '))
    local cwd = vim.fn.matchstr(stdout, [[cwd\s\+\S\+\s\+\S\+\s\+\S\+\s\+\S\+\s\+\zs.\+\ze\n]])
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

  local terminal = self:active_terminal()
  local search_pos = vim.api.nvim_buf_call(terminal.bufnr, function()
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
function Scallop:set_edit_win_options()
  for option, value in pairs(self._options.edit_win_options) do
    pcall(vim.api.nvim_set_option_value, option, value, { win = self._edit_winid, scope = 'local' })
  end

  self:set_edit_winwidth()
  self:set_edit_numberwidth()
end

---@private
function Scallop:open_edit_window()
  local terminal = self:active_terminal()
  if terminal.edit_bufnr == -1 then
    terminal.edit_bufnr = vim.fn.bufadd(get_edit_buf_name(terminal.job_id))
  end

  self._edit_winheight = 1
  self._edit_winid = vim.api.nvim_open_win(terminal.edit_bufnr, true, {
    relative = 'editor',
    row = 1 + vim.o.columns - 6,
    col = 1,
    width = vim.fn.winwidth(self._terminal_winid),
    height = 1,
    border = self._options.floating_border,
    zindex = 12,
  })

  self:set_edit_win_options()

  vim.api.nvim_create_autocmd({ 'WinResized' }, {
    pattern = tostring(self._edit_winid),
    callback = function()
      if self._living then
        self:set_edit_winwidth()
      end
    end,
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
  local terminal = self:active_terminal()
  vim.bo[terminal.edit_bufnr].bufhidden = 'hide'
  vim.bo[terminal.edit_bufnr].buftype = 'nowrite'
  vim.bo[terminal.edit_bufnr].buflisted = false
  vim.bo[terminal.edit_bufnr].swapfile = false
  vim.bo[terminal.edit_bufnr].filetype = self._options.edit_filetype

  local keymap_opt = { buffer = terminal.edit_bufnr }

  vim.keymap.set({ 'n', 'i' }, '<CR>', function()
    if self._living then
      self:execute_command(false)
    end
  end, keymap_opt)
  vim.keymap.set('n', 'q', function()
    if self._living then
      self:close_edit()
    end
  end, keymap_opt)
  vim.keymap.set({ 'n', 'i' }, '<C-q>', function()
    if self._living then
      self:close_terminal()
    end
  end, keymap_opt)
  vim.keymap.set({ 'n' }, '<C-^>', function()
    if self._living then
      self:switch_terminal()
    end
  end, keymap_opt)

  vim.keymap.set({ 'n', 'i' }, '<C-g>', function()
    if self._living then
      local ok, char = pcall(vim.fn.getcharstr)
      if not ok then
        if char == 'Keyboard interrupt' then
          char = vim.api.nvim_replace_termcodes("<C-c>", true, true, true)
        else
          print(":" .. char .. ":")
          return
        end
      end
      if char == vim.api.nvim_replace_termcodes("<C-g>", true, true, true) then
        self:scroll_to_bottom()
      elseif char == vim.api.nvim_replace_termcodes("<C-n>", true, true, true) then
        self:jump_to_prompt('forward')
      elseif char == vim.api.nvim_replace_termcodes("<C-p>", true, true, true) then
        self:jump_to_prompt('backward')
      elseif char == vim.api.nvim_replace_termcodes("<C-^>", true, true, true) then
        self:switch_terminal()
      else
        self:send_ctrl(char)
      end
    end
  end, keymap_opt)

  vim.keymap.set({ 'n', 'i' }, '<C-k>', function()
    if self._living then
      shell_histories(
        self:get_edit_all_lines(),
        self._options.history_filepath,
        self._options.history_filter,
        { default_text = self:get_edit_line('.') },
        function(cmd)
          vim.defer_fn(function() self:start_edit(cmd, true) end, 0)
        end
      )
    end
  end, keymap_opt)

  vim.keymap.set('x', '<CR>', function()
    if self._living then
      self:execute_command(true)
      vim.fn.win_execute(self._edit_winid, "normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, true, true),
        'silent')
    end
  end, keymap_opt)

  --- Direct key mapping
  for code = 65, 90 do
    local key = ("<C-%s>"):format(string.char(code))
    vim.keymap.set('l', key, function()
      if self._living then
        self:send_ctrl(key)
      end
    end, keymap_opt)
  end

  for code = 32, 127 do
    local key = string.char(code)
    vim.keymap.set('l', key, function()
      if self._living then
        self:send_ctrl(key)
      end
    end, keymap_opt)
  end

  vim.api.nvim_create_autocmd({ 'OptionSet' }, {
    pattern = { 'number', 'relativenumber', 'numberwidth' },
    callback = function()
      if self._living and self._edit_winid ~= -1 then
        self:set_edit_numberwidth()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'TextChangedP' }, {
    buffer = terminal.edit_bufnr,
    callback = function()
      if self._living and self._edit_winid ~= -1 then
        self:resize_edit_winheight()
      end
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeave', {
    buffer = terminal.edit_bufnr,
    callback = function()
      if vim.go.iminsert == 1 then
        vim.go.iminsert = 0
      end
      if terminal.edit_bufnr ~= -1 then
        vim.bo[terminal.edit_bufnr].iminsert = 0
      end
    end,
  })
end

---@private
function Scallop:set_edit_numberwidth()
  if vim.wo[self._edit_winid].number or vim.wo[self._edit_winid].relativenumber then
    self._edit_numberwidth = vim.wo[self._edit_winid].numberwidth
  else
    self._edit_numberwidth = 0
  end
end

---@private
function Scallop:set_edit_winwidth()
  self._edit_winwidth = vim.api.nvim_win_get_width(self._edit_winid)
end

---@private
function Scallop:resize_edit_winheight()
  if vim.wo[self._edit_winid].wrap then
    local virtcol = vim.fn.virtcol("$")
    local winwidth = self._edit_winwidth - self._edit_numberwidth
    local winheight = math.ceil(virtcol / winwidth)
    if self._edit_winheight ~= winheight then
      self._edit_winheight = winheight
      vim.api.nvim_win_set_height(self._edit_winid, winheight)
    end
  end
end

---@private
---@param edit_bufnr integer
function Scallop:restore_edit_cursor(edit_bufnr)
  local last_pos = vim.api.nvim_buf_get_mark(edit_bufnr, '"')
  vim.api.nvim_win_set_cursor(self._edit_winid, last_pos)
  self:resize_edit_winheight()
end

---@private
---@param pos string
---@return string
function Scallop:get_edit_line(pos)
  local terminal = self:active_terminal()
  return vim.fn.getbufoneline(terminal.edit_bufnr, vim.fn.line(pos, self._edit_winid))
end

---@private
---@return string
function Scallop:get_select_lines()
  local first = vim.fn.line("v", self._edit_winid)
  local last = vim.fn.line(".", self._edit_winid)
  if first > last then
    first, last = last, first
  end
  local terminal = self:active_terminal()
  return table.concat(vim.api.nvim_buf_get_lines(terminal.edit_bufnr, first - 1, last, true), '\n')
end

---@private
---@return string[]
function Scallop:get_edit_all_lines()
  local terminal = self:active_terminal()
  return vim.api.nvim_buf_get_lines(terminal.edit_bufnr, 0, -1, true)
end

---@package
---@param initial_cmd? string
---@param does_insert? boolean
function Scallop:start_edit(initial_cmd, does_insert)
  local terminal = self:active_terminal()
  if terminal.edit_bufnr == -1 then
    self:open_edit_window()
    self:init_edit_buffer()
  elseif self._edit_winid == -1 then
    self:open_edit_window()
    self:restore_edit_cursor(terminal.edit_bufnr)
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
      vim.fn.appendbufline(terminal.edit_bufnr, vim.fn.line('$', self._edit_winid), initial_cmd)
      vim.api.nvim_win_set_cursor(self._edit_winid, { vim.fn.line('$', self._edit_winid), cursor_column })
    end
  end
end

---@private
function Scallop:scroll_to_bottom()
  if self._terminal_winid ~= -1 then
    vim.api.nvim_win_set_cursor(self._terminal_winid, { vim.fn.line('$', self._terminal_winid), 0 })
  end
end

---@private
---@param is_select boolean
function Scallop:execute_command(is_select)
  local terminal = self:active_terminal()
  if terminal.edit_bufnr == -1 or self._edit_winid == -1 then
    return
  end

  local cmd
  if is_select then
    cmd = self:get_select_lines()
  else
    cmd = self:get_edit_line('.')
  end
  self:jobsend(cmd, { cleanup = true, newline = true })

  self:scroll_to_bottom()

  local last_lnum = vim.fn.line('$', self._edit_winid)
  for lnum = last_lnum, 0, -1 do
    local line = vim.fn.getbufoneline(terminal.edit_bufnr, lnum)
    if vim.fn.match(line, [[^\s*$]]) == -1 then
      if lnum ~= last_lnum then
        vim.fn.deletebufline(terminal.edit_bufnr, lnum + 1, last_lnum)
      end

      if line ~= cmd then
        vim.fn.appendbufline(terminal.edit_bufnr, lnum, cmd)
      end
      break
    end
  end

  vim.fn.appendbufline(terminal.edit_bufnr, vim.fn.line('$', self._edit_winid), '')

  vim.api.nvim_win_set_cursor(self._edit_winid, { vim.fn.line('$', self._edit_winid), 0 })

  local cwd = self:get_terminal_cwd()
  vim.fn.win_execute(self._edit_winid, 'lcd ' .. cwd, 'silent')
end

---@private
---@param ctrl string
function Scallop:send_ctrl(ctrl)
  local terminal = self:active_terminal()
  if terminal.edit_bufnr == -1 or self._edit_winid == -1 then
    return
  end
  self:jobsend(vim.api.nvim_replace_termcodes(ctrl, true, true, true), { cleanup = false, newline = false })

  -- Scroll terminal to bottom
  self:scroll_to_bottom()
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
  group = vim.api.nvim_create_augroup('scallop-internal-auto-group', { clear = true }),
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
