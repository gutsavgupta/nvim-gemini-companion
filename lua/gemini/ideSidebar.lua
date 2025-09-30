-- This file was created on September 26, 2025
--- This module is responsible for managing the sidebar which hosts the Gemini CLI.
-- Provides functions for toggling, switching, sending text, and configuring the sidebar terminal.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local ideSidebar = {}
local ideSidebarState = {
  lastActiveIdx = 1,
  lastPresetIdx = 1,
  terminalOpts = {},
  presets = {
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
  },
}

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

--- Extends the default configuration with user-provided options.
-- This function is primarily used internally during setup to merge user options with defaults
-- and apply preset window configurations.
-- @param opts table A table of options to override the defaults.
-- @param defaults table The default configuration table to extend.
-- @return table The merged configuration table.
function ideSidebar.extendDefaults(opts, defaults)
  local configOpts = vim.tbl_deep_extend('force', defaults, opts or {})

  -- Determine window style from preset and user overrides
  local presetName = (configOpts.win and configOpts.win.preset) or 'right-fixed'
  local presetOpts = ideSidebarState.presets[presetName]
  if not presetOpts then
    log.warn(
      'Invalid sidebar style preset: '
        .. presetName
        .. ". Falling back to 'right-fixed'."
    )
    presetOpts = ideSidebarState.presets['right-fixed']
  end
  -- The user's win options override the preset
  configOpts.win =
    vim.tbl_deep_extend('force', presetOpts, configOpts.win or {})
  return configOpts
end

--- Toggles the sidebar terminal.
-- Used by the 'GeminiToggle' user command to show/hide the sidebar terminal.
function ideSidebar.toggle()
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local term, created = skterminal.get(opts.cmd, opts)
  if created then return end
  term:toggle()
end

--- Switches the sidebar terminal to the next command in the list, hiding the current one
--- and opening the next one.
-- Used internally when multiple commands are configured and user presses Tab in terminal mode.
function ideSidebar.switch()
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local term, created = skterminal.get(opts.cmd, opts)
  if created then return end
  term:hide()
  ideSidebarState.lastActiveIdx = (
    ideSidebarState.lastActiveIdx % #ideSidebarState.terminalOpts
  ) + 1
  local nextOpts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local nextTerm = skterminal.get(nextOpts.cmd, nextOpts)
  nextTerm:show()
  nextTerm:focus()
end

--- Closes the sidebar terminal, stopping the associated job and cleaning up resources.
-- Used by the 'GeminiClose' user command to completely close the sidebar terminal.
function ideSidebar.close()
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local term =
    skterminal.get(opts.cmd, vim.tbl_extend('force', opts, { create = false }))
  if not term then return end
  if term.augroup then
    vim.api.nvim_clear_autocmds({
      group = term.augroup,
      event = 'TermClose',
    })
  end
  term:on('TermClose', function() term:close({ buf = true }) end)
  local channel = vim.api.nvim_buf_get_var(term.buf, 'terminal_job_id')
  if channel then vim.fn.jobstop(channel) end
end

--- Sends text to the sidebar last active terminal.
-- The text is bracketed to ensure it's treated as a single block.
-- Used internally to send commands or data to the active Gemini/Qwen terminal.
-- @param text string The text to send to the terminal.
function ideSidebar.sendText(text)
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local term =
    skterminal.get(opts.cmd, vim.tbl_extend('force', opts, { create = false }))
  if not term or not term:buf_valid() then
    log.debug('Terminal not found or not valid')
    return
  end
  local channel = vim.api.nvim_buf_get_var(term.buf, 'terminal_job_id')
  local bracketStart = '\27[200~'
  local bracketEnd = '\27[201~\r'
  local bracketedText = bracketStart .. text .. bracketEnd
  vim.api.nvim_chan_send(channel, bracketedText)

  term:show()
  term:focus()
end

--- Sends LSP diagnostics for a buffer to the sidebar.
-- Used by 'GeminiSendFileDiagnostic' and 'GeminiSendLineDiagnostic' commands to send
-- diagnostic information to the active terminal for analysis.
-- @param bufnr number The buffer number to get diagnostics from.
-- @param linenumber number (optional) The line number to filter diagnostics by. If nil, sends all diagnostics for the buffer.
function ideSidebar.sendDiagnostic(bufnr, linenumber)
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
  ideSidebar.sendText(diagnosticString)
