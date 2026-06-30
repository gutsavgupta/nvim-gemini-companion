-- Claude Code tool surface.
--
-- Defines the MCP tools advertised to the `claude` CLI and their handlers.
-- Tool results use MCP "content arrays" ({ content = { { type='text', ... } } }).
-- `openDiff` is blocking: its response is withheld until the user accepts
-- (FILE_SAVED + content) or rejects (DIFF_REJECTED) the diff.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local M = {}

local JSON_SCHEMA = 'http://json-schema.org/draft-07/schema#'

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
--- Wrap a Lua value as an MCP text-content result (JSON-encoded).
local function textResult(tbl)
  return { content = { { type = 'text', text = vim.json.encode(tbl) } } }
end

--- Wrap a plain string as an MCP text-content result.
local function rawTextResult(str)
  return { content = { { type = 'text', text = str } } }
end

local function fileUrl(path) return 'file://' .. path end

--- Find a loaded buffer by (absolute) file path.
local function findBuf(path)
  local abs = vim.fn.fnamemodify(path, ':p')
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(b)
      and vim.api.nvim_buf_get_name(b) == abs
    then
      return b
    end
  end
  return nil
end

local severityNames = { [1] = 'Error', [2] = 'Warning', [3] = 'Info', [4] = 'Hint' }

-------------------------------------------------------------------------------
-- Tool definitions
-------------------------------------------------------------------------------
-- Each tool: { name, description, inputSchema, handler = fn(params, client, respond) }
-- respond(result, errTable). Read tools respond synchronously; openDiff defers.
local tools = {}

tools.openDiff = {
  name = 'openDiff',
  description = 'Open a diff view comparing old file content with new file content',
  inputSchema = {
    type = 'object',
    properties = {
      old_file_path = { type = 'string', description = 'Path to the old file to compare' },
      new_file_path = { type = 'string', description = 'Path to the new file to compare' },
      new_file_contents = { type = 'string', description = 'Contents for the new file version' },
      tab_name = { type = 'string', description = 'Name for the diff tab/view' },
    },
    required = { 'old_file_path', 'new_file_path', 'new_file_contents', 'tab_name' },
    additionalProperties = false,
    ['$schema'] = JSON_SCHEMA,
  },
  handler = function(params, client, respond)
    if not (params.old_file_path and params.new_file_contents) then
      respond(nil, { code = -32602, message = 'Invalid params', data = 'Missing required parameter' })
      return
    end
    local diff = require('gemini.ideDiffManager')
    local filePath = params.old_file_path
    diff.open(filePath, params.new_file_contents, function(finalContent, status)
      if status == 'accepted' then
        respond({
          content = {
            { type = 'text', text = 'FILE_SAVED' },
            { type = 'text', text = finalContent or '' },
          },
        })
      else
        respond(rawTextResult('DIFF_REJECTED'))
      end
      -- Reload the buffer so the editor reflects what Claude will write to disk.
      vim.defer_fn(function()
        local b = findBuf(filePath)
        if b then vim.api.nvim_buf_call(b, function() vim.cmd('checktime') end) end
      end, 200)
    end, { clientId = client and client.id })
  end,
}

tools.openFile = {
  name = 'openFile',
  description = 'Open a file in the editor and optionally select a range of text',
  inputSchema = {
    type = 'object',
    properties = {
      filePath = { type = 'string', description = 'Path to the file to open' },
      startLine = { type = 'integer', description = 'Optional 0-indexed start line to select' },
      endLine = { type = 'integer', description = 'Optional 0-indexed end line to select' },
    },
    required = { 'filePath' },
    additionalProperties = false,
    ['$schema'] = JSON_SCHEMA,
  },
  handler = function(params, _, respond)
    if not params.filePath then
      respond(nil, { code = -32602, message = 'Invalid params', data = 'Missing filePath' })
      return
    end
    vim.schedule(function()
      pcall(vim.cmd, 'edit ' .. vim.fn.fnameescape(params.filePath))
      if type(params.startLine) == 'number' then
        pcall(vim.api.nvim_win_set_cursor, 0, { params.startLine + 1, 0 })
      end
    end)
    respond(rawTextResult('FILE_OPENED'))
  end,
}

tools.getCurrentSelection = {
  name = 'getCurrentSelection',
  description = 'Get the current text selection in the editor',
  inputSchema = { type = 'object', additionalProperties = false, ['$schema'] = JSON_SCHEMA },
  handler = function(_, _, respond)
    local cntx = require('gemini.ideCntxManager')
    local sel = cntx.getClaudeSelection()
    if not sel then
      respond(textResult({ success = false, message = 'No active editor found' }))
      return
    end
    respond(textResult(sel))
  end,
}

tools.getLatestSelection = {
  name = 'getLatestSelection',
  description = 'Get the most recent text selection (even if no longer active)',
  inputSchema = { type = 'object', additionalProperties = false, ['$schema'] = JSON_SCHEMA },
  handler = function(_, _, respond)
    local cntx = require('gemini.ideCntxManager')
    local sel = cntx.getClaudeSelection()
    if not sel then
      respond(textResult({ success = false, message = 'No selection available' }))
      return
    end
    respond(textResult(sel))
  end,
}

