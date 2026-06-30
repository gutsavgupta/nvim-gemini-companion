-- WebSocket utility functions for the Claude Code IDE integration.
--
-- base64, SHA-1, RFC 6455 accept-key generation, masking, byte conversions,
-- HTTP header parsing and a constant-time compare.
--
-- Ported from coder/claudecode.nvim (lua/claudecode/server/utils.lua, MIT
-- License). See requirement.md Appendix A.

local M = {}

-- Lua 5.1 compatible bitwise operations (arithmetic emulation).
local function band(a, b)
  local result = 0
  local bitval = 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + bitval end
    bitval = bitval * 2
    a = math.floor(a / 2)
    b = math.floor(b / 2)
  end
  return result
end

local function bor(a, b)
  local result = 0
  local bitval = 1
  while a > 0 or b > 0 do
    if a % 2 == 1 or b % 2 == 1 then result = result + bitval end
    bitval = bitval * 2
    a = math.floor(a / 2)
    b = math.floor(b / 2)
  end
  return result
end

local function bxor(a, b)
  local result = 0
  local bitval = 1
  while a > 0 or b > 0 do
    if (a % 2) ~= (b % 2) then result = result + bitval end
    bitval = bitval * 2
    a = math.floor(a / 2)
    b = math.floor(b / 2)
  end
  return result
end

local bit_ok, bit = pcall(require, 'bit')
local native_bxor = bit_ok and bit and bit.bxor or nil

local function bnot(a) return bxor(a, 0xFFFFFFFF) end

local function lshift(value, amount)
  local shifted_val = value * (2 ^ amount)
  return shifted_val % (2 ^ 32)
end

local function rshift(value, amount) return math.floor(value / (2 ^ amount)) end

local function rotleft(value, amount)
  local mask = 0xFFFFFFFF
  value = band(value, mask)
  local part1 = lshift(value, amount)
  local part2 = rshift(value, 32 - amount)
  return band(bor(part1, part2), mask)
end

local function add32(a, b)
  local sum = a + b
  return band(sum, 0xFFFFFFFF)
end

local unpack = table.unpack or unpack