end

--- Sets the style of the sidebar window using a preset.
-- Changes the appearance and position of the sidebar using predefined configurations.
-- @param presetName string The name of the preset style to apply.
function ideSidebar.setStyle(presetName)
  local preset = ideSidebarState.presets[presetName]
  if not preset then
    log.warn('Invalid sidebar style preset: ' .. presetName)
    return
  end

  for _, opts in ipairs(ideSidebarState.terminalOpts) do
    opts.win = vim.tbl_deep_extend('force', opts.win, preset)
    local term, created = skterminal.get(opts.cmd, opts)
    if not created and term and term:buf_valid() then
      term:hide()
      term.opts = vim.tbl_deep_extend('force', term.opts, preset)
    end
  end

  vim.defer_fn(ideSidebar.toggle, 100)
end

--- Switches the sidebar style to the next preset or to the specified preset.
-- If no preset name is provided, cycles to the next preset in the list.
-- Used by the 'GeminiSwitchSidebarStyle' user command to change the sidebar appearance.
-- @param cmdOpts table Command options containing fargs for preset name.
function ideSidebar.switchStylePreset(cmdOpts)
  local presetName = cmdOpts.fargs[1]
  local presetKeys = vim.tbl_keys(ideSidebarState.presets)
  if not presetName then
    presetName = presetKeys[ideSidebarState.lastPresetIdx]
    ideSidebarState.lastPresetIdx = (
      ideSidebarState.lastPresetIdx % #presetKeys
    ) + 1
  else
    if not ideSidebarState.presets[presetName] then
      log.warn('Invalid sidebar style preset: ' .. presetName)
      return
    end
    for i, key in ipairs(presetKeys) do
      if key == presetName then
        ideSidebarState.lastPresetIdx = i
        break
      end
    end
  end
  ideSidebar.setStyle(presetName)
end

