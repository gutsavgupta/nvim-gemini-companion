-- Claude Code IDE integration entry point.
--
-- Starts the WebSocket MCP server, writes the discovery lock file, dispatches
-- MCP JSON-RPC (initialize / tools/list / tools/call), and pushes
-- `selection_changed` notifications. Kept separate from the HTTP/SSE server used
-- by Gemini/Qwen (see requirement.md §4.1).

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local M = {}

local PROTOCOL_VERSION = '2024-11-05'
local SERVER_NAME = 'claudecode-neovim'
local SERVER_VERSION = '0.1.0'

local state = {
  server = nil,
  port = nil,
  authToken = nil,
  lockPath = nil,
}

-------------------------------------------------------------------------------
-- MCP dispatch
-------------------------------------------------------------------------------
local function handleRequest(client, request)
  local method = request.method
  local id = request.id

  -- A response is only owed when the message carries an id (request, not notification).
  local function respond(result, errData)
    if id == nil then return end
    local msg = { jsonrpc = '2.0', id = id }
    if errData then
      msg.error = errData
    else
      msg.result = result or vim.empty_dict()
    end
    state.server:send(client, msg)
  end

  if method == 'initialize' then
    respond({
      protocolVersion = PROTOCOL_VERSION,
      capabilities = {
        logging = vim.empty_dict(),
        prompts = { listChanged = true },
        tools = { listChanged = true },
      },
      serverInfo = { name = SERVER_NAME, version = SERVER_VERSION },
    })
  elseif method == 'notifications/initialized' then
    -- no-op ack (notification, no id)
  elseif method == 'prompts/list' then
    respond({ prompts = {} })
  elseif method == 'tools/list' then
    local tools = require('gemini.claude.tools')
    respond({ tools = tools.get_tool_list() })
  elseif method == 'tools/call' then
    local tools = require('gemini.claude.tools')
    local params = request.params or {}
    tools.invoke(params.name, params.arguments, client, function(result, errData)
      respond(result, errData)
    end)
  elseif id ~= nil then
    -- Unknown *request* (carries an id): a response is owed.
    log.warn('claude: unhandled MCP method: ' .. tostring(method))
    respond(nil, { code = -32601, message = 'Method not found: ' .. tostring(method) })
  else
    -- Unknown *notification* (no id), e.g. Claude's `ide_connected`. No response
    -- is owed; ignore it quietly (matches the reference server's behavior).
    log.debug('claude: ignoring notification: ' .. tostring(method))
  end
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------
--- Start the Claude integration.
--- @param opts table|nil { port = preferredPort, authToken = reuseToken }.
--- @return table|nil info { port, authToken, lockPath } or nil on failure.
function M.start(opts)
  opts = opts or {}
  if state.server then
    log.warn('claude: server already running')
    return { port = state.port, authToken = state.authToken, lockPath = state.lockPath }
  end

  local lockfile = require('gemini.claude.lockfile')
  local wsServer = require('gemini.claude.wsServer')

  local authToken = opts.authToken
  if type(authToken) ~= 'string' or #authToken < 10 then
    local ok, token = pcall(lockfile.generate_auth_token)
    if not ok then
      log.error('claude: failed to generate auth token: ' .. tostring(token))
      return nil
    end
    authToken = token
  end

  state.server = wsServer.new({
    authToken = authToken,
    onClientRequest = handleRequest,
    onClientClose = function(client)
      -- Force-reject any diffs this client opened but never resolved so the
      -- agent does not hang waiting on a withheld openDiff response.
      local diffOk, diff = pcall(require, 'gemini.ideDiffManager')
      if diffOk and diff.closeDiffsForClient then
        vim.schedule(function()
          diff.closeDiffsForClient(client.id, 'client disconnected')
        end)
      end
    end,
  })

  local port = state.server:start(opts.port)
  state.port = port
  state.authToken = authToken

  local createOk, lockPathOrErr = lockfile.create(port, authToken)
  if not createOk then
    log.error('claude: failed to write lock file: ' .. tostring(lockPathOrErr))
  else
    state.lockPath = lockPathOrErr
    log.info('claude: lock file written at ' .. lockPathOrErr)
  end

  log.info('claude: integration started on port ' .. tostring(port))
  return { port = port, authToken = authToken, lockPath = state.lockPath }
end

--- Broadcast a `selection_changed` notification to connected Claude clients.
function M.notifySelectionChanged()
  if not state.server then return end
  local cntx = require('gemini.ideCntxManager')
  local sel = cntx.getClaudeSelection()
  if not sel then return end
  state.server:broadcast({
    jsonrpc = '2.0',
    method = 'selection_changed',
    params = sel,
  })
end

--- Whether the Claude integration is currently running.
function M.isActive() return state.server ~= nil end

--- Status snapshot for the health check.
function M.getStatus()
  return {
    initialized = state.server ~= nil,
    port = state.port,
    lockPath = state.lockPath,
    authConfigured = state.authToken ~= nil,
    clients = state.server and state.server:getClientCount() or 0,
  }
end

--- Stop the integration: close the server and remove the lock file.
function M.stop()
  if state.port then require('gemini.claude.lockfile').remove(state.port) end
  if state.server then
    state.server:close()
    state.server = nil
  end
  state.port = nil
  state.authToken = nil
  state.lockPath = nil
end

return M
