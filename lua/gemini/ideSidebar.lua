--- IDE Sidebar module for managing Gemini CLI in a sidebar terminal
-- @module ideSidebar
-- Provides functions for toggling, switching, sending text, and
-- configuring the sidebar terminal.
local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

----------------------------------------------------------------
--- IDE Sidebar class definition
----------------------------------------------------------------
local ideSidebar = {}
local terminal = require('gemini.terminal')
local presetKeys = terminal.getPresetKeys()
local ideSidebarState = {
  lastActiveIdx = 1,
  lastPresetIdx = 1,
  rightPresetIdx = nil,
  terminalOpts = {},
}

local cwdBase =
  string.gsub(vim.fn.fnamemodify(vim.fn.getcwd(), ':t'), '[%s:]', '_')
cwdBase = #cwdBase > 20 and string.sub(cwdBase, 1, 20) or cwdBase
----------------------------------------------------------------
--- Helper Functions
----------------------------------------------------------------
-- Get index of preset name in presetKeys table
-- Returns index of preset name or 'right' preset index if invalid
-- @param presetName string The name of the preset to look up
-- @return number The index of the preset in presetKeys table
local function getPresetIdx(presetName)
  for i, key in ipairs(presetKeys) do
    if key == presetName then return i end
  end
  log.warn(
    string.format(
      'Invalid sidebar style preset: %s, falling back to %s',
      presetName,
      'right-fixed'
    )
  )
  return ideSidebarState.rightPresetIdx
end

-- Recursively sort table by keys to ensure consistent ordering
-- @param t table The table to sort recursively
-- @return table A new table with sorted keys
local function sortTableRecursively(t)
  if type(t) ~= 'table' then return t end
  local sorted = {}
  local keys = {}

  -- Get all keys and sort them
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)

  -- Recursively sort values based on sorted keys
  for _, k in ipairs(keys) do
    local v = t[k]
    sorted[k] = type(v) == 'table' and sortTableRecursively(v) or v
  end
  return sorted
end

-- Check if running inside a tmux session
-- @return boolean True if running in tmux, false otherwise
local function isTmux() return os.getenv('TMUX') ~= nil end

-- Find a tmux window by name
-- @param cmd string The command to look for (e.g., 'gemini', 'qwen')
-- @return string|nil The tmux window ID (e.g., '@1') or nil if not found
local function findMatchingTmuxWindow(windowName)
  local command = 'tmux list-windows -F "#{window_name},#{window_id}"'
  local handle = io.popen(command)
  if not handle then return nil end
  local result = handle:read('*a')
  handle:close()

  for line in result:gmatch('[^\n]+') do
    local name, id = line:match('^(.*),(.*)')
    if name and name == windowName then return id end
  end

  return nil
end

----------------------------------------------------------------
--- IDE Sidebar class public methods
----------------------------------------------------------------
--- Toggle the sidebar terminal
-- Used by 'GeminiToggle' command to show/hide the sidebar terminal
-- @return nil
function ideSidebar.toggle()
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local term = terminal.getActiveTerminals()[opts.id]
  if not term then
    term = terminal.create(opts.cmd, opts)
    return
  end
  term:toggle()
end

--- Close the sidebar terminal
-- Used by 'GeminiClose' command to close the sidebar terminal
-- @return nil
function ideSidebar.close()
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local term = terminal.getActiveTerminals()[opts.id]
  if not term then
    log.warn('No terminal found with ID', opts.id)
    return
  end
  term:exit()
end

--- Switch to next sidebar terminal in command list
-- Hide current terminal and open next one in list
-- Used when multiple commands configured and Tab pressed in terminal mode
-- @return nil
function ideSidebar.switchTerms()
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  terminal.create(opts.cmd, opts):hide()
  ideSidebarState.lastActiveIdx = (
    ideSidebarState.lastActiveIdx % #ideSidebarState.terminalOpts
  ) + 1

  local nextOpts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  terminal.create(nextOpts.cmd, nextOpts):show()
end

