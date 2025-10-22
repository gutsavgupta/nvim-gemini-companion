--------------------------------------------------------
--- Log utils
--------------------------------------------------------
local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

--------------------------------------------------------
--- Utility functions
--------------------------------------------------------
-- Check if a process with given PID is an active nvim process
-- @param pid number: Process ID to check
-- @return boolean: True if the process is an active nvim process, false otherwise
local function isActiveNvimProcess(pid)
  -- Check if the process is alive
  local statHandle = io.open('/proc/' .. pid .. '/status', 'r')
  if not statHandle then return false end
  statHandle:close()

  local nameHandle = io.open('/proc/' .. pid .. '/cmdline', 'r')
  if not nameHandle then return false end
  local cmdline = nameHandle:read('*all')
  nameHandle:close()
  return string.find(cmdline, 'nvim') ~= nil
end

--------------------------------------------------------
--- Public Methods
--------------------------------------------------------
local M = {}

-- Get the server details file path for the current neovim instance
-- @return string: Path to the server details file in /tmp directory
function M.getServerDetailsPath()
  local pid = vim.fn.getpid()
  return string.format('/tmp/nvim-gemini-companion-%d.json', pid)
end

-- Read server details from file
-- @param path string|nil: Optional path to read from. If nil, uses default path
-- @return table|nil: Server details table if successful, nil if failed
function M.readServerDetails(path)
  path = path or M.getServerDetailsPath()
  local file = io.open(path, 'r')
  if not file then return nil end

  local content = file:read('*a')
  file:close()

  local success, data = pcall(vim.fn.json_decode, content)
  if not success then
    log.warn('Failed to decode server details file:', path)
    return nil
  end

  return data
end

-- Write server details to file
-- @param port number: Port number for the server
-- @param workspace string: Current working directory/workspace path
function M.writeServerDetails(port, workspace)
  local path = M.getServerDetailsPath()
  local data = {
    port = port,
    workspace = workspace,
    pid = vim.fn.getpid(),
    timestamp = os.time(),
  }

  local file = io.open(path, 'w')
  if not file then
    log.warn('Failed to create server details file:', path)
    return
  end

  file:write(vim.fn.json_encode(data))
  file:close()
end

-- Get stale server details from previous nvim sessions in the same workspace
-- Removes the stale file and returns its details to potentially reuse the port
-- @return table|nil: Stale server details table if found, nil otherwise
function M.getStaleServerDetail()
  local currentPid = vim.fn.getpid()
  local currentWorkspace = vim.fn.getcwd()
  local files = vim.fn.glob('/tmp/nvim-gemini-companion-*.json', true, true)
  for _, file in ipairs(files) do
    local pidStr =
      string.match(file, '/tmp/nvim%-gemini%-companion%-(%d+)%.json')
    local pid = pidStr and tonumber(pidStr) or nil
    if pid and pid ~= currentPid and not isActiveNvimProcess(pid) then
      local details = M.readServerDetails(file)
      if details and details.workspace == currentWorkspace then
        log.debug(
          string.format(
            'Found stale server with details: %s',
            vim.fn.json_encode(details)
          )
        )
        os.remove(file)
        return details
      end
    end
  end
end

return M
