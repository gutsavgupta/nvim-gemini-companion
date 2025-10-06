-- tests/nvim/init.lua
--
-- Minimal init file for running tests with manual dependency management.

-- =============================================================================
-- Dependency Management
-- =============================================================================
local deps_path = vim.fn.stdpath('data') .. '/tests'
vim.fn.mkdir(deps_path, 'p')

local function load_dependency(name, url)
  local dep_path = deps_path .. '/' .. name
  if not vim.loop.fs_stat(dep_path) then
    print('Cloning ' .. name .. '...')
    vim.fn.system({
      'git',
      'clone',
      '--depth=1',
      url,
      dep_path,
    })
  end

  vim.opt.runtimepath:prepend(dep_path)
  package.path = package.path .. ';' .. dep_path .. '/lua/?.lua'
  package.path = package.path .. ';' .. dep_path .. '/lua/?/?.lua'
end

local dependencies = {
  {
    name = 'plenary.nvim',
    url = 'https://github.com/nvim-lua/plenary.nvim.git',
  },
}

for _, dep in ipairs(dependencies) do
  load_dependency(dep.name, dep.url)
end

-- =============================================================================
-- Plugin Under Test Setup
-- =============================================================================
local script_path = debug.getinfo(1, 'S').source:sub(2)
local plugin_root = vim.fn.fnamemodify(script_path, ':h:h:h')
vim.opt.runtimepath:prepend(plugin_root)

-- Add plugin's lua directory to package.path
package.path = package.path .. ';' .. plugin_root .. '/lua/?.lua'
package.path = package.path .. ';' .. plugin_root .. '/lua/?/?.lua'

-- =============================================================================
-- TEST-SPECIFIC SETTINGS
-- =============================================================================
vim.opt.swapfile = false
vim.opt.backup = false

-- =============================================================================
-- Gemini Plugin Setup
-- =============================================================================
require('gemini').setup({
  cmd = 'no-cli',
  win = {
    preset = 'floating',
  },
})
print('Test environment initialized successfully.')
