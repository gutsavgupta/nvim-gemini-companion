-- This file was created on September 25, 2025
-- This file contains tests for the ideSidebar.lua module.

local assert = require('luassert')
local match = require('luassert.match')
local spy = require('luassert.spy')

describe('ideSidebar', function()
  local sidebar
  local original_termopen
  local original_jobstop

  before_each(function()
    -- Go to the first tab and close all others to ensure a clean state
    vim.api.nvim_set_current_tabpage(1)
    vim.cmd('silent! tabonly')

    -- Reset the module to clear the state
    package.loaded.ideSidebar = nil
    sidebar = require('ideSidebar')

    -- Mock terminal functions
    original_termopen = vim.fn.termopen
    original_jobstop = vim.fn.jobstop
    vim.fn.termopen = spy.new(function() return 123 end)
    vim.fn.jobstop = spy.new(function() end)
  end)

  after_each(function()
    sidebar.close()
    vim.fn.termopen = original_termopen
    vim.fn.jobstop = original_jobstop
  end)

  it('should setup with default and custom options', function()
    -- 1. Spy on nvim_win_set_width
    local nvim_win_set_width_spy = spy.on(vim.api, 'nvim_win_set_width')

    -- 2. Setup with custom options
    local opts = { width = 100, command = 'my-command', port = 12345 }
    sidebar.setup(opts)

    -- 3. Open sidebar
    sidebar.open()

    -- 4. Assert that nvim_win_set_width was called with the correct width
    assert.spy(nvim_win_set_width_spy).was.called()
    assert.spy(nvim_win_set_width_spy).was.called_with(match.is_number(), 100)

    -- Restore the original function
    nvim_win_set_width_spy:revert()
  end)

  it('should open and close the sidebar', function()
    -- 1. Check initial state
    assert.are.equal(
      1,
      #vim.api.nvim_list_wins(),
      'Should start with one window'
    )

    -- 2. Open the sidebar
    sidebar.open()

    -- 3. Assert that a new window is opened
    assert.are.equal(
      2,
      #vim.api.nvim_list_wins(),
      'Should have opened a new window'
    )
    local winId = vim.api.nvim_get_current_win()
    assert.is_true(vim.wo[winId].winfixwidth)

    -- 4. Close the sidebar
    sidebar.close()

    -- 5. Assert that the window is closed
    assert.are.equal(
      1,
      #vim.api.nvim_list_wins(),
      'Should have only one window after close'
    )
    assert.spy(vim.fn.jobstop).was_called_with(123)
  end)

  it('should toggle the sidebar', function()
    -- 1. Open the sidebar
    sidebar.open()
    assert.are.equal(2, #vim.api.nvim_list_wins(), 'Sidebar should be open')

    -- 2. Toggle to hide
    sidebar.toggle()
    assert.are.equal(1, #vim.api.nvim_list_wins(), 'Sidebar should be hidden')

    -- 3. Toggle to open again
    sidebar.toggle()
    assert.are.equal(
      2,
      #vim.api.nvim_list_wins(),
      'Sidebar should be open again'
    )
  end)

  it('should focus existing sidebar on open', function()
    -- 1. Open the sidebar
    sidebar.open()
    local winId1 = vim.api.nvim_get_current_win()

    -- 2. Go to another window
    vim.cmd('wincmd p')
    assert.is_not_equal(winId1, vim.api.nvim_get_current_win())

    -- 3. Call open again
    sidebar.open()

    -- 4. Assert that the current window is the sidebar window
    assert.are.equal(winId1, vim.api.nvim_get_current_win())
    assert.are.equal(
      2,
      #vim.api.nvim_list_wins(),
      'Should not open a new window'
    )
  end)
end)
