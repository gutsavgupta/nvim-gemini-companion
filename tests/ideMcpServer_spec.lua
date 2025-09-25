-- This file was created on September 24, 2025
-- This file contains tests for the ideMcpServer.lua module.

local IdeMcpServer = require('ideMcpServer')
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
end)
