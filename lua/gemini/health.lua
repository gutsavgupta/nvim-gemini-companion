local health = vim.health
local M = {}

M.serverStatus = function()
  local has_gemini, gemini = pcall(require, 'gemini')
  if not has_gemini or not gemini or not gemini.getServerStatus then
    health.error('nvim-gemini-companion plugin not in runtime')
    return
  end
  local serverStatus = gemini.getServerStatus()
  if not serverStatus.initialized then
    health.error('nvim-gemini-companion not initialized')
    return
  end
  if not serverStatus.port or serverStatus.port == 0 then
    health.warn('IDE server not started or listening on any port')
    return
  end
  health.ok('IDE server is initialized')
  health.ok('IDE server running on port ' .. tostring(serverStatus.port))
  health.ok('Workspace: ' .. serverStatus.workspace)
end

-- Checks for the server details file and reports its status.
-- This helps diagnose issues with multiple Neovim instances or stale server files.
M.checkServerDetails = function()
  local hasPersistence, persistence = pcall(require, 'gemini.persistence')
  if not hasPersistence then
    health.warn('persistence module not available')
    return
  end

  local serverDetailsPath = persistence.getServerDetailsPath()
  local details = persistence.readServerDetails()

  if not details then
    health.warn('Server details file not found at: ' .. serverDetailsPath)
    return
  end

  local currentPid = vim.fn.getpid()
  if details.pid == currentPid then
    health.ok(
      'Server details file found: '
        .. serverDetailsPath
        .. ' (current nvim session)'
    )
  else
    health.warn(
      'Server details file found: '
        .. serverDetailsPath
        .. ' (another nvim session, PID: '
        .. details.pid
        .. ')'
    )
  end
end

M.check = function()
  health.start('nvim-gemini-companion health check')

  -- Check if gemini CLI is available
  if vim.fn.executable('gemini') == 1 then
    health.ok('Gemini CLI is installed')
  else
    health.warn('Gemini CLI is not installed or not in PATH')
  end

  -- Check if qwen CLI is available
  if vim.fn.executable('qwen') == 1 then
    health.ok('Qwen CLI is installed')
  else
    health.warn('Qwen CLI is not installed or not in PATH')
  end

  -- Check if plenary.nvim is available
  local hasPlenary, _ = pcall(require, 'plenary')
  if hasPlenary then
    health.ok('plenary.nvim is installed')
  else
    health.warn('plenary.nvim is not installed (required dependency)')
  end

  -- Check if mcp-server is initialized
  M.serverStatus()

  -- Check for server details file from persistence module
  M.checkServerDetails()
end

return M
