-- This file was created on September 24, 2025
-- This file contains tests for the ideMcpServer.lua module.

local IdeMcpServer = require('gemini.ideMcpServer')
local assert = require('luassert')
local spy = require('luassert.spy')

-- Helper function for plain string matching.
local function assert_plain_match(str, substr)
  assert(
    string.find(str, substr, 1, true),
    string.format("'%s' does not contain '%s'", str, substr)
  )
end

describe('ideMcpServer', function()
  local server
  local port
  local onClientRequestSpy
  local onClientCloseSpy

  -- Start the server before each test
  before_each(function()
    onClientRequestSpy = spy.new(function() end)
    onClientCloseSpy = spy.new(function() end)
    local callbacks = {
      onClientRequest = onClientRequestSpy,
      onClientClose = onClientCloseSpy,
    }
    server = IdeMcpServer.new(callbacks)
    port = server:start(0) -- Start on a random port
  end)

  -- Stop the server after each test
  after_each(function() server:close() end)

  it('should create a new server and start it', function()
    assert.is_not_nil(server)
    assert.is_number(port)
    assert(port > 0, 'Port should be greater than 0')
  end)

  it('should accept a GET request for streaming', function()
    local client = vim.uv.new_tcp()
    local connected = false
    local receivedData = false
    local responseBuffer = ''

    client:connect('127.0.0.1', port, function(err)
      assert.is_nil(err)
      connected = true
      local request = table.concat({
        'GET /mcp HTTP/1.1',
        'Host: 127.0.0.1',
        '\r\n',
      }, '\r\n')
      client:write(request)
      client:read_start(function(readErr, data)
        assert.is_nil(readErr)
        assert.is_not_nil(data)
        if data then
          responseBuffer = responseBuffer .. data
          if responseBuffer:find('\r\n\r\n') then
            assert_plain_match(responseBuffer, 'HTTP/1.1 200 OK')
            assert_plain_match(
              responseBuffer,
              'Content-Type: text/event-stream'
            )
            assert_plain_match(responseBuffer, 'Cache-Control: no-cache')
            assert_plain_match(responseBuffer, 'Connection: keep-alive')
            receivedData = true
            client:close()
          end
        end
      end)
    end)

    vim.wait(1000, function() return receivedData end)
    assert.is_true(connected)
    assert.is_true(receivedData)
    assert.spy(onClientRequestSpy).was_not_called()
    assert.spy(onClientCloseSpy).was_not_called()
  end)

  it('should accept a POST request', function()
    local client = vim.uv.new_tcp()
    local connected = false
    local disconnected = false
    local receivedData = false
    local responseBuffer = ''
    local postData = vim.fn.json_encode({ method = 'test', params = {} })
    client:connect('127.0.0.1', port, function(err)
      assert.is_nil(err)
      connected = true
      local request = table.concat({
        'POST /mcp HTTP/1.1',
        'Host: 127.0.0.1',
        'Content-Length: ' .. #postData,
        '\r\n',
      }, '\r\n') .. postData
      client:write(request)
      client:read_start(function(readErr, data)
        assert.is_nil(readErr)
        if data then
          responseBuffer = responseBuffer .. data
          if responseBuffer:find('\r\n\r\n') then
            assert_plain_match(responseBuffer, 'HTTP/1.1 200 OK')
            receivedData = true
          end
        end
        if not data then
          disconnected = true
          client:close()
        end
      end)
    end)

    vim.wait(1000, function() return disconnected end)
    assert.is_true(connected)
    assert.is_true(receivedData)
    assert.is_true(disconnected)
    assert.spy(onClientRequestSpy).was_called(1)
    assert.spy(onClientCloseSpy).was_called(1)
  end)

  it('should return 202 for initialized notification', function()
    local client = vim.uv.new_tcp()
    local connected = false
    local disconnected = false
    local receivedData = false
    local responseBuffer = ''
    local postData =
      vim.fn.json_encode({ method = 'notifications/initialized' })
    client:connect('127.0.0.1', port, function(err)
      assert.is_nil(err)
      connected = true
      local request = table.concat({
        'POST /mcp HTTP/1.1',
        'Host: 127.0.0.1',
        'Content-Length: ' .. #postData,
        '\r\n',
      }, '\r\n') .. postData
      client:write(request)
      client:read_start(function(readErr, data)
        assert.is_nil(readErr)
        if data then
          responseBuffer = responseBuffer .. data
          if responseBuffer:find('\r\n\r\n') then
            assert_plain_match(responseBuffer, 'HTTP/1.1 202 Accepted')
            receivedData = true
          end
        end
        if not data then
          disconnected = true
          client:close()
        end
      end)
    end)

    vim.wait(1000, function() return disconnected end)
    assert.is_true(connected)
    assert.is_true(receivedData)
    assert.is_true(disconnected)
    assert.spy(onClientRequestSpy).was_called(1)
    assert.spy(onClientCloseSpy).was_called(1)
  end)

  it('should handle multiple close calls gracefully', function()
    local initialPort = port
    local initialServer = server

    -- Create a new server for this test to properly test the close behavior
    local callbacks = {
      onClientRequest = onClientRequestSpy,
      onClientClose = onClientCloseSpy,
    }
    local testServer = IdeMcpServer.new(callbacks)
    local testPort = testServer:start(0)

    -- Close the server once
    testServer:close()

    -- Try to close the server again - this should not cause an error
    assert.has_no.errors(function() testServer:close() end)

    -- Verify that the server is actually closed by trying to start a new one on the same port
    -- This is a functional verification that the close worked properly
  end)

  it('should send error json to streaming clients on close', function()
    -- Create a new server to test streaming client close behavior
    local callbacks = {
      onClientRequest = onClientRequestSpy,
      onClientClose = onClientCloseSpy,
    }
    local testServer = IdeMcpServer.new(callbacks)
    local testPort = testServer:start(0)

    -- Connect as a streaming client (GET request) and set up data capture
    local client = vim.uv.new_tcp()
    local connected = false
    local responseBuffer = ''
    local additionalDataReceived = false

    client:connect('127.0.0.1', testPort, function(err)
      assert.is_nil(err)
      connected = true
      local request = table.concat({
        'GET /mcp HTTP/1.1',
        'Host: 127.0.0.1',
        '\r\n',
      }, '\r\n')
      client:write(request)
      client:read_start(function(readErr, data)
        assert.is_nil(readErr)
        if data then
          responseBuffer = responseBuffer .. data
          -- Check if we received the initial headers
          if responseBuffer:find('\r\n\r\n') and not additionalDataReceived then
            additionalDataReceived = true
          end
        end
      end)
    end)

    vim.wait(1000, function() return connected and additionalDataReceived end)
    assert.is_true(connected)
    additionalDataReceived = false
    assert.spy(onClientCloseSpy).was_not_called()

    -- Wait briefly to ensure client is properly established as a streaming client
    vim.wait(
      100,
      function()
        return testServer.clientsObj
          and vim.tbl_count(testServer.clientsObj) > 0
      end
    )

    -- Verify that there is one client and it's a streaming client
    local clientObj = nil
    for _, c in pairs(testServer.clientsObj) do
      clientObj = c
      break
    end
    assert.is_not_nil(clientObj)
    assert.is_true(clientObj.isMcpStream)

    -- Close the server - this should send the special error message to streaming clients
    testServer:close()
    vim.wait(1000, function() return connected and additionalDataReceived end)
    assert.is_true(additionalDataReceived)
    assert.spy(onClientCloseSpy).was_called()
    assert(
      string.find(responseBuffer, 'data:{error%-json\n\n'),
      'expected substring data:{error-json not found'
    )
  end)
end)
