local health = vim.health
local M = {}

M.serverStatus = function()
  local has_gemini, gemini = pcall(require, 'gemini')
  if not has_gemini or not gemini or not gemini.getServerStatus then
    health.error('nvim-gemini-companion plugin not loaded')
    return
  end
  local serverStatus = gemini.getServerStatus()
  if not serverStatus.initialized then
    health.error('MCP server not initialized')
    return
  end
  if not serverStatus.port or serverStatus.port == 0 then
    health.error('MCP server not listening on a port')
    return
  end
  health.ok('MCP server is initialized')
  health.ok('MCP server running on port ' .. tostring(serverStatus.port))
  health.ok('Workspace: ' .. serverStatus.workspace)
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
end

return M
