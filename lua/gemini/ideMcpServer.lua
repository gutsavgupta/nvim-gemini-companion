local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'debug',
})

local IdeMcpClient = {}
IdeMcpClient.__index = IdeMcpClient

local IdeMcpServer = {}
IdeMcpServer.__index = IdeMcpServer

-------------------------------------------------------------------------------
-- Utility Functions
-------------------------------------------------------------------------------
--- Decodes an HTTP request from a buffer.
--- It parses the HTTP headers and body.
--- @param buffer string The input buffer containing the HTTP request.
--- @return table|nil headers A table of HTTP headers, or nil if parsing is incomplete.
--- @return string|nil body The HTTP request body, or nil if parsing is incomplete.
--- @return string remainingBuffer The remaining unparsed portion of the buffer.
local function httpDecoder(buffer)
  local headerEnd = buffer:find('\r\n\r\n')
  if not headerEnd then
    return nil, nil, buffer -- Headers not complete yet
  end

  local headers = {}
  local method, url, version = buffer:match('^(%S+) (%S+) HTTP/(%S+)')
  headers['method'] = method
  headers['url'] = url
  headers['version'] = version
  for name, value in buffer:gmatch('\r\n([%w-]+): ([^\r\n]*)') do
    headers[name:lower()] = value
  end

  local msgBody = buffer:sub(headerEnd + 4)
  local contentLength = tonumber(headers['content-length'] or 0)
  if contentLength > 0 and #msgBody < contentLength then
    return nil, nil, buffer -- Body not complete yet
  end

  local body = msgBody:sub(1, contentLength)
  local remainingBuffer = msgBody:sub(contentLength + 1)

  return headers, body, remainingBuffer
end

-------------------------------------------------------------------------------
-- Public Methods (IdeMcpServer)
-------------------------------------------------------------------------------
--- Creates a new IdeMcpServer instance.
--- @param callbacks table A table of callback functions.
---   - onClientRequest: function(client, request) - Called when a client sends a request.
---   - onClientClose: function() - Called when a client connection is closed.
--- @return table self The new IdeMcpServer instance.
function IdeMcpServer.new(callbacks)
  local self = setmetatable({}, IdeMcpServer)
  self.server = vim.uv.new_tcp()
  self.onClientRequest = callbacks.onClientRequest
  self.onClientClose = callbacks.onClientClose
  self.clientsObj = {}
  self.clientsIdx = 0
  log.info('ideMcpServer: new server created')
  return self
end

--- Starts the TCP server and begins listening for connections.
--- @param port number The port to listen on. If 0, a random available port is used.
--- @return number The port the server is listening on.
function IdeMcpServer:start(port)
  self.server:bind('127.0.0.1', port)
  self.server:listen(64, function(err)
    if err then
      log.error('ideMcpServer: listen error: ' .. tostring(err))
      return
    end

    local tcpClient = vim.uv.new_tcp()
    self.server:accept(tcpClient)
    log.info('ideMcpServer: accepted new connection')
    self.clientsObj[self.clientsIdx] = IdeMcpClient.new(
      self.clientsIdx,
      self.onClientRequest,
      self.onClientClose,
      tcpClient,
      self
    )
    self.clientsIdx = self.clientsIdx + 1
  end)

  local sockname = self.server:getsockname()
  log.info('ideMcpServer: listening on port', tostring(sockname.port))
  return sockname.port
end

--- Broadcasts a message to all connected streaming clients.
--- A streaming client is one that has established a connection via a GET request.
--- @param tlbMsg table The message table to be sent (will be JSON encoded).
function IdeMcpServer:BroadcastToStreams(tlbMsg)
  for _, client in pairs(self.clientsObj) do
    if client.isMcpStream then client:send(tlbMsg) end
  end
end

--- Sends a message to the most recently connected streaming client.
--- @param tlbMsg table The message table to be sent (will be JSON encoded).
function IdeMcpServer:SendToLastStream(tlbMsg)
  local lastClient = nil
  for _, client in pairs(self.clientsObj) do
    if client.isMcpStream then lastClient = client end
  end
  if lastClient then lastClient:send(tlbMsg) end
end

--- Closes the server and all active client connections.
function IdeMcpServer:close()
  log.info('ideMcpServer: closing server')
  for _, client in pairs(self.clientsObj) do
    client:close()
  end
  self.server:close()
end

-------------------------------------------------------------------------------
-- Public Methods (IdeMcpClient)
-------------------------------------------------------------------------------
--- Creates a new IdeMcpClient instance.
--- This is typically called by the IdeMcpServer when a new client connects.
--- @param clientId number The unique identifier for the client.
--- @param onClientRequest function The callback to execute when a request is received from this client.
--- @param onClientClose function The callback to execute when this client's connection is closed.
--- @param tcpClient userdata The underlying TCP client object from libuv.
--- @param server table The parent IdeMcpServer instance.
--- @return table self The new IdeMcpClient instance.
function IdeMcpClient.new(
  clientId,
  onClientRequest,
  onClientClose,
  tcpClient,
  server
)
  local self = setmetatable({}, IdeMcpClient)
  self.server = server
  self.clientId = clientId
  self.tcpClient = tcpClient
  self.onClientRequest = onClientRequest
  self.onClientClose = onClientClose

  -- State Management
  self.buffer = ''
  self.requestProcessed = false
  self.isMcpStream = false
  self.lastReadTime = 0
  self.lastWriteTime = 0
  self.keepAliveTimer = nil
  self:read()
  return self
end

