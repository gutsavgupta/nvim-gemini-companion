local M = {}

--- Gets the path to the installation info file.
-- @param installDirArg string (optional) The installation directory.
-- @return string The path to the installation info file.
local function getInstallInfoPath(installDirArg)
  local installDir = installDirArg or vim.fn.expand('$HOME/.local/bin')
  return installDir .. '/.nvim-gemini-installed-info.json'
end

--- Installs the tmux wrapper scripts for gemini and qwen.
-- @param installDirArg string (optional) The directory to install the wrappers to.
function M.installMuxWrappers(installDirArg)
  local installDir = installDirArg or vim.fn.expand('$HOME/.local/bin')
  local installInfoPath = getInstallInfoPath(installDir)

  -- Check if installation already exists, and remove it first if needed
  if vim.fn.filereadable(installInfoPath) == 1 then
    print('Previous installation detected. Removing first...')
    M.removeMuxWrappers(installDir)
  end

  local prompt = string.format('Install wrappers to %s?', installDir)
  if vim.fn.confirm(prompt, '&Yes\n&No', 1) ~= 1 then
    print('Installation cancelled.')
    return
  end

  if vim.fn.isdirectory(installDir) == 0 then
    print(
      string.format(
        "Warning: Directory '%s' does not exist. Please create it first.",
        installDir
      )
    )
    return
  end

  if
    not string.find(':' .. os.getenv('PATH') .. ':', ':' .. installDir .. ':')
  then
    print(string.format("Warning: '%s' is not in your PATH.", installDir))
    print("Please add it to your shell's configuration.")
  end

  local pluginPath = debug.getinfo(1, 'S').source:match('@?(.*[\\/])')
  pluginPath = pluginPath .. '../../'
  local connectShPath = pluginPath .. 'scripts/connect.sh'

  if vim.fn.filereadable(connectShPath) == 0 then
    print('Error: Could not find connect.sh in the plugin directory.')
    return
  end

  local connectShDest = installDir .. '/nvim-gemini-connect'
  vim.fn.system(string.format('cp %s %s', connectShPath, connectShDest))
  vim.fn.system(string.format('chmod +x %s', connectShDest))
  print(string.format('Installed nvim-gemini-connect to %s', connectShDest))

  local installedFiles = { connectShDest }

  local originalGemini = vim.fn.executable('gemini') == 1
      and vim.fn.exepath('gemini')
    or nil
  if originalGemini then
    local wrapperPath = installDir .. '/gemini'
    local wrapperContent = string.format(
      [[ 
#!/bin/bash
exec "%s/nvim-gemini-connect" gemini --path "%s" "$@" 
    ]],
      installDir,
      originalGemini
    )
    vim.fn.writefile(vim.split(wrapperContent, '\n'), wrapperPath)
    vim.fn.system(string.format('chmod +x %s', wrapperPath))
    print(string.format('Created wrapper for gemini at %s', wrapperPath))
    table.insert(installedFiles, wrapperPath)
  end

  local originalQwen = vim.fn.executable('qwen') == 1 and vim.fn.exepath('qwen')
    or nil
  if originalQwen then
    local wrapperPath = installDir .. '/qwen'
    local wrapperContent = string.format(
      [[ 
#!/bin/bash
exec "%s/nvim-gemini-connect" qwen --path "%s" "$@" 
    ]],
      installDir,
      originalQwen
    )
    vim.fn.writefile(vim.split(wrapperContent, '\n'), wrapperPath)
    vim.fn.system(string.format('chmod +x %s', wrapperPath))
    print(string.format('Created wrapper for qwen at %s', wrapperPath))
    table.insert(installedFiles, wrapperPath)
  end

  -- Create installation info file to track what was installed
  local installInfo = {
    installedFiles = installedFiles,
    timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'), -- UTC timestamp
  }

  vim.fn.writefile({ vim.fn.json_encode(installInfo) }, installInfoPath)
  print(string.format('Installation info saved to %s', installInfoPath))

  print('Installation complete.')
end

--- Removes the tmux wrapper scripts for gemini and qwen.
-- @param installDirArg string (optional) The directory to remove the wrappers from.
function M.removeMuxWrappers(installDirArg)
  local installDir = installDirArg or vim.fn.expand('$HOME/.local/bin')
  local installInfoPath = getInstallInfoPath(installDir)

  local filesToRemove = {}

  -- Try to read installation info file first
  if vim.fn.filereadable(installInfoPath) == 1 then
    local installInfoLines = vim.fn.readfile(installInfoPath)
    local installInfoStr = table.concat(installInfoLines, '\n')
    local installInfo = vim.fn.json_decode(installInfoStr)

    if installInfo and installInfo.installedFiles then
      filesToRemove = installInfo.installedFiles
    else
      -- Fallback to default file list if info file is corrupted/invalid
      filesToRemove = {
        installDir .. '/nvim-gemini-connect',
        installDir .. '/gemini',
        installDir .. '/qwen',
      }
    end
  else
    -- Fallback to default file list if no info file exists
    filesToRemove = {
      installDir .. '/nvim-gemini-connect',
      installDir .. '/gemini',
      installDir .. '/qwen',
    }
  end

  local prompt = string.format('Remove wrappers from %s?', installDir)
  if vim.fn.confirm(prompt, '&Yes\n&No', 2) ~= 1 then
    print('Removal cancelled.')
    return
  end

  for _, file in ipairs(filesToRemove) do
    if vim.fn.filereadable(file) == 1 then
      vim.fn.delete(file)
      print(string.format('Removed %s', file))
    else
      print(string.format('File not found, skipping: %s', file))
    end
  end

  -- Remove the installation info file as well
  if vim.fn.filereadable(installInfoPath) == 1 then
    vim.fn.delete(installInfoPath)
    print(string.format('Removed installation info file: %s', installInfoPath))
  end

  print('Removal complete.')
end

--- Sets up the user commands for the installer.
function M.setup()
  vim.api.nvim_create_user_command(
    'GeminiMuxInstallWrappers',
    function(fOpts) M.installMuxWrappers(fOpts.fargs[1]) end,
    {
      nargs = '?',
      desc = 'Install tmux wrapper scripts for gemini/qwen.',
    }
  )

  vim.api.nvim_create_user_command(
    'GeminiMuxRemoveWrappers',
    function(fOpts) M.removeMuxWrappers(fOpts.fargs[1]) end,
    {
      nargs = '?',
      desc = 'Remove tmux wrapper scripts for gemini/qwen.',
    }
  )
end

return M
