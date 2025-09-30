-- This file was created on September 25, 2025
-- This file contains tests for the ideCntxManager.lua module.

local assert = require('luassert')

local spy = require('luassert.spy')

describe('ideCntxManager', function()
  local cntxManager
  local original_filereadable

  before_each(function()
    -- Reset the module to clear the state
    package.loaded['gemini.ideCntxManager'] = nil
    cntxManager = require('gemini.ideCntxManager')

    -- Clean up any buffers created by previous tests
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name and string.match(name, 'test_') then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end

    -- Mock filereadable
    original_filereadable = vim.fn.filereadable
    vim.fn.filereadable = function(path)
      if
        path and (string.match(path, 'test_') or string.match(path, 'test-'))
      then
        return 1
      end
      return original_filereadable(path)
    end
  end)

  after_each(function()
    -- Restore filereadable
    vim.fn.filereadable = original_filereadable
  end)

  it('should initialize with open buffers on setup', function()
    -- 1. Setup: Create some buffers
    local buf1 = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf1, 'test_file1.txt')
    local buf2 = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf2, 'test_file2.txt')

    -- 2. Call setup
    local onChangeSpy = spy.new(function() end)
    cntxManager.setup(onChangeSpy)

    -- 3. Assert
    local context = cntxManager.getContext()
    local openFiles = context.workspaceState.openFiles
    -- The order is not guaranteed, so we check for existence
    assert.is_not_nil(openFiles)

    local found1 = false
    local found2 = false
    for _, file in ipairs(openFiles) do
      if file.path:match('test_file1.txt') then found1 = true end
      if file.path:match('test_file2.txt') then found2 = true end
    end
    assert.is_true(found1, 'test_file1.txt should be in open files')
    assert.is_true(found2, 'test_file2.txt should be in open files')
  end)

  it('should update active file on getContext', function()
    -- 1. Setup
    local buf = vim.api.nvim_create_buf(true, false)
    local filePath = vim.fn.getcwd() .. '/test_active_file.txt'
    vim.api.nvim_buf_set_name(buf, filePath)
    vim.api.nvim_set_current_buf(buf)

    -- 2. Call getContext
    local context = cntxManager.getContext()

    -- 3. Assert
    local openFiles = context.workspaceState.openFiles
    assert.are.equal(1, #openFiles)
    assert.are.equal(filePath, openFiles[1].path)
    assert.is_true(openFiles[1].isActive)
  end)

  it('should capture cursor position', function()
    -- 1. Setup
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, 'test_cursor_pos.txt')
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { 'line 1', 'line 2', 'line 3' }
    )
    vim.api.nvim_win_set_cursor(0, { 2, 4 })

    -- 2. Call getContext
    local context = cntxManager.getContext()

    -- 3. Assert
    local activeFile = context.workspaceState.openFiles[1]
    assert.is_not_nil(activeFile.cursor)
    assert.are.equal(2, activeFile.cursor.line)
    assert.are.equal(5, activeFile.cursor.character)
  end)

  it('should capture selected text', function()
    -- 1. Setup
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, 'test_selection.txt')
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(
      buf,
      0,
      -1,
      false,
      { 'line 1', 'selected text', 'line 3' }
    )

    local win = vim.api.nvim_open_win(
      buf,
      true,
      { relative = 'editor', width = 30, height = 10, row = 0, col = 0 }
    )
    vim.api.nvim_set_current_win(win)

    -- 2. Simulate visual selection
    vim.api.nvim_win_set_cursor(win, { 2, 0 }) -- Move to line 2, col 1
    vim.cmd('normal! V') -- Enter visual mode and select 12 characters
    vim.cmd('normal! y')

    -- 3. Call getContext
    local context = cntxManager.getContext()

    -- 4. Assert
    local activeFile = context.workspaceState.openFiles[1]
    assert.is_not_nil(activeFile.selectedText)
    assert.are.equal('selected text', activeFile.selectedText)

    -- cleanup
    vim.api.nvim_win_close(win, true)
  end)

  it('should handle buffer switching', function()
    -- 1. Setup
    local onChangeSpy = spy.new(function() end)
    cntxManager.setup(onChangeSpy)

    local buf1 = vim.api.nvim_create_buf(true, false)
    local filePath1 = vim.fn.getcwd() .. '/test_switch1.txt'
    vim.api.nvim_buf_set_name(buf1, filePath1)

    local buf2 = vim.api.nvim_create_buf(true, false)
    local filePath2 = vim.fn.getcwd() .. '/test_switch2.txt'
    vim.api.nvim_buf_set_name(buf2, filePath2)

    -- 2. Switch to buf1 and get context
    vim.api.nvim_set_current_buf(buf1)
    local context1 = cntxManager.getContext()

    -- 3. Assert buf1 is active
    assert.are.equal(filePath1, context1.workspaceState.openFiles[1].path)
    assert.is_true(context1.workspaceState.openFiles[1].isActive)

    -- 4. Switch to buf2 and get context
    vim.api.nvim_set_current_buf(buf2)
    local context2 = cntxManager.getContext()

    -- 5. Assert buf2 is active
    assert.are.equal(filePath2, context2.workspaceState.openFiles[1].path)
    assert.is_true(context2.workspaceState.openFiles[1].isActive)
    -- Check that buf1 is no longer active
    assert.are.equal(filePath1, context2.workspaceState.openFiles[2].path)
    assert.is_false(context2.workspaceState.openFiles[2].isActive)
  end)
end)
