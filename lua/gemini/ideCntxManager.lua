-- This file was created on September 25, 2025
-- This module is responsible for tracking the workspace state, including open files,
-- cursor position, and selected text. It provides the state for the
-- ide/contextUpdate notification.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'info',
})

local MAX_FILES = 10
local manager = {}
local state = {
  openFiles = {},
  isTrusted = true, -- Neovim doesn't have a direct equivalent of VS Code's workspace trust
}

---
-- Ensures that an empty table is encoded as an empty JSON array.
-- @param t table The table to check.
-- @return table The original table or a new table with metatable for JSON encoding.
local function createJsonArray(t)
  if t and #t > 0 then return t end
  -- For some JSON encoders (like dkjson), this forces an empty table
  -- to be encoded as an array.
  local emptyArray = {}
  setmetatable(emptyArray, { __jsontype = 'array' })
  return emptyArray
end

---
-- Gets file information from a buffer number.
-- This is a helper function to create a file info object from a buffer.
-- It returns nil if the buffer is not a valid, named file.
-- @param bufnr number The buffer number.
-- @return table|nil A table with file information, or nil.
local function getFileInfo(bufnr)
  if not bufnr or bufnr == 0 then return nil end
  local bufName = vim.api.nvim_buf_get_name(bufnr)
  if not bufName or bufName == '' then return nil end
  -- check if file exists
  if vim.fn.filereadable(bufName) == 0 then return nil end

  return { path = bufName, timestamp = os.time() }
end

---
-- Updates the list of open files, making the given buffer the most recent one.
-- If the file is already in the list, it is moved to the front.
-- The previously active file is deactivated.
-- @param bufnr number The buffer number of the file to make active.
local function addOrMoveToFront(bufnr)
  local fileInfo = getFileInfo(bufnr)
  if not fileInfo then return end

  -- Deactivate previous active file
  for _, file in ipairs(state.openFiles) do
    if file.isActive then
      file.isActive = false
      file.cursor = nil
      file.selectedText = nil
    end
  end

  -- Remove if it exists
  local indexToRemove = -1
  for i, file in ipairs(state.openFiles) do
    if file.path == fileInfo.path then
      indexToRemove = i
      break
    end
  end
  if indexToRemove ~= -1 then table.remove(state.openFiles, indexToRemove) end

  -- Add to the front as active
  fileInfo.isActive = true
  table.insert(state.openFiles, 1, fileInfo)

  -- Enforce max length
  if #state.openFiles > MAX_FILES then table.remove(state.openFiles) end
end

---
-- Returns the full IdeContext object to be sent to the Gemini CLI.
-- This function is the main entry point for getting the workspace state.
-- It updates the active file with the current cursor position and selection.
-- @return table The IdeContext object.
function manager.getContext()
  local currentBuf = vim.api.nvim_get_current_buf()
  addOrMoveToFront(currentBuf)

  -- Update cursor and selection for active file
  local activeFile = state.openFiles[1]
  if activeFile and activeFile.isActive then
    local cursorPos = vim.api.nvim_win_get_cursor(0)
    activeFile.cursor = {
      line = cursorPos[1],
      character = cursorPos[2] + 1,
    }

    -- This is a simplified way to get selected text.
    -- It might not work for visual block mode.
    local startPos = vim.fn.getpos("'<")
    local endPos = vim.fn.getpos("'>")
    if startPos[2] ~= 0 and endPos[2] ~= 0 then
      local lines = vim.api.nvim_buf_get_lines(
        currentBuf,
        startPos[2] - 1,
        endPos[2],
        false
      )
      if #lines > 0 then
        -- This is a simplification. It doesn't handle multi-line selection perfectly.
        activeFile.selectedText = table.concat(lines, '\n')
      end
    end
  end

  return {
    workspaceState = {
      openFiles = createJsonArray(state.openFiles),
      isTrusted = state.isTrusted,
    },
  }
end

---
-- Sets up the autocommands to track IDE events.
-- This function should be called once when the plugin is initialized.
-- It registers autocommands for buffer and cursor events to trigger updates.
-- @param onChangeCallback function A function to be called when the context changes.
function manager.setup(onChangeCallback)
  -- Initial population
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then addOrMoveToFront(bufnr) end
  end

  local group =
    vim.api.nvim_create_augroup('GeminiIdeContextManager', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
    group = group,
    pattern = '*',
    callback = function()
      log.debug(
        'BufEnter/BufWinEnter:',
        vim.api.nvim_get_current_buf(),
        vim.api.nvim_buf_get_name(0)
      )
      addOrMoveToFront(vim.api.nvim_get_current_buf())
      onChangeCallback()
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufDelete' }, {
    group = group,
    pattern = '*',
    callback = function(args)
      log.debug('BufDelete/WinClosed callback with args:', args)
      local filePath = vim.api.nvim_buf_get_name(args.buf)
      local indexToRemove = -1
      for i, file in ipairs(state.openFiles) do
        if file.path == filePath then
          indexToRemove = i
          break
        end
      end
      if indexToRemove ~= -1 then
        table.remove(state.openFiles, indexToRemove)
      end
      onChangeCallback()
    end,
  })

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    pattern = '*',
    callback = function() onChangeCallback() end,
  })
end

return manager
