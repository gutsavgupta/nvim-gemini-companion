-- Lock file management for the Claude Code IDE integration.
--
-- Claude Code discovers IDEs by scanning a lock-file directory
-- (~/.claude/ide/ or $CLAUDE_CONFIG_DIR/ide). Each lock file is named
-- "<port>.lock" and carries the workspace folders, the transport ("ws") and the
-- auth token the CLI must present on the WebSocket upgrade.
--
-- Adapted from coder/claudecode.nvim (lua/claudecode/lockfile.lua, MIT License).
-- See requirement.md Appendix A.

local M = {}

--- Resolve the lock-file directory ($CLAUDE_CONFIG_DIR/ide or ~/.claude/ide).
--- @return string lock_dir
function M.get_lock_dir()
  local claude_config_dir = os.getenv('CLAUDE_CONFIG_DIR')
  if claude_config_dir and claude_config_dir ~= '' then
    return vim.fn.expand(claude_config_dir .. '/ide')
  end
  return vim.fn.expand('~/.claude/ide')
end

--- Read n random bytes from a cryptographically secure source.
--- @param n number Number of random bytes.
--- @return string bytes
local function get_random_bytes(n)
  if vim.loop and vim.loop.random then
    local ok, bytes = pcall(vim.loop.random, n)
    if ok and type(bytes) == 'string' and #bytes == n then return bytes end
  end
  local file = io.open('/dev/urandom', 'rb')
  if file then
    local bytes = file:read(n)
    file:close()
    if type(bytes) == 'string' and #bytes == n then return bytes end
  end
  error('Failed to obtain ' .. n .. ' bytes of secure random data')
end

--- Generate a cryptographically secure auth token (32 lowercase hex chars).
--- @return string token
function M.generate_auth_token()
  local bytes = get_random_bytes(16)
  local token = bytes:gsub('.', function(c) return string.format('%02x', string.byte(c)) end)
  if not token:match('^[0-9a-f]+$') then error('Generated invalid auth token format') end
  return token
end

--- Get workspace folders for the lock file (cwd + LSP workspace folders).
--- @return table folders Array of absolute paths.
function M.get_workspace_folders()
  local folders = { vim.fn.getcwd() }

  local clients = {}
  if vim.lsp then
    if vim.lsp.get_clients then
      clients = vim.lsp.get_clients()
    elseif vim.lsp.get_active_clients then
      clients = vim.lsp.get_active_clients()
    end
  end

  for _, client in pairs(clients) do
    if client.config and client.config.workspace_folders then
      for _, ws in ipairs(client.config.workspace_folders) do
        local path = ws.uri
        if path:sub(1, 7) == 'file://' then path = path:sub(8) end
        local exists = false
        for _, folder in ipairs(folders) do
          if folder == path then
            exists = true
            break
          end
        end
        if not exists then table.insert(folders, path) end
      end
    end
  end
  return folders
end

--- Path of the lock file for the given port.
--- @param port number
--- @return string
function M.lock_path(port) return M.get_lock_dir() .. '/' .. port .. '.lock' end

--- Create (or overwrite) the lock file for a WebSocket port.
--- @param port number The WebSocket server port.
--- @param auth_token string The auth token to embed.
--- @return boolean success
--- @return string result_or_error Lock file path on success, error message on failure.
function M.create(port, auth_token)
  if not port or type(port) ~= 'number' then return false, 'Invalid port number' end
  if type(auth_token) ~= 'string' or #auth_token < 10 then
    return false, 'Invalid auth token'
  end

  local lock_dir = M.get_lock_dir()
  local ok = pcall(function()
    return vim.fn.mkdir(lock_dir, 'p', tonumber('700', 8))
  end)
  if not ok then return false, 'Failed to create lock directory' end
  pcall(vim.loop.fs_chmod, lock_dir, tonumber('700', 8))

  local lock_path = M.lock_path(port)
  local lock_content = {
    pid = vim.fn.getpid(),
    workspaceFolders = M.get_workspace_folders(),
    ideName = 'Neovim',
    transport = 'ws',
    authToken = auth_token,
  }

  local ok_json, json = pcall(vim.json.encode, lock_content)
  if not ok_json or not json then
    return false, 'Failed to encode lock file content'
  end

  -- Atomic write: temp file with restrictive perms, then rename into place.
  local tmp_path = lock_path
    .. '.tmp.'
    .. vim.fn.getpid()
    .. '.'
    .. string.format('%d', vim.loop.hrtime())

  local write_ok, write_err = pcall(function()
    local fd = vim.loop.fs_open(tmp_path, 'wx', tonumber('600', 8))
    if not fd then error('could not open temp file: ' .. tmp_path) end
    local pos = 0
    while pos < #json do
      local okw, written = pcall(vim.loop.fs_write, fd, json:sub(pos + 1), pos)
      if not okw or type(written) ~= 'number' or written <= 0 then
        pcall(vim.loop.fs_close, fd)
        error('could not write temp file')
      end
      pos = pos + written
    end
    local okc, res = pcall(vim.loop.fs_close, fd)
    if not okc or not res then error('could not close temp file') end
  end)
  if not write_ok then
    pcall(vim.loop.fs_unlink, tmp_path)
    return false, 'Failed to write lock file: ' .. tostring(write_err)
  end

  local rename_ok, rename_err = os.rename(tmp_path, lock_path)
  if not rename_ok then
    pcall(vim.loop.fs_unlink, tmp_path)
    return false, 'Failed to rename lock file: ' .. tostring(rename_err)
  end

  return true, lock_path
end

--- Remove the lock file for the given port.
--- @param port number
--- @return boolean success
function M.remove(port)
  if not port or type(port) ~= 'number' then return false end
  local lock_path = M.lock_path(port)
  if vim.fn.filereadable(lock_path) == 0 then return false end
  local ok = pcall(os.remove, lock_path)
  return ok
end

--- Read and decode a lock file.
--- @param port number
--- @return table|nil data
function M.read(port)
  local lock_path = M.lock_path(port)
  local file = io.open(lock_path, 'r')
  if not file then return nil end
  local content = file:read('*a')
  file:close()
  if not content or content == '' then return nil end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= 'table' then return nil end
  return data
end

return M
