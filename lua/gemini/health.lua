local M = {}

local installer = nil -- Reference to installer module

--- Sets the installer module reference for health checks.
-- @param installerModule table The installer module.
function M.setInstaller(installerModule) installer = installerModule end

--- Checks if the IDE server is running.
local function checkIdeServer()
  vim.health.start('IDE server status')

  -- Get the current Vim process PID
  local vimPid = vim.fn.getpid()

  -- Check for the specific connection file for this Vim instance
  local connFile = string.format('/tmp/nvim-gemini-companion-%d.json', vimPid)
  local connFileExists = vim.fn.filereadable(connFile) == 1

  if connFileExists then
    vim.health.ok(
      string.format('IDE server running (connection file: %s)', connFile)
    )
  else
    vim.health.error(
      string.format(
        'IDE server not running (no connection file found: %s)',
        connFile
      )
    )
  end
end

--- Checks if gemini/qwen binaries are installed and detectable in the system.
local function checkBinaries()
  vim.health.start('Binaries detection')

  local geminiStatus = vim.fn.executable('gemini') == 1
  local qwenStatus = vim.fn.executable('qwen') == 1

  if geminiStatus then
    vim.health.ok(
      string.format('gemini binary found: %s', vim.fn.exepath('gemini'))
    )
  else
    vim.health.info('gemini binary not found')
  end

  if qwenStatus then
    vim.health.ok(
      string.format('qwen binary found: %s', vim.fn.exepath('qwen'))
    )
  else
    vim.health.info('qwen binary not found')
  end

  if geminiStatus and qwenStatus then
    vim.health.ok('Both gemini and qwen binaries detected')
  elseif geminiStatus or qwenStatus then
    vim.health.warn('Only one of gemini/qwen binaries detected')
  else
    vim.health.warn('Neither gemini nor qwen binary detected')
  end
end

--- Checks if mux wrappers are installed.
local function checkMuxInstaller()
  vim.health.start('Mux wrappers installation')

  if not installer then
    vim.health.error('Installer module not available')
    return
  end

  local installDir = vim.fn.expand('$HOME/.local/bin')
  local installInfoPath = installDir .. '/.nvim-gemini-installed-info.json'

  if vim.fn.filereadable(installInfoPath) == 1 then
    -- Read the installed files from the info file
    local installInfoLines = vim.fn.readfile(installInfoPath)
    local installInfoStr = table.concat(installInfoLines, '\n')
    local installInfo = vim.fn.json_decode(installInfoStr)

    if installInfo and installInfo.installedFiles then
      vim.health.info(
        string.format(
          'Installation info timestamp: %s',
          installInfo.timestamp or 'unknown'
        )
      )

      -- Check if all files in the info file actually exist
      local missingFiles = {}
      for _, file in ipairs(installInfo.installedFiles) do
        if vim.fn.filereadable(file) ~= 1 then
          table.insert(missingFiles, file)
        end
      end

      if #missingFiles == 0 then
        vim.health.ok(
          string.format(
            'Mux wrappers properly installed (%d files)',
            #installInfo.installedFiles
          )
        )
        for _, file in ipairs(installInfo.installedFiles) do
          vim.health.info(string.format('  - %s', file))
        end
      else
        vim.health.error(
          string.format(
            'Mux wrappers installation info exists but some files are missing: %s',
            table.concat(missingFiles, ', ')
          )
        )
        for _, file in ipairs(missingFiles) do
          vim.health.info(string.format('  - MISSING: %s', file))
        end
      end
    else
      vim.health.error('Mux installer info file exists but is corrupted')
    end
  else
    -- Check for default files (fallback for older installations)
    local filesToCheck = {
      installDir .. '/nvim-gemini-connect',
      installDir .. '/gemini',
      installDir .. '/qwen',
    }

    local foundFiles = {}
    local missingFiles = {}

    for _, file in ipairs(filesToCheck) do
      if vim.fn.filereadable(file) == 1 then
        table.insert(foundFiles, file)
      else
        table.insert(missingFiles, file)
      end
    end

    if #foundFiles == 0 then
      vim.health.info('Mux wrappers are not installed')
    elseif #missingFiles > 0 then
      vim.health.warn(
        string.format(
          'Some mux wrapper files are installed (%d) but some are missing (%d)',
          #foundFiles,
          #missingFiles
        )
      )
      for _, file in ipairs(foundFiles) do
        vim.health.info(string.format('  - INSTALLED: %s', file))
      end
      for _, file in ipairs(missingFiles) do
        vim.health.info(string.format('  - MISSING: %s', file))
      end
    else
      vim.health.ok(
        string.format('Mux wrappers installed (%d files)', #foundFiles)
      )
      for _, file in ipairs(foundFiles) do
        vim.health.info(string.format('  - %s', file))
      end
    end
  end
end

--- Main health check function that runs all checks.
function M.check()
  checkIdeServer()
  checkBinaries()
  checkMuxInstaller()
end

return M

