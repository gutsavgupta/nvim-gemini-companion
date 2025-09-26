-- /home/fedoralab/github/nvim-gemini-companion/tests/init.lua
-- This is a minimal init file for running tests.
-- It sets up the necessary paths for the test environment.
-- =============================================================================
-- IMPORTANT: SET UP PLENARY.NVIM PATH
-- =============================================================================
local plugin_paths = {
  vim.fn.expand('$HOME/.local/share/nvim/lazy/plenary.nvim'),
  vim.fn.expand('$HOME/.local/share/nvim/lazy/snacks.nvim'),
}

for _, path in ipairs(plugin_paths) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:prepend(path)
  else
    print('WARNING: not a valid path: ' .. path)
  end
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
require('snacks').setup()
require('gemini').setup({
  win = {
    position = 'float',
    border = 'rounded',
  },
})
