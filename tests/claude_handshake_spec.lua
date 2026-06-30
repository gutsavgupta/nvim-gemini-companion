local handshake = require('gemini.claude.handshake')
local wsUtils = require('gemini.claude.wsUtils')

describe('claude handshake', function()
  local KEY = 'dGhlIHNhbXBsZSBub25jZQ==' -- 24-char base64, RFC 6455 example
  local TOKEN = 'abcdef0123456789abcdef0123456789'

  local function upgrade_request(extra_headers)
    local lines = {
      'GET / HTTP/1.1',
      'Host: 127.0.0.1',
      'Upgrade: websocket',
      'Connection: Upgrade',
      'Sec-WebSocket-Key: ' .. KEY,
      'Sec-WebSocket-Version: 13',
    }
    for _, h in ipairs(extra_headers or {}) do
      table.insert(lines, h)
    end
    return table.concat(lines, '\r\n') .. '\r\n\r\n'
  end

  it('accepts a valid upgrade request without auth', function()
    local ok, headers = handshake.validate_upgrade_request(upgrade_request())
    assert.is_true(ok)
    assert.are.equal('websocket', headers['upgrade']:lower())
  end)

  it('builds a 101 response with the correct accept key', function()
    local success, response = handshake.process_handshake(upgrade_request())
    assert.is_true(success)
    assert.is_truthy(response:match('^HTTP/1%.1 101'))
    local expected = wsUtils.generate_accept_key(KEY)
    -- plain find (true): the base64 accept key contains Lua-magic chars (+ / =).
    assert.is_truthy(response:find('Sec-WebSocket-Accept: ' .. expected, 1, true))
  end)

  it('rejects a request missing the Upgrade header', function()
    local bad = 'GET / HTTP/1.1\r\nHost: x\r\n\r\n'
    local ok, err = handshake.validate_upgrade_request(bad)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('Upgrade'))
  end)

  it('accepts a matching auth token', function()
    local req = upgrade_request({ handshake.AUTH_HEADER .. ': ' .. TOKEN })
    local ok = handshake.validate_upgrade_request(req, TOKEN)
    assert.is_true(ok)
  end)

  it('rejects a missing auth token when one is required', function()
    local ok, err = handshake.validate_upgrade_request(upgrade_request(), TOKEN)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('authentication header'))
  end)

  it('rejects a wrong auth token', function()
    local req = upgrade_request({ handshake.AUTH_HEADER .. ': wrong-token-value' })
    local ok, err = handshake.validate_upgrade_request(req, TOKEN)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('Invalid authentication token'))
  end)

  it('extracts a complete HTTP request from a buffer', function()
    local req = upgrade_request()
    local complete, extracted, remaining =
      handshake.extract_http_request(req .. 'leftover')
    assert.is_true(complete)
    assert.is_truthy(extracted:match('GET / HTTP/1%.1'))
    assert.are.equal('leftover', remaining)
  end)
end)
