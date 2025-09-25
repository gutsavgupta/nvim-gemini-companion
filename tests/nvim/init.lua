-- /home/fedoralab/github/nvim-gemini-companion/tests/init.lua
-- This is a minimal init file for running tests.
-- It sets up the necessary paths for the test environment.
-- =============================================================================
-- IMPORTANT: SET UP PLENARY.NVIM PATH
-- =============================================================================
local plenary_path = vim.fn.expand('$HOME/.local/share/nvim/lazy/plenary.nvim')
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:prepend(plenary_path)
else
  print('WARNING: plenary.nvim not found at ' .. plenary_path)
end

-- =============================================================================
-- PLUGIN SETUP
-- =============================================================================
local script_path = debug.getinfo(1, 'S').source:sub(2)
local plugin_root = vim.fn.fnamemodify(script_path, ':h:h:h')
vim.opt.runtimepath:prepend(plugin_root)
package.path = package.path .. ';' .. plugin_root .. '/lua/?.lua'
package.path = package.path .. ';' .. plugin_root .. '/lua/gemini/?.lua'

-- =============================================================================
-- TEST-SPECIFIC SETTINGS
-- =============================================================================
vim.opt.swapfile = false
vim.opt.backup = false

print('Test environment initialized successfully.')
require('gemini').setup()

