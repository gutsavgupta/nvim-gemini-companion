-- This file was created on September 25, 2025
-- This module is responsible for tracking the workspace state, including open files,
-- cursor position, and selected text. It provides the state for the
-- ide/contextUpdate notification sent to the Gemini CLI.

local log = require('plenary.log').new({
  plugin = 'nvim-gemini-companion',
  level = os.getenv('NGC_LOG_LEVEL') or 'warn',
})

local manager = {}
local maxFiles = 10
local state = {
  openFiles = {},
  isTrusted = true, -- Neovim doesn't have a direct equivalent of VS Code's workspace trust
}

---
-- Ensures that an empty Lua table is encoded as an empty JSON array (`[]`)
-- instead of an empty object (`{}`). This is crucial for the Gemini CLI, which
-- expects a list of files.
-- @param t table The table to process.
-- @return table The original table if not empty, or a new table with a metatable
--   to force JSON array encoding for empty tables.
local function createJsonArray(t)
  if t and #t > 0 then return t end
  -- For some JSON encoders (like dkjson), this forces an empty table
  -- to be encoded as an array.
  local emptyArray = {}
  setmetatable(emptyArray, { __jsontype = 'array' })
  return emptyArray
end

---
-- Creates a file information object from a buffer number.
-- It returns nil if the buffer is not associated with a named, readable file on disk.
-- @param bufnr number The buffer number.
-- @return table|nil A table containing the file's absolute path and a timestamp, or nil.
--   Example: { path = "/path/to/file.lua", timestamp = 1678886400 }
local function getFileInfo(bufnr)
  if not bufnr or bufnr == 0 then return nil end
  local bufName = vim.api.nvim_buf_get_name(bufnr)
  if not bufName or bufName == '' then return nil end
  -- check if file exists
  if vim.fn.filereadable(bufName) == 0 then return nil end

  return { path = bufName, timestamp = os.time() }
end

---
-- Updates the internal list of open files.
-- This function marks the specified buffer as the most recent, active file.
-- It deactivates the previously active file, moves the new one to the front of the list,
-- and trims the list if it exceeds `maxFiles`.
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
  if #state.openFiles > maxFiles then table.remove(state.openFiles) end
end

---
-- Gathers and returns the complete IDE context for the Gemini CLI.
-- This is the main public function of the module. It updates the active file's
-- state with the current cursor position and any selected text before returning
-- the full context object.
-- @return table The IdeContext object, structured for the Gemini CLI.
--   Example: { workspaceState = { openFiles = {...}, isTrusted = true } }
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

    -- This is a simplified way to get selected text from the last visual selection.
    -- Note: This may not be perfectly accurate for all selection types,
    -- such as visual block mode.
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
-- Sets up autocommands to track workspace events and keep the context updated.
-- This should be called once during plugin initialization. It tracks buffer
-- changes, cursor movements, and file deletions to trigger the onChangeCallback.
-- @param onChangeCallback function A function to be called whenever the context changes.
function manager.setup(onChangeCallback)
  -- Initial population
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then addOrMoveToFront(bufnr) end
  end

  local group =
    vim.api.nvim_create_augroup('GeminiIdeContextManager', { clear = true })

  -- Track when the user enters a new buffer to mark it as active.
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

  -- Track when a buffer is deleted to remove it from the open files list.
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

  -- Track cursor movement to provide real-time context updates.
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    pattern = '*',
    callback = function() onChangeCallback() end,
  })
end

return manager
