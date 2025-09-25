-- This file was created on September 25, 2025
-- This file is responsible for managing the diff view for the IDE.
-- It allows opening a diff view between a file and new content, and handling
-- user actions like accepting or rejecting the changes.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local manager = {}
local views = {}

---
---
-- Opens a new diff view in a new tab.
-- @param filePath string The absolute path to the original file.
-- @param newContent string The new content to be diffed against the original file.
-- @param onClose function A callback function that is called when the diff view is closed.
--   It receives the final content of the modified buffer and a status string
--   ("accepted", "rejected", or "closed").
function manager.open(filePath, newContent, onClose)
  vim.schedule(function()
    -- 1. Get filename and create the modified buffer name
    local filename = vim.fn.fnamemodify(filePath, ':t')
    local modifiedBufName = filename .. ' <-> modified'

    -- If a buffer with the same name exists from a previous diff, delete it
    local existingBuf = vim.fn.bufnr(modifiedBufName)
    if existingBuf ~= -1 then
      vim.api.nvim_buf_delete(existingBuf, { force = true })
    end

    -- 2. Create a new scratch buffer for the new content
    local newBuf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(
      newBuf,
      0,
      -1,
      false,
      vim.split(newContent, '\n')
    )
    vim.api.nvim_buf_set_name(newBuf, modifiedBufName)
    vim.api.nvim_buf_set_option(newBuf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(newBuf, 'bufhidden', 'hide')

    -- 3. Open a new tab for the diff
    vim.cmd('tabnew')
    local diffTab = vim.api.nvim_get_current_tabpage()

    -- 4. Set options for the diff
    vim.cmd(
      'setlocal diffopt=internal,filler,closeoff,vertical,algorithm:patience'
    )
    vim.cmd('set splitright') -- Ensure vsplit opens to the right

    -- 5. Open original file in the left split
    vim.cmd('edit ' .. filePath)
    local originalWinDiff = vim.api.nvim_get_current_win()
    local originalBuf = vim.api.nvim_win_get_buf(originalWinDiff)
    local filetype = vim.api.nvim_buf_get_option(originalBuf, 'filetype')
    vim.cmd('diffthis')

    -- Set filetype for the new buffer
    vim.api.nvim_buf_set_option(newBuf, 'filetype', filetype)

    -- 6. Open the new content in a vertical split on the right
    vim.cmd('vsplit')
    local newWinDiff = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(newBuf)
    vim.cmd('diffthis')

    -- Make sure both windows scroll together
    vim.api.nvim_set_option_value('scrollbind', true, { win = originalWinDiff })
    vim.api.nvim_set_option_value('scrollbind', true, { win = newWinDiff })

    -- Lock the buffers in the windows
    vim.api.nvim_set_option_value('winfixbuf', true, { win = originalWinDiff })
    vim.api.nvim_set_option_value('winfixbuf', true, { win = newWinDiff })

    -- Store view info for closing later
    views[filePath] = {
      tabId = diffTab,
      winIds = { originalWinDiff, newWinDiff },
      originalBuf = vim.api.nvim_win_get_buf(originalWinDiff),
      newBuf = newBuf,
      onClose = onClose,
    }
  end)
end

local function closeView(filePath, status)
  status = status or 'closed'
  local view = views[filePath]
  if not view then return end

  local content
  if view.newBuf and vim.api.nvim_buf_is_valid(view.newBuf) then
    local lines = vim.api.nvim_buf_get_lines(view.newBuf, 0, -1, false)
    content = table.concat(lines, '\n')
  end

  for _, winId in ipairs(view.winIds) do
    if vim.api.nvim_win_is_valid(winId) then
      vim.api.nvim_win_close(winId, true)
    end
  end

  views[filePath] = nil
  if view.onClose then view.onClose(content, status) end
end

---
---
-- Closes the diff view for a given file path.
-- @param filePath string The file path of the diff to close.
function manager.close(filePath) closeView(filePath, 'closed') end

---
---
-- Accepts the changes in the diff view.
-- This closes the view and triggers the onClose callback with "accepted" status.
-- @param filePath string The file path of the diff to accept.
function manager.accept(filePath) closeView(filePath, 'accepted') end

---
---
-- Rejects the changes in the diff view.
-- This closes the view and triggers the onClose callback with "rejected" status.
-- @param filePath string The file path of the diff to reject.
function manager.reject(filePath) closeView(filePath, 'rejected') end

---
---
function manager.getFilePathFromWindowID(winId)
  for filePath, view in pairs(views) do
    for _, diffWinId in ipairs(view.winIds) do
      if diffWinId == winId then return filePath end
    end
  end
  print('Not a Gemini diff buffer')
  return nil
end

function manager.setup()
  vim.api.nvim_create_user_command('GeminiAccept', function()
    local winId = vim.api.nvim_get_current_win()
    local filePath = manager.getFilePathFromWindowID(winId)
    if filePath then manager.accept(filePath) end
  end, {
    desc = 'Accept changes in Gemini diff view',
  })
  vim.api.nvim_create_user_command('GeminiReject', function()
    local winId = vim.api.nvim_get_current_win()
    local filePath = manager.getFilePathFromWindowID(winId)
    if filePath then manager.reject(filePath) end
  end, {
    desc = 'Reject changes in Gemini diff view',
  })
end

return manager
