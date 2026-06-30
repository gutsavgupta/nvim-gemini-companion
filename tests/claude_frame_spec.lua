local frame = require('gemini.claude.frame')
local wsUtils = require('gemini.claude.wsUtils')

describe('claude frame (RFC 6455)', function()
  -- Helper: client->server frames must be masked. Build a masked frame from a
  -- server (unmasked) frame by flipping the mask bit and applying a mask.
  local function mask_frame(opcode, payload)
    local mask = string.char(0x12, 0x34, 0x56, 0x78)
    local masked_payload = wsUtils.apply_mask(payload, mask)
    local header
    if #payload < 126 then
      header = string.char(0x80 + opcode) .. string.char(0x80 + #payload)
    elseif #payload < 65536 then
      header = string.char(0x80 + opcode)
        .. string.char(0x80 + 126)
        .. wsUtils.uint16_to_bytes(#payload)
    else
      header = string.char(0x80 + opcode)
        .. string.char(0x80 + 127)
        .. wsUtils.uint64_to_bytes(#payload)
    end
    return header .. mask .. masked_payload
  end

  it('round-trips a server text frame through the parser', function()
    local text = 'hello world'
    -- create_text_frame is unmasked; re-mask it so the (server-side) parser,
    -- which expects masked client frames, can decode it.
    local data = mask_frame(frame.OPCODE.TEXT, text)
    local parsed, consumed = frame.parse_frame(data)
    assert.is_not_nil(parsed)
    assert.are.equal(frame.OPCODE.TEXT, parsed.opcode)
    assert.are.equal(text, parsed.payload)
    assert.are.equal(#data, consumed)
    assert.is_true(parsed.fin)
  end)

  it('returns nil,0 for an incomplete frame (need more bytes)', function()
    local parsed, consumed, close_code = frame.parse_frame('\x81')
    assert.is_nil(parsed)
    assert.are.equal(0, consumed)
    assert.is_nil(close_code)
  end)

  it('flags a reserved-bit violation with close code 1002', function()
    -- byte1 = 0xC1 sets RSV1 + FIN + TEXT opcode.
    local data = string.char(0xC1) .. string.char(0x80) .. '\0\0\0\0'
    local parsed, _, close_code = frame.parse_frame(data)
    assert.is_nil(parsed)
    assert.are.equal(1002, close_code)
  end)

  it('decodes an extended 16-bit length payload', function()
    local payload = string.rep('a', 200)
    local data = mask_frame(frame.OPCODE.TEXT, payload)
    local parsed = frame.parse_frame(data)
    assert.is_not_nil(parsed)
    assert.are.equal(200, parsed.payload_length)
    assert.are.equal(payload, parsed.payload)
  end)

  it('parses ping/pong/close control frames', function()
    local ping = mask_frame(frame.OPCODE.PING, 'pingdata')
    assert.are.equal(frame.OPCODE.PING, (frame.parse_frame(ping)).opcode)

    local pong = mask_frame(frame.OPCODE.PONG, '')
    assert.are.equal(frame.OPCODE.PONG, (frame.parse_frame(pong)).opcode)
  end)

  it('creates a well-formed unmasked server text frame', function()
    local data = frame.create_text_frame('hi')
    -- FIN + TEXT
    assert.are.equal(0x81, data:byte(1))
    -- no mask bit, length 2
    assert.are.equal(2, data:byte(2))
    assert.are.equal('hi', data:sub(3))
  end)

  it('creates a close frame with a status code', function()
    local data = frame.create_close_frame(1000, '')
    assert.are.equal(0x88, data:byte(1)) -- FIN + CLOSE
    local code = data:byte(3) * 256 + data:byte(4)
    assert.are.equal(1000, code)
  end)
end)
