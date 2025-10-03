-- This file was created on September 25, 2025
-- This file contains tests for the ideDiffManager.lua module.

local spy = require('luassert.spy')

describe('ideDiffManager', function()
  local diffManager

  before_each(function()
    -- Go to the first tab and close all others to ensure a clean state
    vim.api.nvim_set_current_tabpage(1)
    vim.cmd('silent! tabonly')

    -- Reset the module to clear the 'views' table
    package.loaded['gemini.ideDiffManager'] = nil
    diffManager = require('gemini.ideDiffManager')

    -- Mock vim.schedule to run functions immediately for testing
    _G.originalVimSchedule = vim.schedule
    vim.schedule = function(fn) fn() end
  end)

  after_each(function()
    -- Restore the original vim.schedule
    vim.schedule = _G.originalVimSchedule
  end)

  it('should open a diff view with the correct setup', function()
    -- 1. Setup test data
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1', 'line 2' }, tempFile)
    local newContent = 'line 1\nline 2 changed'

    -- 2. Check initial state
    assert.are.equal(
      1,
      #vim.api.nvim_list_tabpages(),
      'Should start with one tab'
    )

    -- 3. Call the open method
    diffManager.open(tempFile, newContent)

    -- 4. Assert the final state
    assert.are.equal(
      2,
      #vim.api.nvim_list_tabpages(),
      'Should have opened a new tab'
    )

    local currentTab = vim.api.nvim_get_current_tabpage()
    assert.is_not_equal(1, currentTab, 'Should be in the new tab')

    local diffWins = vim.api.nvim_tabpage_list_wins(currentTab)
    assert.are.equal(2, #diffWins, 'New tab should have two windows')

    -- Check left window (original file)
    local leftBuf = vim.api.nvim_win_get_buf(diffWins[1])
    assert.are.equal(tempFile, vim.api.nvim_buf_get_name(leftBuf))
    assert.is_true(
      vim.wo[diffWins[1]].diff,
      'Left window should be in diff mode'
    )

    -- Check right window (modified content)
    local rightBuf = vim.api.nvim_win_get_buf(diffWins[2])
    local expectedBufName = vim.fn.fnamemodify(tempFile, ':t')
      .. ' <-> modified'
    local actualBufName = vim.api.nvim_buf_get_name(rightBuf)
    -- Check that the buffer name ends with the expected name.
    -- This is more robust than a direct equality check, in case the
    -- full path is unexpectedly prepended.
    assert.is_true(
      actualBufName:sub(-#expectedBufName) == expectedBufName,
      "Expected buffer name to end with '"
        .. expectedBufName
        .. "', but got '"
        .. actualBufName
        .. "'"
    )
    assert.are.equal(
      true,
      vim.wo[diffWins[2]].diff,
      'Right window should be in diff mode'
    )
  end)

it('should close the diff view', function()
    -- 1. Setup: Open a diff view first
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1' }, tempFile)
    local newContent = 'line 1 changed'
    diffManager.open(tempFile, newContent)

    diffManager.close(tempFile)

    -- 3. Assert the final state
    assert.are.equal(
      1,
      #vim.api.nvim_list_tabpages(),
      'Should have only one tab after close'
    )
  end)

  it("should accept the diff and call onClose with 'accepted'", function()
    -- 1. Setup: Open a diff view first
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1' }, tempFile)
    local newContent = 'line 1 changed'
    local onCloseSpy = spy.new(function() end)
    diffManager.open(tempFile, newContent, onCloseSpy)

    -- 2. Call the accept method
    diffManager.accept(tempFile)

    -- 3. Assert the final state
    assert.spy(onCloseSpy).was.called_with(newContent, 'accepted')
    local fileContent = vim.fn.readfile(tempFile)
    assert.are.same({ 'line 1' }, fileContent)
  end)

  it("should reject the diff and call onClose with 'rejected'", function()
    -- 1. Setup: Open a diff view first
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1' }, tempFile)
    local newContent = 'line 1 changed'
    local onCloseSpy = spy.new(function() end)
    diffManager.open(tempFile, newContent, onCloseSpy)

    -- 2. Call the reject method
    diffManager.reject(tempFile)

    -- 3. Assert the final state
    assert.spy(onCloseSpy).was.called_with(newContent, 'rejected')
    local fileContent = vim.fn.readfile(tempFile)
    assert.are.same({ 'line 1' }, fileContent)
  end)

  it('should handle opening a diff for the same file twice', function()
    -- 1. Setup
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1' }, tempFile)
    local newContent1 = 'line 1 changed'
    local newContent2 = 'line 1 changed again'

    -- 2. Open the diff for the first time
    diffManager.open(tempFile, newContent1)
    assert.are.equal(
      2,
      #vim.api.nvim_list_tabpages(),
      'Should have two tabs after first open'
    )

    -- 3. Close the diff
    diffManager.close(tempFile)
    assert.are.equal(
      1,
      #vim.api.nvim_list_tabpages(),
      'Should have one tab after close'
    )

    -- 4. Open the diff for the second time and assert it doesn't error
    assert.does_not.error(
      function() diffManager.open(tempFile, newContent2) end
    )
    assert.are.equal(
      2,
      #vim.api.nvim_list_tabpages(),
      'Should have two tabs after second open'
    )
  end)

  it('should get the file path from the window ID', function()
    -- 1. Setup: Open a diff view first
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1' }, tempFile)
    local newContent = 'line 1 changed'
    diffManager.open(tempFile, newContent)

    -- 2. Get the window ID of the right-hand side window
    local diffWins =
      vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
    local rightWin = diffWins[2]

    -- 3. Call getFilePathFromWindowID with the window ID
    local filePath = diffManager.getFilePathFromWindowID(rightWin)

    -- 4. Assert that the returned file path is correct
    assert.are.equal(tempFile, filePath)

    -- 5. Call getFilePathFromWindowID with an invalid window ID
    local invalidFilePath = diffManager.getFilePathFromWindowID(-1)

    -- 6. Assert that the function returns nil
    assert.is_nil(invalidFilePath)
  end)

  it('should lock the buffers in the diff view', function()
    -- 1. Setup test data
    local tempFile = vim.fn.tempname()
    vim.fn.writefile({ 'line 1', 'line 2' }, tempFile)
    local newContent = 'line 1\nline 2 changed'

    -- 2. Call the open method
    diffManager.open(tempFile, newContent)

    -- 3. Get the windows from the new tab
    local currentTab = vim.api.nvim_get_current_tabpage()
    local diffWins = vim.api.nvim_tabpage_list_wins(currentTab)

    -- 4. Assert that winfixbuf is set for both windows
    assert.is_true(
      vim.api.nvim_get_option_value('winfixbuf', { win = diffWins[1] }),
      'Left window should have winfixbuf set'
    )
    assert.is_true(
      vim.api.nvim_get_option_value('winfixbuf', { win = diffWins[2] }),
      'Right window should have winfixbuf set'
    )
  end)

  it('should set the correct filetype for the new content buffer', function()
    -- 1. Setup test data
    local tempFile = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ 'local x = 1' }, tempFile)
    local newContent = 'local x = 2'

    -- 2. Call the open method
    diffManager.open(tempFile, newContent)

    -- 3. Get the buffers from the new tab
    local currentTab = vim.api.nvim_get_current_tabpage()
    local diffWins = vim.api.nvim_tabpage_list_wins(currentTab)
    local leftBuf = vim.api.nvim_win_get_buf(diffWins[1])
    local rightBuf = vim.api.nvim_win_get_buf(diffWins[2])

    -- 4. Assert that the filetypes are the same
    local leftFiletype = vim.api.nvim_buf_get_option(leftBuf, 'filetype')
    local rightFiletype = vim.api.nvim_buf_get_option(rightBuf, 'filetype')

    assert.are.equal('lua', leftFiletype, 'Original filetype should be lua')
    assert.are.equal(leftFiletype, rightFiletype, 'New content buffer should have the same filetype as the original')
  end)

  describe('autocmd triggers', function()
    it("should accept changes when ':wq' is used", function()
      -- 1. Setup
      local tempFile = vim.fn.tempname()
      vim.fn.writefile({ 'line 1' }, tempFile)
      local newContent = 'line 1 changed'
      local onCloseSpy = spy.new(function() end)
      diffManager.open(tempFile, newContent, onCloseSpy)

      -- 2. Get the buffer of the modified buffer
      local diffWins =
        vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
      local rightBuf = vim.api.nvim_win_get_buf(diffWins[2])

      -- 3. Simulate :wq command by triggering the autocmds
      vim.api.nvim_exec_autocmds(
        'BufWriteCmd',
        { buffer = rightBuf, modeline = false }
      )
      vim.api.nvim_exec_autocmds(
        'BufWinLeave',
        { buffer = rightBuf, modeline = false }
      )

      -- 4. Assert
      assert.spy(onCloseSpy).was.called_with(newContent, 'accepted')
      assert.are.equal(
        1,
        #vim.api.nvim_list_tabpages(),
        'Should have closed the diff tab'
      )
    end)

    it("should reject changes when ':q' is used", function()
      -- 1. Setup
      local tempFile = vim.fn.tempname()
      vim.fn.writefile({ 'line 1' }, tempFile)
      local newContent = 'line 1 changed'
      local onCloseSpy = spy.new(function() end)
      diffManager.open(tempFile, newContent, onCloseSpy)

      -- 2. Get the buffer of the modified buffer
      local diffWins =
        vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())
      local rightBuf = vim.api.nvim_win_get_buf(diffWins[2])

      -- 3. Simulate :q command by triggering the autocmd
      vim.api.nvim_exec_autocmds(
        'BufWinLeave',
        { buffer = rightBuf, modeline = false }
      )

      -- 4. Assert
      assert.spy(onCloseSpy).was.called_with(newContent, 'rejected')
      assert.are.equal(
        1,
        #vim.api.nvim_list_tabpages(),
        'Should have closed the diff tab'
      )
    end)
  end)
end)