tools.getOpenEditors = {
  name = 'getOpenEditors',
  description = 'Get a list of files currently open in the editor',
  inputSchema = { type = 'object', additionalProperties = false, ['$schema'] = JSON_SCHEMA },
  handler = function(_, _, respond)
    local editors = {}
    local current = vim.api.nvim_get_current_buf()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buflisted then
        local name = vim.api.nvim_buf_get_name(b)
        if name and name ~= '' then
          table.insert(editors, {
            filePath = name,
            fileUrl = fileUrl(name),
            isDirty = vim.bo[b].modified or false,
            isActive = (b == current),
          })
        end
      end
    end
    respond(textResult({ editors = editors }))
  end,
}

tools.getWorkspaceFolders = {
  name = 'getWorkspaceFolders',
  description = 'Get the workspace folders currently open in the editor',
  inputSchema = { type = 'object', additionalProperties = false, ['$schema'] = JSON_SCHEMA },
  handler = function(_, _, respond)
    local lockfile = require('gemini.claude.lockfile')
    local folders = {}
    for _, path in ipairs(lockfile.get_workspace_folders()) do
      table.insert(folders, { name = vim.fn.fnamemodify(path, ':t'), uri = fileUrl(path), path = path })
    end
    respond(textResult({ folders = folders, rootPath = vim.fn.getcwd() }))
  end,
}

tools.getDiagnostics = {
  name = 'getDiagnostics',
  description = 'Get language diagnostics (errors, warnings) from the editor',
  inputSchema = {
    type = 'object',
    properties = {
      uri = { type = 'string', description = 'Optional file URI to filter diagnostics' },
    },
    additionalProperties = false,
    ['$schema'] = JSON_SCHEMA,
  },
  handler = function(params, _, respond)
    local filterBuf = nil
    if params and type(params.uri) == 'string' and params.uri ~= '' then
      local path = params.uri:gsub('^file://', '')
      filterBuf = findBuf(path)
    end

    local results = {}
    local diags = vim.diagnostic.get(filterBuf)
    for _, d in ipairs(diags) do
      local bufPath = vim.api.nvim_buf_get_name(d.bufnr)
      table.insert(results, {
        uri = fileUrl(bufPath),
        message = d.message,
        severity = severityNames[d.severity] or 'Info',
        source = d.source or '',
        range = {
          start = { line = d.lnum, character = d.col },
          ['end'] = { line = d.end_lnum or d.lnum, character = d.end_col or d.col },
        },
      })
    end
    respond(textResult({ diagnostics = results }))
  end,
}

tools.checkDocumentDirty = {
  name = 'checkDocumentDirty',
  description = 'Check if a document has unsaved changes',
  inputSchema = {
    type = 'object',
    properties = { filePath = { type = 'string', description = 'Path to the document' } },
    required = { 'filePath' },
    additionalProperties = false,
    ['$schema'] = JSON_SCHEMA,
  },
  handler = function(params, _, respond)
    local b = params.filePath and findBuf(params.filePath)
    if not b then
      respond(textResult({ success = false, message = 'Document not open', filePath = params.filePath }))
      return
    end
    respond(textResult({ success = true, filePath = params.filePath, isDirty = vim.bo[b].modified or false }))
  end,
}

tools.saveDocument = {
  name = 'saveDocument',
  description = 'Save a document with unsaved changes',
  inputSchema = {
    type = 'object',
    properties = { filePath = { type = 'string', description = 'Path to the document' } },
    required = { 'filePath' },
    additionalProperties = false,
    ['$schema'] = JSON_SCHEMA,
  },
  handler = function(params, _, respond)
    local b = params.filePath and findBuf(params.filePath)
    if not b then
      respond(textResult({ success = false, message = 'Document not open', filePath = params.filePath }))
      return
    end
    vim.schedule(function()
      pcall(vim.api.nvim_buf_call, b, function() vim.cmd('write') end)
    end)
    respond(textResult({ success = true, filePath = params.filePath }))
  end,
}

tools.closeAllDiffTabs = {
  name = 'closeAllDiffTabs',
  description = 'Close all open diff tabs in the editor',
  inputSchema = { type = 'object', additionalProperties = false, ['$schema'] = JSON_SCHEMA },
  handler = function(_, _, respond)
    local diff = require('gemini.ideDiffManager')
    local count = diff.closeAll('closeAllDiffTabs')
    respond(rawTextResult('CLOSED_' .. tostring(count) .. '_DIFF_TABS'))
  end,
}

M._tools = tools

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
--- Build the tools/list payload.
--- @return table list Array of { name, description, inputSchema }.
function M.get_tool_list()
  local list = {}
  -- Stable ordering for deterministic output.
  local names = {}
  for name in pairs(tools) do
    table.insert(names, name)
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local t = tools[name]
    table.insert(list, { name = t.name, description = t.description, inputSchema = t.inputSchema })
  end
  return list
end

--- Invoke a tool.
--- @param name string Tool name.
--- @param params table Tool arguments.
--- @param client table|nil The MCP client.
--- @param respond function function(result, errTable).
function M.invoke(name, params, client, respond)
  local tool = tools[name]
  if not tool then
    respond(nil, { code = -32601, message = 'Tool not found: ' .. tostring(name) })
    return
  end
  local ok, err = pcall(tool.handler, params or {}, client, respond)
  if not ok then
    log.error('tools: handler error for ' .. tostring(name) .. ': ' .. tostring(err))
    respond(nil, { code = -32000, message = 'Tool execution failed', data = tostring(err) })
  end
end

return M