--- Base64 encode a string.
--- @param data string The data to encode.
--- @return string encoded The base64 encoded string.
function M.base64_encode(data)
  local chars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local result = {}
  local padding = ''

  local pad_len = 3 - (#data % 3)
  if pad_len ~= 3 then
    data = data .. string.rep('\0', pad_len)
    padding = string.rep('=', pad_len)
  end

  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local bitmap = a * 65536 + b * 256 + c
    result[#result + 1] =
      chars:sub(math.floor(bitmap / 262144) + 1, math.floor(bitmap / 262144) + 1)
    result[#result + 1] = chars:sub(
      math.floor((bitmap % 262144) / 4096) + 1,
      math.floor((bitmap % 262144) / 4096) + 1
    )
    result[#result + 1] = chars:sub(
      math.floor((bitmap % 4096) / 64) + 1,
      math.floor((bitmap % 4096) / 64) + 1
    )
    result[#result + 1] = chars:sub((bitmap % 64) + 1, (bitmap % 64) + 1)
  end

  local encoded = table.concat(result)
  return encoded:sub(1, #encoded - #padding) .. padding
end

--- Pure Lua SHA-1 implementation.
--- @param data string The data to hash.
--- @return string|nil hash The SHA-1 hash in binary format, or nil on error.
function M.sha1(data)
  if type(data) ~= 'string' then return nil end
  if #data > 10 * 1024 * 1024 then return nil end -- 10MB limit (DOS protection)

  local h0 = 0x67452301
  local h1 = 0xEFCDAB89
  local h2 = 0x98BADCFE
  local h3 = 0x10325476
  local h4 = 0xC3D2E1F0

  local msg = data
  local msg_len = #msg
  local bit_len = msg_len * 8

  msg = msg .. string.char(0x80)
  while (#msg % 64) ~= 56 do
    msg = msg .. string.char(0x00)
  end
  for i = 7, 0, -1 do
    msg = msg .. string.char(band(rshift(bit_len, i * 8), 0xFF))
  end

  for chunk_start = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do
      local offset = chunk_start + i * 4
      w[i] = bor(
        bor(
          bor(lshift(msg:byte(offset), 24), lshift(msg:byte(offset + 1), 16)),
          lshift(msg:byte(offset + 2), 8)
        ),
        msg:byte(offset + 3)
      )
    end
    for i = 16, 79 do
      w[i] =
        rotleft(bxor(bxor(bxor(w[i - 3], w[i - 8]), w[i - 14]), w[i - 16]), 1)
    end

    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i <= 19 then
        f = bor(band(b, c), band(bnot(b), d))
        k = 0x5A827999
      elseif i <= 39 then
        f = bxor(bxor(b, c), d)
        k = 0x6ED9EBA1
      elseif i <= 59 then
        f = bor(bor(band(b, c), band(b, d)), band(c, d))
        k = 0x8F1BBCDC
      else
        f = bxor(bxor(b, c), d)
        k = 0xCA62C1D6
      end
      local temp = add32(add32(add32(add32(rotleft(a, 5), f), e), k), w[i])
      e = d
      d = c
      c = rotleft(b, 30)
      b = a
      a = temp
    end

    h0 = add32(h0, a)
    h1 = add32(h1, b)
    h2 = add32(h2, c)
    h3 = add32(h3, d)
    h4 = add32(h4, e)
  end

  local result = ''
  for _, h in ipairs({ h0, h1, h2, h3, h4 }) do
    result = result
      .. string.char(
        band(rshift(h, 24), 0xFF),
        band(rshift(h, 16), 0xFF),
        band(rshift(h, 8), 0xFF),
        band(h, 0xFF)
      )
  end
  return result
end

--- Generate the RFC 6455 accept key from a client key.
--- @param client_key string The client's Sec-WebSocket-Key header value.
--- @return string|nil accept_key The base64 accept key, or nil on error.
function M.generate_accept_key(client_key)
  local magic_string = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
  local combined = client_key .. magic_string
  local hash = M.sha1(combined)
  if not hash then return nil end
  return M.base64_encode(hash)
end

--- Parse HTTP headers from a request string.
--- @param request string The HTTP request string.
--- @return table headers Table of header name (lowercased) -> value pairs.
function M.parse_http_headers(request)
  local headers = {}
  local lines = {}
  for line in request:gmatch('[^\r\n]+') do
    table.insert(lines, line)
  end
  for i = 2, #lines do
    local line = lines[i]
    local name, value = line:match('^([^:]+):%s*(.+)$')
    if name and value then headers[name:lower()] = value end
  end
  return headers
end

--- Check if a string contains valid UTF-8.
--- @param str string The string to check.
--- @return boolean valid True if the string is valid UTF-8.
function M.is_valid_utf8(str)
  local i = 1
  while i <= #str do
    local byte = str:byte(i)
    local char_len = 1
    if byte >= 0x80 then
      if byte >= 0xF0 then
        char_len = 4
      elseif byte >= 0xE0 then
        char_len = 3
      elseif byte >= 0xC0 then
        char_len = 2
      else
        return false
      end
      for j = 1, char_len - 1 do
        if i + j > #str then return false end
        local cont_byte = str:byte(i + j)
        if cont_byte < 0x80 or cont_byte >= 0xC0 then return false end
      end
    end
    i = i + char_len
  end
  return true
end

--- Convert a 16-bit number to big-endian bytes.
function M.uint16_to_bytes(num) return string.char(math.floor(num / 256), num % 256) end

--- Convert a 64-bit number to big-endian bytes.
function M.uint64_to_bytes(num)
  local bytes = {}
  for i = 8, 1, -1 do
    bytes[i] = num % 256
    num = math.floor(num / 256)
  end
  return string.char(unpack(bytes))
end

--- Convert big-endian bytes to a 16-bit number.
function M.bytes_to_uint16(bytes)
  if #bytes < 2 then return 0 end
  return bytes:byte(1) * 256 + bytes:byte(2)
end

--- Convert big-endian bytes to a 64-bit number.
function M.bytes_to_uint64(bytes)
  if #bytes < 8 then return 0 end
  local num = 0
  for i = 1, 8 do
    num = num * 256 + bytes:byte(i)
  end
  return num
end

--- Apply an XOR mask to payload data.
--- @param data string The data to mask/unmask.
--- @param mask string The 4-byte mask.
--- @return string masked The masked/unmasked data.
function M.apply_mask(data, mask)
  local result = {}
  local mask_bytes = { mask:byte(1, 4) }
  for i = 1, #data do
    local mask_idx = ((i - 1) % 4) + 1
    local data_byte = data:byte(i)
    local mask_byte = mask_bytes[mask_idx]
    local masked_byte = native_bxor and native_bxor(data_byte, mask_byte)
      or bxor(data_byte, mask_byte)
    result[i] = string.char(masked_byte)
  end
  return table.concat(result)
end

--- Compare two strings in constant time relative to their length.
--- @param a string First string.
--- @param b string Second string.
--- @return boolean equal True if the strings are byte-for-byte equal.
function M.constant_time_compare(a, b)
  if type(a) ~= 'string' or type(b) ~= 'string' then return false end
  if #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do
    local d = a:byte(i) - b:byte(i)
    diff = diff + d * d
  end
  return diff == 0
end

return M
