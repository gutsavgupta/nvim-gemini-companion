-- This file was created on September 25, 2025
-- This is the main entry point for the nvim-gemini-companion plugin.
-- It initializes the MCP server, sidebar, and context manager.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})
local M = {}

-- Defer loading of modules to speed up startup
local ideMcpServer
local ideCntxManager
local ideDiffManager
local ideSidebar
local announcement

-- Lazily loads the plugin's modules.
-- This is done to improve Neovim's startup time by only
-- loading the modules when they are first needed.
local function load_modules()
  if ideMcpServer then return end
  ideMcpServer = require('gemini.ideMcpServer')
  ideCntxManager = require('gemini.ideCntxManager')
  ideDiffManager = require('gemini.ideDiffManager')
  ideSidebar = require('gemini.ideSidebar')
  announcement = require('gemini.announce')
end

local server = nil

---
-- Sends a JSON-RPC notification to the Gemini CLI via the MCP server.
-- This is used for server-to-client communication without expecting a response.
-- @param method string The method name of the notification (e.g., 'ide/contextUpdate').
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

-- Handles the 'initialize' request from the MCP client.
-- This is the first request sent by the client to the server.
-- It returns the server's capabilities and information.
-- @param client table The client instance that sent the request.
-- @param request table The JSON-RPC request object.
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

-- Handles the 'initialized' notification from the MCP client.
-- This notification is sent by the client after it has received the 'initialize' response.
-- It indicates that the client is ready to receive notifications from the server.
-- @param client table The client instance that sent the request.
-- @param request table The JSON-RPC request object.
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

-- Handles the 'tools/list' request from the MCP client.
-- This request asks the server to provide a list of available tools.
-- The server responds with a list of tools that the user can execute.
-- @param client table The client instance that sent the request.
-- @param request table The JSON-RPC request object.
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

-- Handles the 'tools/call' request from the MCP client.
-- This request asks the server to execute a specific tool with the given parameters.
-- @param client table The client instance that sent the request.
-- @param request table The JSON-RPC request object, containing the tool name and arguments.
local function handleToolCall(client, request)
  local reloadFunction = function(filePath)
    vim.defer_fn(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local bufname = vim.api.nvim_buf_get_name(buf)
        if bufname == filePath then
          vim.api.nvim_buf_call(buf, function() vim.cmd('checktime') end)
        end
      end
    end, 200)
  end

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
        elseif status == 'rejected' then
          sendMcpNotification('ide/diffClosed', {
            filePath = toolParams.filePath,
          })
        end
        reloadFunction(toolParams.filePath)
      end
    )
  elseif toolName == 'closeDiff' then
    local finalContent = ideDiffManager.close(toolParams.filePath)
    responseTbl.result.content[1].text = finalContent
    reloadFunction(toolParams.filePath)
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

--- Sets up the plugin. This should be called from the user's Neovim config.
-- @param opts table Configuration options for the plugin.
--   - width (number): Width of the sidebar.
--   - command (string): The command to run for the Gemini CLI.
--   - autoRead (boolean): Enable automatic file reading when changed outside of Neovim (default: true).
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
  opts.port = port
  vim.api.nvim_create_autocmd('VimLeave', {
    pattern = '*',
    callback = function()
      if server then server:close() end
    end,
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

  -- 3. Setup sidebar (this will check if binaries exist and warn if none found)
  ideSidebar.setup(opts)

  -- 4. Setup diff manager
  ideDiffManager.setup()

  -- 5. Setup announcement
  announcement.setup()

  -- 6. Setup autoread functionality (enabled by default unless explicitly disabled)
  if opts.autoRead ~= false then M.enableAutoread() end

  log.info('nvim-gemini-companion setup complete.')
end

---
-- Enables autoread functionality to automatically read files when changed outside of Neovim.
function M.enableAutoread()
  if M.autoreadAucmd then
    -- Autoread is already enabled, just return
    return
  end

  vim.opt.autoread = true
  M.autoreadAucmd = vim.api.nvim_create_autocmd(
    { 'BufEnter', 'WinEnter', 'FocusGained' },
    {
      pattern = '*',
      callback = function()
        -- When a file is changed outside of Neovim, check if the buffer should be reloaded
        local currentFile = vim.fn.expand('%:p')
        if currentFile ~= '' then
          vim.cmd('checktime') -- Check if file has been modified and reload if needed
        end
      end,
    }
  )

  log.info('Autoread enabled')
end

---
-- Disables autoread functionality.
function M.disableAutoread()
  if M.autoreadAucmd then
    vim.api.nvim_del_autocmd(M.autoreadAucmd)
    M.autoreadAucmd = nil
  end

  vim.opt.autoread = false
  log.info('Autoread disabled')
end

return M
