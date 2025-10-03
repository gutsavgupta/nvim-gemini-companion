-- This file was created on September 25, 2025
-- This file is responsible for managing the diff view for the IDE.
-- It allows opening a diff view between a file and new content, and handling
-- user actions like accepting or rejecting the changes.

local manager = {}
local views = {}

---
-- Opens a new diff view in a new tab, showing the differences between the
-- content of a local file and a new string of content. This is useful for
-- previewing changes before applying them.
--
-- The user can accept the changes, which will trigger a callback with the new
-- content, or reject them. The diff view is automatically closed after either
-- action.
--
-- @param filePath string The absolute path to the original file. This file is
--   used as the "original" side of the diff.
-- @param newContent string The new content to be diffed against the original
--   file. This is shown in the "modified" side of the diff.
-- @param onClose function A callback function that is called when the diff view
--   is closed. It receives two arguments:
--   - `finalContent`: A string with the content of the modified buffer when the
--     view was closed. This allows the caller to get the latest version of the
--     content, including any manual edits made by the user in the diff view.
--   - `status`: A string indicating how the view was closed. It can be one of
--     the following:
--       - `"accepted"`: The user accepted the changes.
--       - `"rejected"`: The user rejected the changes.
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
    -- Allow write commands but prevent actual file writes
    vim.api.nvim_buf_set_option(newBuf, 'buftype', 'acwrite')
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
    vim.api.nvim_buf_set_option(originalBuf, 'readonly', true)
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

    -- Store view info for closing later (we need this before setting up autocommands)
    views[filePath] = {
      tabId = diffTab,
      winIds = { originalWinDiff, newWinDiff },
      originalBuf = vim.api.nvim_win_get_buf(originalWinDiff),
      newBuf = newBuf,
      onClose = onClose,
      diffAccepted = false,
    }

    -- Set up autocommands for the new buffer to handle :w and quit events
    local augroup = vim.api.nvim_create_augroup(
      'GeminiDiffManager_' .. newBuf,
      { clear = true }
    )

    local handleWriteCmd = function()
      local view = views[filePath]
      if view then view.diffAccepted = true end
      vim.api.nvim_buf_set_option(view.newBuf, 'modified', false)
    end

    local handleQuit = function()
      local view = views[filePath]
      if not view then return end
      if view.diffAccepted then
        vim.schedule(function() manager.accept(filePath) end)
      else
        vim.schedule(function() manager.reject(filePath) end)
      end
    end

    -- Handle :w command on the newBuf to accept changes
    vim.api.nvim_create_autocmd('BufWriteCmd', {
      group = augroup,
      buffer = newBuf,
      callback = handleWriteCmd,
    })

    -- Handle quit events to accept changes if the buffer was modified
    vim.api.nvim_create_autocmd('BufWinLeave', {
      group = augroup,
      buffer = newBuf,
      callback = handleQuit,
    })

    vim.api.nvim_create_autocmd('BufWinLeave', {
      group = augroup,
      buffer = originalBuf,
      callback = handleQuit,
    })

    -- Update the view with the augroup for proper cleanup later
    local existing_view = views[filePath]
    if existing_view then
      existing_view.augroup = augroup -- Store the augroup to clean it up later
    end
  end)
end

---
-- Closes the diff view for a given file path and returns the final content of
-- the modified buffer. This function is used internally to clean up the view
-- and retrieve the content before calling the `onClose` callback.
--
-- @param filePath string The file path of the diff to close.
-- @return string The final content of the modified buffer.
local function closeView(filePath)
  local view = views[filePath]
  if not view then return end

  -- disable the augroup
  if view.augroup then vim.api.nvim_del_augroup_by_id(view.augroup) end

  local content
  if view.newBuf and vim.api.nvim_buf_is_valid(view.newBuf) then
    local lines = vim.api.nvim_buf_get_lines(view.newBuf, 0, -1, false)
    content = table.concat(lines, '\n')
  end

  -- delete the buffers
  if view.originalBuf and vim.api.nvim_buf_is_valid(view.originalBuf) then
    vim.api.nvim_buf_delete(view.originalBuf, { force = true })
  end
  if view.newBuf and vim.api.nvim_buf_is_valid(view.newBuf) then
    vim.api.nvim_buf_delete(view.newBuf, { force = true })
  end

  -- close the windows
  for _, winId in ipairs(view.winIds) do
    if vim.api.nvim_win_is_valid(winId) then
      vim.api.nvim_win_close(winId, true)
    end
  end

  views[filePath] = nil
  return content
end

---
-- Closes the diff view for a given file path.
--
-- This is a convenience function that wraps `closeView` to expose it as part
-- of the public API. It is not typically used directly, as the view is
-- automatically closed when the user accepts or rejects the changes.
--
-- @param filePath string The file path of the diff to close.
function manager.close(filePath) return closeView(filePath) end

---
-- Accepts the changes in the diff view.
--
-- This closes the view and triggers the `onClose` callback with an "accepted"
-- status. The final content of the modified buffer is passed to the callback,
-- allowing the caller to apply the changes.
--
-- @param filePath string The file path of the diff to accept.
function manager.accept(filePath)
  local view = views[filePath]
  local content = closeView(filePath)
  if content and view and view.onClose then
    view.onClose(content, 'accepted')
  end
end

---
-- Rejects the changes in the diff view.
--
-- This closes the view and triggers the `onClose` callback with a "rejected"
-- status. The final content of the modified buffer is still passed to the
-- callback, but it is up to the caller to decide whether to use it.
--
-- @param filePath string The file path of the diff to reject.
function manager.reject(filePath)
  local view = views[filePath]
  local content = closeView(filePath)
  if content and view and view.onClose then
    view.onClose(content, 'rejected')
  end
end

---
-- Retrieves the file path associated with a given window ID.
--
-- This function is used to find the file path of the original file in a diff
-- view, which is necessary to perform actions like accepting or rejecting the
-- changes.
--
-- @param winId number The window ID to look up.
-- @return string|nil The file path if the window is part of a diff view, or
--   nil otherwise.
function manager.getFilePathFromWindowID(winId)
  for filePath, view in pairs(views) do
    for _, diffWinId in ipairs(view.winIds) do
      if diffWinId == winId then return filePath end
    end
  end
  print('Not a Gemini diff buffer')
  return nil
end

function manager.getView(filePath) return views[filePath] end

---
-- Sets up the user commands for interacting with the diff view.
--
-- This function creates the `:GeminiAccept` and `:GeminiReject` commands, which
-- allow the user to accept or reject the changes in the current diff view.
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