--- Handles the GeminiSend command, processing visual selections and sending text to the active terminal.
-- When called with visual selection, sends the selected text along with any additional arguments.
-- When called without selection, sends only the provided arguments.
-- @param cmdOpts table The command options, including args and range information.
function ideSidebar.handleGeminiSend(cmdOpts)
  local text = cmdOpts.args or ''
  local selectedText = ''

  -- Check if we have a visual selection range ('<,'> notation)
  local startLine, endLine = vim.fn.line("'<"), vim.fn.line("'>")
  local startCol, endCol = vim.fn.col("'<"), vim.fn.col("'>")

  if startLine > 0 and endLine >= startLine then
    -- We have a visual selection
    local lines = vim.api.nvim_buf_get_lines(0, startLine - 1, endLine, false)

    if #lines == 1 then
      -- Single line selection - handle column-wise selection
      local startIdx = startCol - 1
      local endIdx = endCol
      if endIdx > #lines[1] then endIdx = #lines[1] end
      if startIdx < #lines[1] then
        lines[1] = string.sub(lines[1], startIdx + 1, endIdx)
      end
    else
      -- Multi-line selection - trim first and last line according to column selection
      local firstLine = lines[1]
      if startCol <= #firstLine then
        lines[1] = string.sub(firstLine, startCol, #firstLine)
      end

      local lastLine = lines[#lines]
      if endCol <= #lastLine then
        lines[#lines] = string.sub(lastLine, 1, endCol)
      end
    end

    selectedText = table.concat(lines, '\n')
    text = selectedText .. ' ' .. text
  end

  ideSidebar.sendText(text)
end

--- Sets up the Gemini sidebar, creating user commands and terminal configurations.
-- @param opts table Configuration options for the sidebar with the following fields:
--                  - cmds (table): List of commands to initialize ('gemini', 'qwen', etc.)
--                  - cmd (string): Single command to use (alternative to cmds)
--                  - port (number): Port number for the Gemini/Qwen server
--                  - env (table): Additional environment variables
--                  - win (table): Window configuration options including preset
function ideSidebar.setup(opts)
  -------------------------------------------------------
  --- Setup Defaults
  -------------------------------------------------------
  local defaults = {
    cmds = { 'gemini', 'qwen' },
    port = nil,
    env = {},
    win = {
      preset = 'right-fixed',
    },
  }

  -------------------------------------------------------
  --- Creating Opts for Each Terminal
  -------------------------------------------------------
  opts = ideSidebar.extendDefaults(opts, defaults)
  if opts.cmd then opts.cmds = { opts.cmd } end
  for _, cmd in ipairs(opts.cmds) do
    local termOpts = vim.tbl_deep_extend('force', opts, { cmd = cmd })
    local orgOnBuf = termOpts.win.on_buf
    termOpts.env.TERM_PROGRAM = 'vscode'
    if string.find(termOpts.cmd, 'qwen') then
      if termOpts.cmd == 'qwen' and vim.fn.executable('qwen') == 0 then
        termOpts = nil
        goto continue
      end
      termOpts.env.QWEN_CODE_IDE_WORKSPACE_PATH = vim.fn.getcwd()
      termOpts.env.QWEN_CODE_IDE_SERVER_PORT = tostring(termOpts.port)
    else
      if termOpts.cmd == 'gemini' and vim.fn.executable('gemini') == 0 then
        termOpts = nil
        goto continue
      end
      termOpts.env.GEMINI_CLI_IDE_WORKSPACE_PATH = vim.fn.getcwd()
      termOpts.env.GEMINI_CLI_IDE_SERVER_PORT = tostring(termOpts.port)
    end
    if #opts.cmds <= 1 then goto continue end
    termOpts.win.on_buf = function(win)
      vim.api.nvim_buf_set_keymap(
        win.buf,
        't',
        '<Tab>',
        '<Cmd>lua require("gemini.ideSidebar").switch()<CR>', -- Corrected escaping for nested quotes
        { noremap = true, silent = true }
      )
      if orgOnBuf and type(orgOnBuf) == 'function' then orgOnBuf(win) end
    end
    ::continue::
    if termOpts then table.insert(ideSidebarState.terminalOpts, termOpts) end
  end
  if #ideSidebarState.terminalOpts == 0 then
    log.error('No valid terminals found for Gemini/Qwen')
    error('No valid executable found for Gemini/Qwen')
    return
  end
  log.debug(vim.inspect(ideSidebarState.terminalOpts))
  -------------------------------------------------------
  --- Creating User Commands
  -------------------------------------------------------
  vim.api.nvim_create_user_command(
    'GeminiToggle',
    function() ideSidebar.toggle() end,
    { desc = 'Toggle Gemini/Qwen sidebar' }
  )

  vim.api.nvim_create_user_command(
    'GeminiSwitchSidebarStyle',
    ideSidebar.switchStylePreset,
    {
      nargs = '?',
      desc = 'Switch the style of the Gemini/Qwen sidebar. Presets:'
        .. vim.inspect(ideSidebarState.presets),
      complete = function() return vim.tbl_keys(ideSidebarState.presets) end,
    }
  )

  vim.api.nvim_create_user_command(
    'GeminiSend',
    function(cmdOpts) ideSidebar.handleGeminiSend(cmdOpts) end,
    {
      nargs = '*',
      range = true, -- Enable range support for visual selections
      desc = 'Send selected text (with provided text) to active sidebar',
    }
  )

  vim.api.nvim_create_user_command('GeminiSendFileDiagnostic', function()
    local bufnr = vim.api.nvim_get_current_buf()
    ideSidebar.sendDiagnostic(bufnr, nil)
  end, {
    desc = 'Send file diagnostics to active sidebar',
  })

  vim.api.nvim_create_user_command('GeminiSendLineDiagnostic', function()
    local bufnr = vim.api.nvim_get_current_buf()
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    ideSidebar.sendDiagnostic(bufnr, linenr)
  end, {
    desc = 'Send line diagnostics to active sidebar',
  })

  vim.api.nvim_create_user_command(
    'GeminiClose',
    function() ideSidebar.close() end,
    {
      desc = 'Close Gemini sidebar',
    }
  )
end

return ideSidebar
