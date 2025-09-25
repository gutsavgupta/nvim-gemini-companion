-- This file was created on September 25, 2025
-- This is the main entry point for the nvim-gemini-companion plugin.
-- It initializes the MCP server, sidebar, and context manager.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local M = {}

-- Defer loading of modules to speed up startup
local ideMcpServer, ideCntxManager, ideDiffManager, ideSidebar
local function load_modules()
  if ideMcpServer then return end
  ideMcpServer = require('gemini.ideMcpServer')
  ideCntxManager = require('gemini.ideCntxManager')
  ideDiffManager = require('gemini.ideDiffManager')
  ideSidebar = require('gemini.ideSidebar')
end

local server = nil

---
-- Sends a JSON-RPC notification to the Gemini CLI.
-- @param method string The method name of the notification.
-- @param params table The parameters for the notification.
local function sendMcpNotification(method, params)
  if server then
    log.debug('Sending notification:', { method = method, params = params })
    server:BroadcastToStreams({
      jsonrpc = '2.0',
      method = method,
      params = params,
    })
  else
    log.warn('MCP server not running, cannot send notification.')
  end
end

local function handleInitialization(client, request)
  local responseTbl = {
    jsonrpc = '2.0',
    id = request.id,
    result = {
      capabilities = { tools = { listChanged = false } },
      instructions = table.concat({
        'This is the nvim-ide-companion. It can open and close diff ',
        'views send context update via ide/ContextUpdate notification',
      }),
      protocolVersion = '2025-06-18',
      serverInfo = { name = 'nvim-ide-companion', version = '0.0.1' },
    },
  }
  if client then client:send(responseTbl) end
end

local function handleInitialized(client, request)
  local responseTbl = { jsonrpc = '2.0', id = request.id, result = {} }
  if client then client:send(responseTbl) end

  -- Send initial context
  vim.schedule(
    function()
      sendMcpNotification('ide/contextUpdate', ideCntxManager.getContext())
    end
  )
end

local function handleToolsList(client, request)
  local responseTbl = {
    jsonrpc = '2.0',
    id = request.id,
    result = {
      tools = {
        {
          name = 'openDiff',
          description = 'Open a diff view',
          inputSchema = {
            type = 'object',
            properties = {
              filePath = { type = 'string' },
              newContent = { type = 'string' },
            },
            required = { 'filePath', 'newContent' },
          },
        },
        {
          name = 'closeDiff',
          description = 'Close a diff view',
          inputSchema = {
            type = 'object',
            properties = { filePath = { type = 'string' } },
            required = { 'filePath' },
          },
        },
      },
    },
  }
  if client then client:send(responseTbl) end
end

local function handleToolCall(client, request)
  local toolName = request.params.name
  local toolParams = request.params.arguments
  local responseTbl = {
    jsonrpc = '2.0',
    id = request.id,
    result = {
      content = { { type = 'text', text = 'Tool called ' .. toolName } },
    },
  }

  if toolName == 'openDiff' then
    ideDiffManager.open(
      toolParams.filePath,
      toolParams.newContent,
      function(finalContent, status)
        if status == 'accepted' then
          sendMcpNotification('ide/diffAccepted', {
            filePath = toolParams.filePath,
            content = finalContent,
          })
        else
          sendMcpNotification('ide/diffClosed', {
            filePath = toolParams.filePath,
            content = finalContent,
          })
        end
      end
    )
  elseif toolName == 'closeDiff' then
    ideDiffManager.close(toolParams.filePath)
  else
    log.warn('Unhandled tool call:', toolName)
    if client then client:close() end
    return
  end
  if client then client:send(responseTbl) end
end

---
-- Handles incoming JSON-RPC requests from the Gemini CLI.
-- @param client table The client instance that sent the request.
-- @param request table The JSON-RPC request object.
local function handleMcpRequest(client, request)
  local method = request.method
  log.debug('Handling MCP request:', request)

  if method == 'initialize' then
    handleInitialization(client, request)
  elseif method == 'notifications/initialized' then
    handleInitialized(client, request)
  elseif method == 'tools/list' then
    handleToolsList(client, request)
  elseif method == 'tools/call' then
    handleToolCall(client, request)
  else
    log.warn('Unhandled McpRequest:', method)
    client:close()
  end
end

---
-- Sets up the plugin. This should be called from the user's Neovim config.
-- @param opts table Configuration options for the plugin.
--   - width (number): Width of the sidebar.
--   - command (string): The command to run for the Gemini CLI.
function M.setup(opts)
  opts = opts or {}
  log.info('Setting up nvim-gemini-companion with options:', opts)
  load_modules()

  -- 1. Start MCP server
  server = ideMcpServer.new({
    onClientRequest = handleMcpRequest,
    onClientClose = function() end,
  })
  local port = server:start(0) -- Listen on a random port
  log.info('MCP Server started on port: ' .. port)
  vim.api.nvim_create_autocmd('VimLeave', {
    pattern = '*',
    callback = function() server:stop() end,
  })

  -- 2. Setup context manager
  ideCntxManager.setup(function()
    -- Send context update, throttle it to avoid spam
    if M.debounce_timer then vim.fn.timer_stop(M.debounce_timer) end
    M.debounce_timer = vim.fn.timer_start(100, function()
      local context = ideCntxManager.getContext()
      sendMcpNotification('ide/contextUpdate', context)
    end)
  end)

  -- 3. Setup sidebar
  ideSidebar.setup({
    port = port,
    command = opts.command,
    width = opts.width,
  })

  -- 4. Setup diff manager
  ideDiffManager.setup()

  log.info('nvim-gemini-companion setup complete.')
end

return M
