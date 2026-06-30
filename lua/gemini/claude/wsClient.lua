-- WebSocket client connection management for the Claude Code IDE integration.
--
-- Owns the per-client receive buffer and the connecting -> connected state
-- machine: it runs the HTTP upgrade handshake, then decodes RFC 6455 frames and
-- dispatches complete TEXT messages, handles PING/PONG/CLOSE control frames.
--
-- Ported from coder/claudecode.nvim (lua/claudecode/server/client.lua, MIT
-- License). See requirement.md Appendix A.

local frame = require('gemini.claude.frame')
local handshake = require('gemini.claude.handshake')
local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local M = {}

--- Create a new WebSocket client wrapper.
--- @param tcp_handle table The vim.loop TCP handle.
--- @return table client The client object.
function M.create_client(tcp_handle)
  local client_id = tostring(tcp_handle):gsub('userdata: ', 'client_')
  return {
    id = client_id,
    tcp_handle = tcp_handle,
    state = 'connecting',
    buffer = '',
    handshake_complete = false,
    last_ping = 0,
    last_pong = vim.loop.now(),
  }
end

--- Process incoming data for a client.
--- @param client table The client object.
--- @param data string The incoming data.
--- @param on_message function function(client, message_text).
--- @param on_close function function(client, code, reason).
--- @param on_error function function(client, error_msg).
--- @param auth_token string|nil Expected authentication token for validation.
function M.process_data(client, data, on_message, on_close, on_error, auth_token)
  client.buffer = client.buffer .. data

  if not client.handshake_complete then
    local complete, request, remaining =
      handshake.extract_http_request(client.buffer)
    if complete and request then
      local success, response_from_handshake, _ =
        handshake.process_handshake(request, auth_token)

      if not success then
        log.warn(
          'wsClient('
            .. client.id
            .. '): handshake failed: '
            .. tostring(response_from_handshake)
        )
      end

      client.tcp_handle:write(response_from_handshake, function(err)
        if err then
          log.error('wsClient(' .. client.id .. '): handshake write error: ' .. err)
          on_error(client, 'Failed to send handshake response: ' .. err)
          return
        end
        if success then
          client.handshake_complete = true
          client.state = 'connected'
          client.buffer = remaining
          log.debug('wsClient(' .. client.id .. '): connection established')
          if #client.buffer > 0 then
            M.process_data(client, '', on_message, on_close, on_error, auth_token)
          end
        else
          client.state = 'closing'
          vim.schedule(function() client.tcp_handle:close() end)
        end
      end)
    end
    return
  end

  while #client.buffer >= 2 do
    if client.state == 'closing' or client.state == 'closed' then break end

    local parsed_frame, bytes_consumed, close_code =
      frame.parse_frame(client.buffer)

    if not parsed_frame then
      if close_code then
        client.buffer = ''
        M.close_client(client, close_code, 'Protocol error', function()
          on_error(client, 'WebSocket protocol error in frame')
        end)
      end
      break -- incomplete frame: wait for more bytes
    end

    client.buffer = client.buffer:sub(bytes_consumed + 1)

    if
      parsed_frame.opcode == frame.OPCODE.TEXT
      or parsed_frame.opcode == frame.OPCODE.BINARY
    then
      vim.schedule(function() on_message(client, parsed_frame.payload) end)
    elseif parsed_frame.opcode == frame.OPCODE.CLOSE then
      local code = 1000
      local reason = ''
      if #parsed_frame.payload >= 2 then
        local payload = parsed_frame.payload
        code = payload:byte(1) * 256 + payload:byte(2)
        if #payload > 2 then reason = payload:sub(3) end
      end
      if client.state == 'connected' then
        client.tcp_handle:write(frame.create_close_frame(code, reason))
        client.state = 'closing'
      end
      vim.schedule(function() on_close(client, code, reason) end)
      client.buffer = ''
      break
    elseif parsed_frame.opcode == frame.OPCODE.PING then
      client.tcp_handle:write(frame.create_pong_frame(parsed_frame.payload))
    elseif parsed_frame.opcode == frame.OPCODE.PONG then
      client.last_pong = vim.loop.now()
    elseif parsed_frame.opcode == frame.OPCODE.CONTINUATION then
      -- Fragmentation across frames is not supported.
      M.close_client(client, 1003, 'Unsupported data', function()
        on_error(client, 'Fragmented messages not supported')
      end)
      client.buffer = ''
      break
    else
      local opcode = parsed_frame.opcode
      M.close_client(client, 1002, 'Protocol error', function()
        on_error(client, 'Unknown WebSocket opcode: ' .. opcode)
      end)
      client.buffer = ''
      break
    end
  end
end

--- Send a text message to a client.
--- @param client table The client object.
--- @param message string The message to send.
--- @param callback function|nil Optional callback: function(err).
function M.send_message(client, message, callback)
  if client.state ~= 'connected' then
    if callback then callback('Client not connected') end
    return
  end
  client.tcp_handle:write(frame.create_text_frame(message), callback)
end

--- Send a ping to a client.
function M.send_ping(client, data)
  if client.state ~= 'connected' then return end
  client.tcp_handle:write(frame.create_ping_frame(data or ''))
  client.last_ping = vim.loop.now()
end

--- Close a client connection.
--- @param client table The client object.
--- @param code number|nil Close code (default: 1000).
--- @param reason string|nil Close reason.
--- @param on_done function|nil Callback run after the Close frame is written.
function M.close_client(client, code, reason, on_done)
  if client.state == 'closed' or client.state == 'closing' then
    if on_done then vim.schedule(on_done) end
    return
  end

  code = code or 1000
  reason = reason or ''

  if client.tcp_handle:is_closing() then
    client.state = 'closed'
    if on_done then vim.schedule(on_done) end
    return
  end

  if client.handshake_complete then
    client.tcp_handle:write(frame.create_close_frame(code, reason), function()
      client.state = 'closed'
      if not client.tcp_handle:is_closing() then client.tcp_handle:close() end
      if on_done then on_done() end
    end)
    client.state = 'closing'
  else
    client.state = 'closed'
    client.tcp_handle:close()
    if on_done then vim.schedule(on_done) end
  end
end

--- Check if a client connection is alive.
function M.is_client_alive(client, timeout)
  timeout = timeout or 30000
  if client.state ~= 'connected' then return false end
  return (vim.loop.now() - client.last_pong) < timeout
end

return M
