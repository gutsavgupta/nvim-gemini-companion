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

-- Gets the path for the server details file.
-- This path is unique for each workspace to allow multiple nvim instances to run
-- in different workspaces without conflicts.
-- @return string: The absolute path to the server details file.
function M.getServerDetailsPath()
  local cwd = vim.fn.getcwd()
  local cwdHash = vim.fn.sha256(cwd)
  -- Use only first 12 characters of the hash to keep filename manageable
  local shortHash = string.sub(cwdHash, 1, 12)
  return string.format('/tmp/nvim-gemini-companion-%s.json', shortHash)
end

-- Reads and decodes the server details from a JSON file.
-- @param path string|nil: The absolute path to the file to read. If nil, the default path is used.
-- @return table|nil: The server details as a table, or nil if the file does not exist or is invalid.
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

-- Writes the server details to a JSON file.
-- This file is used to communicate the server's port, workspace, and PID to other processes.
-- @param port number: The port number the server is listening on.
-- @param workspace string: The absolute path of the current workspace.
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

-- Finds server details for the current workspace by searching for server details files in /tmp.
-- This is used to check if another instance of the plugin is already running for the same project.
-- @return table|nil: A table with `details` and `isActive` boolean, or nil if no details are found.
function M.getServerDetailsForSameWorkspace()
  local currentWorkspace = vim.fn.getcwd()
  local files = vim.fn.glob('/tmp/nvim-gemini-companion-*.json', true, true)
  for _, file in ipairs(files) do
    local details = M.readServerDetails(file)
    if details and details.workspace == currentWorkspace then
      log.debug(
        string.format(
          'Found stale server with details: %s',
          vim.fn.json_encode(details)
        )
      )
      return { details = details, isActive = isActiveNvimProcess(details.pid) }
    end
  end
  return nil
end

return M
