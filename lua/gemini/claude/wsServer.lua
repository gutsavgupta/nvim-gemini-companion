-- WebSocket MCP server for the Claude Code IDE integration.
--
-- Owns the listening TCP socket, accepts connections, drives each client through
-- the handshake + frame state machine (gemini.claude.wsClient), and exposes
-- JSON-RPC send/broadcast helpers. A single open WebSocket carries the full
-- bidirectional MCP session (requests, responses and notifications).
--
-- Binding follows the same single-port reuse/fallback pattern as the existing
-- HTTP/SSE server (gemini.ideMcpServer): try a preferred port (for reconnection),
-- else bind a random one.

local wsClient = require('gemini.claude.wsClient')
local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local IdeWsServer = {}
IdeWsServer.__index = IdeWsServer

--- Create a new WebSocket MCP server.
--- @param callbacks table
---   - onClientRequest: function(client, decodedMessage) JSON-RPC message in.
---   - onClientConnect: function(client) optional.
---   - onClientClose: function(client, code, reason) optional.
---   - authToken: string|nil token required on the upgrade handshake.
--- @return table self
function IdeWsServer.new(callbacks)
  local self = setmetatable({}, IdeWsServer)
  self.server = vim.uv.new_tcp()
  self.onClientRequest = callbacks.onClientRequest
  self.onClientConnect = callbacks.onClientConnect
  self.onClientClose = callbacks.onClientClose
  self.authToken = callbacks.authToken
  self.clients = {}
  self.pingTimer = nil
  log.info('wsServer: new server created')
  return self
end

--- Start listening. Tries the preferred port first (for reconnection), falling
--- back to a random port if it is unavailable.
--- @param preferredPort number|nil The port to try first (0/nil = random).
--- @return number port The port actually bound.
function IdeWsServer:start(preferredPort)
  local ok = self.server:bind('127.0.0.1', preferredPort or 0)
  if not ok and preferredPort and preferredPort ~= 0 then
    log.warn(
      'wsServer: could not reuse port '
        .. tostring(preferredPort)
        .. ', falling back to a random port'
    )
    self.server:bind('127.0.0.1', 0)
  end

  self.server:listen(64, function(err)
    if err then
      log.error('wsServer: listen error: ' .. tostring(err))
      return
    end
    self:_acceptConnection()
  end)

  self:_startPingTimer(30000)

  local sockname = self.server:getsockname()
  local port = sockname and sockname.port or 0
  log.info('wsServer: listening on port ' .. tostring(port))
  return port
end

function IdeWsServer:_acceptConnection()
  local tcpClient = vim.uv.new_tcp()
  local accepted = self.server:accept(tcpClient)
  if not accepted then
    tcpClient:close()
    return
  end

  local client = wsClient.create_client(tcpClient)
  self.clients[client.id] = client
  log.debug('wsServer: accepted connection ' .. client.id)

  tcpClient:read_start(function(err, data)
    if err then
      log.error('wsServer(' .. client.id .. '): read error: ' .. tostring(err))
      self:_disconnect(client, 1006, tostring(err))
      return
    end
    if not data then
      self:_disconnect(client, 1006, 'EOF')
      return
    end
    wsClient.process_data(client, data, function(cl, message)
      self:_onMessage(cl, message)
    end, function(cl, code, reason)
      self:_disconnect(cl, code, reason)
    end, function(cl, errMsg)
      log.warn('wsServer(' .. cl.id .. '): ' .. tostring(errMsg))
      self:_disconnect(cl, 1006, tostring(errMsg))
    end, self.authToken)
  end)

  if self.onClientConnect then
    vim.schedule(function() self.onClientConnect(client) end)
  end
end

function IdeWsServer:_onMessage(client, message)
  local ok, decoded = pcall(vim.json.decode, message)
  if not ok or type(decoded) ~= 'table' then
    log.warn('wsServer(' .. client.id .. '): JSON decode error')
    return
  end
  if self.onClientRequest then self.onClientRequest(client, decoded) end
end

function IdeWsServer:_disconnect(client, code, reason)
  if not self.clients[client.id] then return end
  self.clients[client.id] = nil
  if self.onClientClose then
    pcall(self.onClientClose, client, code, reason)
  end
  if client.tcp_handle and not client.tcp_handle:is_closing() then
    client.tcp_handle:close()
  end
end

--- Send a JSON-RPC message table to a specific client.
--- @param client table The client object.
--- @param tbl table The message table (JSON encoded before sending).
function IdeWsServer:send(client, tbl)
  if not client or not self.clients[client.id] then return false end
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok then
    log.error('wsServer(' .. client.id .. '): JSON encode error')
    return false
  end
  wsClient.send_message(client, encoded)
  return true
end

--- Broadcast a JSON-RPC message table to all connected clients.
--- @param tbl table The message table.
function IdeWsServer:broadcast(tbl)
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok then
    log.error('wsServer: broadcast JSON encode error')
    return
  end
  for _, client in pairs(self.clients) do
    wsClient.send_message(client, encoded)
  end
end

--- Number of currently connected clients.
function IdeWsServer:getClientCount()
  local count = 0
  for _ in pairs(self.clients) do
    count = count + 1
  end
  return count
end

function IdeWsServer:_startPingTimer(interval)
  self.pingTimer = vim.uv.new_timer()
  if not self.pingTimer then return end
  self.pingTimer:start(interval, interval, function()
    for _, client in pairs(self.clients) do
      if client.state == 'connected' then
        if wsClient.is_client_alive(client, interval * 2) then
          wsClient.send_ping(client, 'ping')
        else
          wsClient.close_client(client, 1006, 'Connection timeout')
          self:_disconnect(client, 1006, 'Connection timeout')
        end
      end
    end
  end)
end

--- Close the server and all client connections.
function IdeWsServer:close()
  log.info('wsServer: closing server')
  if self.pingTimer then
    self.pingTimer:stop()
    if not self.pingTimer:is_closing() then self.pingTimer:close() end
    self.pingTimer = nil
  end
  for _, client in pairs(self.clients) do
    wsClient.close_client(client, 1001, 'Server shutting down')
  end
  self.clients = {}
  if self.server and not self.server:is_closing() then self.server:close() end
end

return IdeWsServer
