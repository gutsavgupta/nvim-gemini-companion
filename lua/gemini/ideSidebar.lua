-- This file was created on September 26, 2025
-- This module is responsible for managing the sidebar which hosts the Gemini CLI.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local ideSidebar = {}
local snacksAvailable, skterminal = pcall(require, 'snacks.terminal')

if not snacksAvailable then
  vim.notify(
    'nvim-gemini-companion: snacks.nvim not found.'
      .. ' Please add `folke/snacks.nvim` as a dependency'
      .. ' in your lazy.nvim configuration.',
    vim.log.levels.ERROR
  )
  return
end

local defaults = {
  port = nil,
  cmd = 'gemini',
  env = {},
  win = {},
}

local presets = {
  ['right-fixed'] = {
    position = 'right',
    fixed = true,
    border = 'rounded',
    height = 1.0,
    width = 0.35,
    max_height = nil,
    max_width = 120,
  },
  ['left-fixed'] = {
    position = 'left',
    fixed = true,
    border = 'rounded',
    height = 1.0,
    width = 0.35,
    max_height = nil,
    max_width = 120,
  },
  ['bottom-fixed'] = {
    position = 'bottom',
    fixed = true,
    border = 'rounded',
    width = 1.0,
    height = 0.35,
    max_height = 100,
    max_width = nil,
  },
  ['floating'] = {
    position = 'float',
    border = 'rounded',
    height = 0.9,
    width = 0.9,
    max_height = nil,
    max_width = nil,
  },
}

--- Toggles the Gemini sidebar terminal.
-- It will open the terminal if it's closed, or close it if it's open.
-- @param opts table Configuration options for the sidebar.
function ideSidebar.toggle(opts) skterminal.toggle(opts.cmd, opts) end

--- Closes the Gemini sidebar terminal.
-- @param opts table Configuration options for the sidebar.
function ideSidebar.close(opts)
  local terminal = skterminal.get(opts.cmd, opts)
  if not terminal then return end
  if terminal.augroup then
    vim.api.nvim_clear_autocmds({
      group = terminal.augroup,
      event = 'TermClose',
    })
  end
  terminal:on('TermClose', function() terminal:close({ buf = true }) end)
  local channel = vim.api.nvim_buf_get_var(terminal.buf, 'terminal_job_id')
  if channel then vim.fn.jobstop(channel) end
end

--- Sends text to the Gemini sidebar terminal.
-- The text is bracketed to ensure it's treated as a single block.
-- @param opts table Configuration options for the sidebar.
-- @param text string The text to send to the terminal.
function ideSidebar.sendText(opts, text)
  local terminal = skterminal.get(opts.cmd, opts)
  if not terminal or not terminal:buf_valid() then
    log.debug('Terminal not found or not valid')
    return
  end
  terminal:show()
  terminal:focus()
  local channel = vim.api.nvim_buf_get_var(terminal.buf, 'terminal_job_id')
  if not channel then
    log.debug('Terminal channel not found')
    return
  end
  local bracketStart = '\27[200~'
  local bracketEnd = '\27[201~\r'
  local bracketedText = bracketStart .. text .. bracketEnd
  vim.api.nvim_chan_send(channel, bracketedText)
end

--- Sends LSP diagnostics for a buffer to the Gemini sidebar.
-- @param opts table Configuration options for the sidebar.
-- @param bufnr number The buffer number to get diagnostics from.
-- @param linenumber number (optional) The line number to filter diagnostics by.
function ideSidebar.sendDiagnostic(opts, bufnr, linenumber)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local diagnostics = vim.diagnostic.get(bufnr)

  if not diagnostics or #diagnostics == 0 then
    log.info('No diagnostics found for buffer ' .. bufnr)
    return
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filteredDiagnostics = {}

  for _, diag in ipairs(diagnostics) do
    if linenumber == nil or (diag.lnum + 1) == linenumber then -- LSP is 0-indexed, user is 1-indexed
      table.insert(filteredDiagnostics, {
        linenumber = diag.lnum + 1,
        severity = vim.diagnostic.severity[diag.severity],
        message = diag.message,
        source = diag.source,
      })
    end
  end

  if #filteredDiagnostics == 0 then
    if linenumber then
      log.info(
        'No diagnostics found for line ' .. linenumber .. ' in buffer ' .. bufnr
      )
    else
      log.info('No diagnostics found for buffer ' .. bufnr)
    end
    return
  end

  local diagnosticData = {
    filename = filename,
    diagnostics = filteredDiagnostics,
  }

  local diagnosticString = vim.fn.json_encode(diagnosticData)
  ideSidebar.sendText(opts, diagnosticString)