--- Switch sidebar style to preset or specified preset
-- If no preset provided, cycle to next preset in list
-- Used by 'GeminiSwitchSidebarStyle' command to change appearance
-- @param presetName? string The name of the preset to switch to.
-- @return nil
function ideSidebar.switchStyle(presetName)
  if not presetName or type(presetName) ~= 'string' then
    presetName = presetKeys[ideSidebarState.lastPresetIdx % #presetKeys + 1]
  end
  for _, opts in ipairs(ideSidebarState.terminalOpts) do
    local term = terminal.getActiveTerminals()[opts.id]
    if term then
      term:hide()
      presetName = term:switch(presetName)
    end
    opts.win.preset = presetName
  end
  vim.defer_fn(ideSidebar.toggle, 100)
  ideSidebarState.lastPresetIdx = getPresetIdx(presetName)
end

--- Send diagnostic information to sidebar terminal
-- Filter and format diagnostics from specified buffer and line number,
-- send as JSON to active terminal for analysis
-- @param bufnr number The buffer number to get diagnostics from
-- @param linenumber number Optional line to filter diagnostics by.
-- @return nil
function ideSidebar.sendDiagnostic(bufnr, linenumber)
  local diagnostics = vim.diagnostic.get(bufnr)
  if not diagnostics or #diagnostics == -1 then
    log.info('No diagnostics found for buffer ' .. bufnr)
    return
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  local filteredDiagnostics = {}
  for _, diag in ipairs(diagnostics) do
    -- LSP is 0-indexed, user is 1-indexed
    if linenumber == nil or (diag.lnum + 1) == linenumber then
      table.insert(filteredDiagnostics, {
        linenumber = diag.lnum + 1,
        severity = vim.diagnostic.severity[diag.severity],
        message = diag.message,
        source = diag.source,
      })
    end
  end

  if #filteredDiagnostics == 0 then return end
  local diagnosticData = {
    filename = filename,
    diagnostics = filteredDiagnostics,
  }

  local diagnosticString = vim.fn.json_encode(diagnosticData)
  ideSidebar.sendText(diagnosticString)
end

--- Send selected text from current buffer to sidebar terminal
-- Extract text based on visual selection range, send code to Gemini/Qwen
-- Include any additional arguments provided with the command
-- @param cmdOpts table Command options containing args for additional text
-- @return nil
function ideSidebar.sendSelectedText(cmdOpts)
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
      -- Multi-line selection - trim first and last line
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

function ideSidebar.sendTextToTerm(term, text)
  if not term.buf or not vim.api.nvim_buf_is_valid(term.buf) then
    term:exit()
    log.debug('No valid buffer found for terminal')
    return
  end

  local channel = vim.api.nvim_buf_get_var(term.buf, 'terminal_job_id')
  if not channel or channel == 0 then
    term:exit()
    log.debug('No terminal job found for buffer', term.buf)
    return
  end

  local bracketStart = '\27[200~'
  local bracketEnd = '\27[201~\r'
  local bracketedText = bracketStart .. text .. bracketEnd
  vim.api.nvim_chan_send(channel, bracketedText)

  -- Hide the currently active terminal
  local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
  local currentTerm = terminal.getActiveTerminals()[opts.id]
  if
    currentTerm
    and currentTerm ~= term
    and currentTerm.win
    and vim.api.nvim_win_is_valid(currentTerm.win)
  then
    currentTerm:hide()
  end

  -- Find the terminal id for the term we're sending to
  for i, opt in ipairs(ideSidebarState.terminalOpts) do
    if opt.id == term.id then
      ideSidebarState.lastActiveIdx = i
      break
    end
  end

  term:show()
end

function ideSidebar.sendTextToTmux(sessionName, text)
  local bracketStart = '\27[200~'
  local bracketEnd = '\27[201~\r'
  local bracketedText = bracketStart .. text .. bracketEnd
  vim.system(
    { 'tmux', 'load-buffer', '-b', 'ngcbuffer0', '-' },
    { stdin = bracketedText },
    function(result)
      if result.code == 0 then
        os.execute(
          string.format('tmux paste-buffer -b ngcbuffer0 -t "%s"', sessionName)
        )
        os.execute(string.format('tmux select-window -t "%s"', sessionName))
      else
        -- TODO change this to notify (via vim schedule)
        log.error('Failed to send text to tmux')
      end
    end
  )
end

--- Send text to sidebar last active terminal
-- Text is bracketed to ensure single block treatment
-- Used internally to send commands or data to active Gemini/Qwen terminal
-- @param text string The text to send to the terminal
-- @return nil
function ideSidebar.sendText(text)
  local activeSessions = ideSidebar.getActiveTerminals()
  local routeTextToSession = function(sessionName)
    if string.match(sessionName, '^sidebar:') then
      -- routing to sidebar term session
      local term = nil
      local activeTerms = terminal.getActiveTerminals()
      for idx, activeTerm in pairs(activeTerms) do
        local name = activeTerm.config.name or idx
        if name == string.gsub(sessionName, '^sidebar:', '') then
          term = activeTerm
          break
        end
      end
      if not term then
        vim.notify(
          string.format('Session %s not found', sessionName),
          vim.log.levels.ERROR
        )
        return
      end
      ideSidebar.sendTextToTerm(term, text)
    else
      -- routing to tmux session
      sessionName = string.gsub(sessionName, '^tmux:', '')
      ideSidebar.sendTextToTmux(sessionName, text)
    end
  end

  if #activeSessions == 0 then
    -- Fallback to lastActiveTerminal if no active sessions found
    local opts = ideSidebarState.terminalOpts[ideSidebarState.lastActiveIdx]
    local term = terminal.create(opts.cmd, opts)
    ideSidebar.sendTextToTerm(term, text)
    return
  elseif #activeSessions == 1 then
    routeTextToSession(activeSessions[1])
  else
    -- Multiple active sessions, prompt user to select one
    vim.ui.select(activeSessions, {
      prompt = 'Select a session to send text to:',
    }, function(choice)
      if not choice then return end
      routeTextToSession(choice)
    end)
  end
end

-- Helper function to spawn tmux window with proper configuration
local function spawnTmuxWithConfig(optIndex, cmd, env)
  if not cmd then return end
  local windowName = string.format('%s-ngc-%d(%s)', cwdBase, optIndex, cmd)

  local windowId = findMatchingTmuxWindow(windowName)
  if windowId then
    -- Window exists, switch to it
    os.execute('tmux select-window -t ' .. windowId)
  else
    -- Window does not exist, create it with proper environment variables
    local envCmd = ''
    if type(env) == 'table' then
      for key, value in pairs(env) do
        envCmd = envCmd
          .. string.format('%s="%s" ', tostring(key), tostring(value))
      end
    end

    os.execute(
      'tmux new-window -n "' .. windowName .. '" "' .. envCmd .. cmd .. '"'
    )
  end
end

--- Spawn a new tmux window with the specified CLI or switch to it if it already exists.
-- @param cmd string The command to execute (e.g., 'gemini', 'qwen'). If nil, prompts user to select.
function ideSidebar.spawnOrSwitchToTmux(cmd)
  if not isTmux() then
    vim.notify('Not running in a tmux session.', vim.log.levels.WARN)
    return
  end

  -- local function to extract index and env variable for a command
  local getIndexAndEnv = function(fcmd)
    if not fcmd then return nil, nil end
    local index = nil
    local env = nil
    for i, opt in ipairs(ideSidebarState.terminalOpts) do
      if opt.cmd == fcmd then
        index = i
        env = opt.env
        break
      end
    end
    return index, env
  end

  -- If no cmd provided, prompt user to select one
  if not cmd or cmd == '' then
    if #ideSidebarState.terminalOpts == 0 then
      vim.notify('No terminal commands configured.', vim.log.levels.ERROR)
      return
    elseif #ideSidebarState.terminalOpts == 1 then
      local opt = ideSidebarState.terminalOpts[1]
      return spawnTmuxWithConfig(1, opt.cmd, opt.env)
    else
      local cmdOptions = {}
      for _, opt in ipairs(ideSidebarState.terminalOpts) do
        local optionText = string.format('%s', opt.cmd)
        table.insert(cmdOptions, optionText)
      end
      vim.ui.select(cmdOptions, {
        prompt = 'Select a command to spawn in tmux:',
      }, function(choice)
        local index, env = getIndexAndEnv(choice)
        return spawnTmuxWithConfig(index, choice, env)
      end)
    end
  else
    local index, env = getIndexAndEnv(cmd)
    if not index or not env then
      vim.notify(
        string.format(
          'Command "%s" not found in configured terminal options.',
          cmd
        ),
        vim.log.levels.WARN
      )
      return
    end
    spawnTmuxWithConfig(index, cmd, env)
  end
end

--- Get active terminals and tmux sessions
-- Combines active terminals from terminal.lua with tmux sessions named ngc-agent(*)
-- @return table A list of active sessions with prefixed names
function ideSidebar.getActiveTerminals()
  -- Get active terminals from terminal.lua
  local activeTerminals = terminal.getActiveTerminals()
  local combinedSessions = {}

  -- Validate and add active terminals
  for id, term in pairs(activeTerminals) do
    if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
      local termName = 'sidebar:' .. (term.config.name or id)
      table.insert(combinedSessions, termName)
    end
  end

  -- Find matching tmux sessions
  if isTmux() then
    local command = 'tmux list-windows -F "#{window_name},#{window_id}"'
    local handle = io.popen(command)
    if handle then
      local pattern = string.format('%s-ngc-', cwdBase)
      local result = handle:read('*a')
      handle:close()
      for line in result:gmatch('[^\n]+') do
        local sessionName, _ = line:match('^(.*),(.*)')
        if
          sessionName and vim.fn.match(sessionName, '\\V' .. pattern) ~= -1
        then
          local tmuxSessionName = 'tmux:' .. sessionName
          table.insert(combinedSessions, tmuxSessionName)
        end
      end
    end
  end

  return combinedSessions
end

-------------------------------------------------------
--- Main Setup Function
-------------------------------------------------------
--- Setup Gemini sidebar with user commands and terminal configurations
-- Initialize terminal options for each command in opts, set up environment
-- variables for Gemini/Qwen tools, create user commands to interact with
-- sidebar. Must call to initialize sidebar functionality.
-- @param opts table Configuration options:
--    - cmds (table): List of commands to init ('gemini', 'qwen', etc.)
--    - cmd (string): Single command to use (alternative to cmds)
--    - port (number): Port number for the Gemini/Qwen server
--    - env (table): Additional environment variables
--    - win (table): Window configuration options including preset
-- @return nil
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
    name = nil,
  }

  for i, key in ipairs(presetKeys) do
    if key == 'right' then
      ideSidebarState.rightPresetIdx = i
      break
    end
  end

  -------------------------------------------------------
  --- Creating Opts for Each Terminal
  -------------------------------------------------------
  opts = vim.tbl_deep_extend('force', defaults, opts)
  ideSidebarState.port = opts.port
  if opts.cmd then opts.cmds = { opts.cmd } end
  for idx, cmd in ipairs(opts.cmds) do
    local termOpts =
      vim.tbl_deep_extend('force', vim.deepcopy(opts), { cmd = cmd })
    local onBuffer = termOpts.on_buf
    local name = string.format('%s-ngc-%d(%s)', cwdBase, idx, cmd)

    termOpts.name = name
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
    -- Use the public deterministic ID creation method
    termOpts.id =
      ideSidebar.createDeterministicId(termOpts.cmd, termOpts.env, idx)

    if #opts.cmds > 1 then
      termOpts.on_buf = function(buf)
        vim.api.nvim_buf_set_keymap(
          buf,
          't',
          '<Tab>',
          '<Cmd>lua require("gemini.ideSidebar").switchTerms()<CR>', -- Corrected escaping for nested quotes
          { noremap = true, silent = true }
        )
        if type(onBuffer) == 'function' then onBuffer(buf) end
      end
    end

    ::continue::
    if termOpts then table.insert(ideSidebarState.terminalOpts, termOpts) end
  end

  if #ideSidebarState.terminalOpts == 0 then
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
    'GeminiToggleTmux',
    function(cmdOpts) ideSidebar.spawnOrSwitchToTmux(cmdOpts.fargs[1]) end,
    {
      nargs = '*',
      desc = 'Spawn or switch to a tmux window with the specified CLI. If no command is given, prompts for selection.',
      complete = function() return { 'gemini', 'qwen' } end,
    }
  )

  vim.api.nvim_create_user_command(
    'GeminiSwitchSidebarStyle',
    function(cmdOpts) ideSidebar.switchStyle(cmdOpts.fargs[1]) end,
    {
      nargs = '?',
      desc = 'Switch the style of the Gemini/Qwen sidebar. Presets:'
        .. vim.inspect(terminal.presets or {}),
      complete = function() return presetKeys end,
    }
  )

  vim.api.nvim_create_user_command(
    'GeminiSend',
    function(cmdOpts) ideSidebar.sendSelectedText(cmdOpts) end,
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

----------------------------------------------------------------
--- Helper Methods
----------------------------------------------------------------
-- Create a deterministic ID from command and environment
-- Sorts the environment recursively and replaces special chars with underscores
-- @param cmd string The command name
-- @param env table The environment table
-- @return string A deterministic ID string
function ideSidebar.createDeterministicId(cmd, env, idx)
  local sortedEnv = sortTableRecursively(env)
  local idStr = cmd
    .. ':'
    .. vim.inspect(sortedEnv, { newline = '', indent = '' })
    .. (idx and ':' .. idx or '')
  -- Replace whitespace and special characters with underscores
  -- to make it more deterministic, also replace subsequent underscores
  -- with a single underscore
  idStr = string.gsub(idStr, '[%s%p]', '_')
  idStr = string.gsub(idStr, '[_]+', '_')
  return idStr
end

-------------------------------------------------------
--- Module Ends
-------------------------------------------------------
return ideSidebar
