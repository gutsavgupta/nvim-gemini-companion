-- This file was created on September 25, 2025
-- This module is responsible for managing the sidebar which hosts the Gemini CLI.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'info',
})

local ideSidebar = {}

local state = {
  winId = nil,
  bufId = nil,
  termJobId = nil,
  width = 80,
  command = 'gemini',
  port = nil,
}

local function setHighlights()
  vim.api.nvim_set_hl(
    0,
    'GeminiSidebarNormal',
    { ctermbg = 235, bg = '#181717' }
  )
end

function ideSidebar.open()
  log.debug('Opening sidebar')
  if state.winId and vim.api.nvim_win_is_valid(state.winId) then
    vim.api.nvim_set_current_win(state.winId)
    vim.cmd('startinsert')
    return
  end

  -- Create a full-height vertical split on the rightmost side of the editor.
  vim.cmd('botright vsplit')

  if state.bufId and vim.api.nvim_buf_is_loaded(state.bufId) then
    vim.api.nvim_set_current_buf(state.bufId)
  else
    vim.cmd('enew')
    state.bufId = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_option(state.bufId, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(state.bufId, 'bufhidden', 'hide')
    vim.api.nvim_buf_set_option(state.bufId, 'buflisted', false)

    local command = state.command
    local cwd = vim.fn.getcwd()
    local termOpts = {
      env = {
        TERM_PROGRAM = 'vscode',
        GEMINI_CLI_IDE_WORKSPACE_PATH = cwd,
        GEMINI_CLI_IDE_SERVER_PORT = state.port,
      },
      on_exit = function(jobId, code, event)
        log.info('Terminal job exited:', jobId, code, event)
        ideSidebar.close()
      end,
    }

    log.debug(
      'Starting terminal with command:',
      command,
      'and options:',
      termOpts
    )
    state.termJobId = vim.fn.termopen(command, termOpts)
    vim.cmd('startinsert')
  end

  state.winId = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(state.winId, state.width)
  vim.wo[state.winId].winfixwidth = true
  vim.wo[state.winId].winfixbuf = true
  vim.wo[state.winId].number = false
  vim.wo[state.winId].relativenumber = false
  vim.wo[state.winId].signcolumn = 'no'
  vim.wo[state.winId].winhighlight = 'Normal:GeminiSidebarNormal'
  log.debug('Sidebar opened with winId:', state.winId)
end

function ideSidebar.close()
  log.debug('Closing sidebar')
  if state.winId and vim.api.nvim_win_is_valid(state.winId) then
    vim.api.nvim_win_close(state.winId, true)
  end
  if state.bufId and vim.api.nvim_buf_is_loaded(state.bufId) then
    -- Close the terminal job
    if state.termJobId then
      log.debug('Stopping terminal job:', state.termJobId)
      vim.fn.jobstop(state.termJobId)
    end
    -- Using :bd! to delete the buffer
    vim.cmd('bd! ' .. state.bufId)
  end
  state.winId = nil
  state.bufId = nil
  state.termJobId = nil
  log.debug('Sidebar closed')
end

function ideSidebar.hide()
  log.debug('Hiding sidebar')
  if state.winId and vim.api.nvim_win_is_valid(state.winId) then
    vim.api.nvim_win_hide(state.winId)
    state.winId = nil
  end
end

function ideSidebar.toggle()
  if state.winId and vim.api.nvim_win_is_valid(state.winId) then
    log.debug('Toggling sidebar: hiding')
    ideSidebar.hide()
  else
    log.debug('Toggling sidebar: opening')
    ideSidebar.open()
  end
end

function ideSidebar.setup(opts)
  log.debug('Setting up sidebar with options:', opts)
  setHighlights()
  opts = opts or {}
  state.width = opts.width or state.width
  state.command = opts.command or state.command
  state.port = opts.port or state.port

  vim.api.nvim_create_user_command(
    'GeminiToggle',
    function() ideSidebar.toggle() end,
    {
      desc = 'Toggle Gemini sidebar',
    }
  )
  vim.api.nvim_create_user_command(
    'GeminiClose',
    function() ideSidebar.close() end,
    {
      desc = 'Close Gemini sidebar',
    }
  )
end

return ideSidebar