--- Starts reading data from the client's TCP connection.
--- It sets up a callback to process incoming data chunks.
function IdeMcpClient:read()
  log.debug(string.format('ideMcpClient(c-%d): read started', self.clientId))
  self.tcpClient:read_start(function(err, data)
    self.lastReadTime = vim.loop.now()
    if err then
      log.error(
        string.format('ideMcpClient(c-%d): client read error:', self.clientId),
        { err = err }
      )
      self:close()
      return
    end
    if not data then
      log.info(
        string.format('ideMcpClient(c-%d): client disconnected.', self.clientId)
      )
      self:close()
      return
    end

    log.debug(
      string.format(
        'ideMcpClient(c-%d): received data:\n%s',
        self.clientId,
        data
      )
    )
    self.buffer = self.buffer .. data
    vim.schedule(function() self:_parseData() end)
  end)
end

--- Sends a message to the client.
--- The message is JSON-encoded and formatted as a Server-Sent Event.
--- @param mcpTbl table The message table to be sent.
function IdeMcpClient:send(mcpTbl)
  local success, encoded = pcall(vim.fn.json_encode, mcpTbl)
  if not success then
    log.error(
      string.format(
        'ideMcpClient(c-%d): JSON encode error: %s',
        self.clientId,
        tostring(encoded)
      )
    )
    return
  end
  local data = 'data: ' .. encoded .. '\n\n'
  self.tcpClient:write(data)
  self.lastWriteTime = vim.loop.now()
  log.debug(
    string.format('ideMcpClient(c-%d): sent message:\n%s', self.clientId, data)
  )
end

--- Closes the client connection.
--- It stops any timers, closes the TCP handle, and cleans up resources.
function IdeMcpClient:close()
  if not self.tcpClient then return end
  log.info(string.format('ideMcpClient(c-%d): closing client', self.clientId))
  if self.onClientClose then self.onClientClose() end
  if self.keepAliveTimer then self.keepAliveTimer:stop() end
  if not self.tcpClient:is_closing() then self.tcpClient:close() end
  self.server.clientsObj[self.clientId] = nil
  self.onClientClose = nil
  self.keepAliveTimer = nil
  self.tcpClient = nil
end

-------------------------------------------------------------------------------
-- Internal methods
-------------------------------------------------------------------------------
--- Internal helper to orchestrate parsing of the incoming data buffer.
--- It decides whether to parse a new HTTP message or handle subsequent data.
--- @see IdeMcpClient:_parseHttpMsg
function IdeMcpClient:_parseData()
  if not self.requestProcessed then
    self:_parseHttpMsg()
  else
    log.error(
      string.format(
        'ideMcpClient(c-%d): received another request after response',
        self.clientId
      )
    )
    self:close()
  end
end

--- Internal helper to parse the HTTP message from the buffer.
--- It handles GET requests by establishing a streaming connection and POST requests
--- by processing the incoming message.
function IdeMcpClient:_parseHttpMsg()
  local header, msgBody, remainingBuffer = httpDecoder(self.buffer)
  self.buffer = remainingBuffer

  if not header then
    log.debug(
      string.format(
        'ideMcpClient(c-%d): HttpHeader or Body not complete yet',
        self.clientId
      )
    )
    return
  end
  if header['url'] ~= '/mcp' then
    log.error(
      string.format(
        'ideMcpClient(c-%d): invalid url %s, only /mcp supported',
        self.clientId,
        header['url']
      )
    )
    self:close()
    return
  end

  if header['method'] == 'GET' then
    log.debug(
      string.format('ideMcpClient(c-%d): received GET request', self.clientId)
    )
    local responseHeaders = {
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream',
      'Cache-Control: no-cache',
      'Connection: keep-alive',
      '',
      '',
    }
    assert(#msgBody == 0)
    self.tcpClient:write(table.concat(responseHeaders, '\r\n'))
    self.isMcpStream = true
    self.keepAliveTimer = vim.uv.new_timer()
    self.keepAliveTimer:start(30000, 30000, function()
      local now = vim.loop.now()
      if
        now - self.lastReadTime < 30000 or now - self.lastWriteTime < 30000
      then
        log.debug(
          string.format(
            'ideMcpClient(c-%d): keep-alive skipped, recent activity',
            self.clientId
          )
        )
        return
      end
      if self.tcpClient:is_writable() then
        self.tcpClient:write(':keep-alive\n\n')
        log.debug(
          string.format(
            'ideMcpClient(c-%d): sent keep-alive packet',
            self.clientId
          )
        )
      end
    end)
  elseif header['method'] == 'POST' then
    log.debug(
      string.format('ideMcpClient(c-%d): received POST request', self.clientId)
    )
    local responseCode = '200 OK'
    local success, decoded = pcall(vim.fn.json_decode, msgBody)
    if not success then
      log.error(
        string.format(
          'ideMcpClient(c-%d): json decode error for message: %s',
          self.clientId,
          tostring(msgBody)
        )
      )
      self:close()
      return
    end
    if decoded.method == 'notifications/initialized' then
      responseCode = '202 Accepted'
    end
    local responseHeaders = {
      'HTTP/1.1 ' .. responseCode,
      'Connection: close',
      'Content-Type: text/event-stream',
      '',
      '',
    }
    self.tcpClient:write(table.concat(responseHeaders, '\r\n'))
    self.onClientRequest(self, decoded)
    --self:close()
    vim.defer_fn(function() self:close() end, 10) -- close after 10ms
  else
    log.error(
      string.format(
        'ideMcpClient(c-%d): invalid method %s, only GET and POST supported',
        self.clientId,
        header['method']
      )
    )
    self:close()
    return
  end
  self.requestProcessed = true
end

return IdeMcpServer