end

--- Sets the style of the sidebar window.
-- @param opts table Configuration options for the sidebar.
-- @param presetName string The name of the preset style to apply.
function ideSidebar.setStyle(opts, presetName)
  local preset = presets[presetName]
  if not preset then
    log.warn('Invalid sidebar style preset: ' .. presetName)
    return
  end

  -- If the terminal is open, close and reopen it to apply the new style
  local terminal = skterminal.get(opts.cmd, opts)
  if terminal and terminal:buf_valid() then
    terminal:hide()
    terminal.opts = vim.tbl_deep_extend('force', terminal.opts, preset)
    vim.defer_fn(function() ideSidebar.toggle(opts) end, 100) -- Defer to allow the terminal to close properly
  end
end

--- Extends the default configuration with user-provided options.
-- @param opts table A table of options to override the defaults.
-- @return table The merged configuration table.
local function extendDefaults(opts)
  local configOpts = vim.tbl_deep_extend('force', defaults, opts or {})

  -- Determine window style from preset and user overrides
  local presetName = (configOpts.win and configOpts.win.preset) or 'right-fixed'
  local presetOpts = presets[presetName]
  if not presetOpts then
    log.warn(
      'Invalid sidebar style preset: '
        .. presetName
        .. ". Falling back to 'right-fixed'."
    )
    presetOpts = presets['right-fixed']
  end
  -- The user's win options override the preset
  configOpts.win =
    vim.tbl_deep_extend('force', presetOpts, configOpts.win or {})
  return configOpts
end

--- Sets up the Gemini sidebar, creating user commands.
-- @param opts table Configuration options for the sidebar.
function ideSidebar.setup(opts)
  local lastSidebarStyleIdx = 1
  local configOpts = extendDefaults(opts)
  configOpts.env.TERM_PROGRAM = 'vscode'
  configOpts.env.GEMINI_CLI_IDE_WORKSPACE_PATH = vim.fn.getcwd()
  configOpts.env.GEMINI_CLI_IDE_SERVER_PORT = configOpts.port

  vim.api.nvim_create_user_command(
    'GeminiToggle',
    function() ideSidebar.toggle(configOpts) end,
    {
      desc = 'Toggle Gemini sidebar',
    }
  )
  vim.api.nvim_create_user_command(
    'GeminiClose',
    function() ideSidebar.close(configOpts) end,
    {
      desc = 'Close Gemini sidebar',
    }
  )
  vim.api.nvim_create_user_command(
    'GeminiSend',
    function(opts) ideSidebar.sendText(configOpts, opts.args) end,
    {
      nargs = '*',
      desc = 'Send text to Gemini sidebar',
    }
  )
  vim.api.nvim_create_user_command('GeminiSendFileDiagnostic', function()
    local bufnr = vim.api.nvim_get_current_buf()
    ideSidebar.sendDiagnostic(configOpts, bufnr, nil)
  end, {
    desc = 'Send file diagnostics to Gemini sidebar',
  })
  vim.api.nvim_create_user_command('GeminiSendLineDiagnostic', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    ideSidebar.sendDiagnostic(configOpts, bufnr, linenr)
  end, {
    desc = 'Send line diagnostics to Gemini sidebar',
  })
  vim.api.nvim_create_user_command(
    'GeminiSwitchSidebarStyle',
    function(cmd_opts)
      local presetName = cmd_opts.fargs[1]
      local presetKeys = vim.tbl_keys(presets)
      if not presetName then
        presetName = presetKeys[lastSidebarStyleIdx]
        lastSidebarStyleIdx = (lastSidebarStyleIdx % #presetKeys) + 1
      else
        if not presets[presetName] then
          log.warn('Invalid sidebar style preset: ' .. presetName)
          return
        end
        for i, key in ipairs(presetKeys) do
          if key == presetName then
            lastSidebarStyleIdx = i
            break
          end
        end
      end
      ideSidebar.setStyle(configOpts, presetName)
    end,
    {
      nargs = '?',
      desc = 'Switch the style of the Gemini sidebar. Presets:'
        .. vim.inspect(presets),
      complete = function() return vim.tbl_keys(presets) end,
    }
  )
end

return ideSidebar
