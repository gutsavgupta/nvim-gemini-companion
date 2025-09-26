-- This file was created on September 26, 2025
-- This file contains tests for the ideSidebar.lua module.

local assert = require('luassert')
local match = require('luassert.match')
local spy = require('luassert.spy')

describe('ideSidebar', function()
  local ideSidebar
  local snacks_terminal_spy
  local term_spy
  local configOpts

  before_each(function()
    -- Reset the module to clear the state
    package.loaded['gemini.ideSidebar'] = nil
    package.loaded['snacks.terminal'] = nil

    -- Mock snacks.terminal
    term_spy = {
      close = spy.new(function() end),
      on = spy.new(function() end),
      buf_valid = function() return true end,
      buf = 1,
    }
    snacks_terminal_spy = {
      toggle = spy.new(function() end),
      get = spy.new(function() return term_spy end),
    }
    package.loaded['snacks.terminal'] = snacks_terminal_spy
    vim.api.nvim_buf_get_var = spy.new(function() return 123 end)
    vim.api.nvim_chan_send = spy.new(function() end)
    vim.fn.jobstop = spy.new(function() end)
    vim.api.nvim_create_user_command = spy.new(function() end)
    vim.fn.getcwd = spy.new(function() return '/fake/dir' end)

    ideSidebar = require('gemini.ideSidebar')
    configOpts = {
      port = 12345,
      cmd = 'gemini',
      env = {},
      win = {
        position = 'right',
        fixed = true,
      },
    }
  end)

  it('should setup user commands', function()
    ideSidebar.setup({ port = 12345 })
    assert.spy(vim.api.nvim_create_user_command).was.called(6)
    assert
      .spy(vim.api.nvim_create_user_command).was
      .called_with('GeminiToggle', match.is_function(), { desc = 'Toggle Gemini sidebar' })
    assert
      .spy(vim.api.nvim_create_user_command).was
      .called_with('GeminiClose', match.is_function(), { desc = 'Close Gemini sidebar' })
    assert.spy(vim.api.nvim_create_user_command).was.called_with(
      'GeminiSend',
      match.is_function(),
      { nargs = '*', desc = 'Send text to Gemini sidebar' }
    )
    assert.spy(vim.api.nvim_create_user_command).was.called_with(
      'GeminiSendFileDiagnostic',
      match.is_function(),
      { desc = 'Send file diagnostics to Gemini sidebar' }
    )
    assert.spy(vim.api.nvim_create_user_command).was.called_with(
      'GeminiSendLineDiagnostic',
      match.is_function(),
      { desc = 'Send line diagnostics to Gemini sidebar' }
    )
    assert.spy(vim.api.nvim_create_user_command).was.called_with(
      'GeminiSwitchSidebarStyle',
      match.is_function(),
      match.is_table()
    )
  end)

  it('should toggle the sidebar', function()
    ideSidebar.toggle(configOpts)
    assert
      .spy(snacks_terminal_spy.toggle).was
      .called_with(configOpts.cmd, configOpts)
  end)

  it('should close the sidebar', function()
    ideSidebar.close(configOpts)
    assert
      .spy(snacks_terminal_spy.get).was
      .called_with(configOpts.cmd, configOpts)
    assert.spy(vim.fn.jobstop).was.called_with(123)
    assert.spy(term_spy.on).was.called()
  end)

  it('should send text to the sidebar', function()
    local text = 'Hello, Gemini!'
    ideSidebar.sendText(configOpts, text)
    assert
      .spy(snacks_terminal_spy.get).was
      .called_with(configOpts.cmd, configOpts)
    local bracketStart = '\27[200~'
    local bracketEnd = '\27[201~\r'
    local bracketedText = bracketStart .. text .. bracketEnd
    assert.spy(vim.api.nvim_chan_send).was.called_with(123, bracketedText)
  end)

  it('should not send text if terminal is invalid', function()
    term_spy.buf_valid = function() return false end
    local text = 'Hello, Gemini!'
    ideSidebar.sendText(configOpts, text)
    assert
      .spy(snacks_terminal_spy.get).was
      .called_with(configOpts.cmd, configOpts)
    assert.spy(vim.api.nvim_chan_send).was.not_called()
  end)

  it('should not send text if channel is not found', function()
    vim.api.nvim_buf_get_var = spy.new(function() return nil end)
    local text = 'Hello, Gemini!'
    ideSidebar.sendText(configOpts, text)
    assert
      .spy(snacks_terminal_spy.get).was
      .called_with(configOpts.cmd, configOpts)
    assert.spy(vim.api.nvim_chan_send).was.not_called()
  end)

  it('should not close if terminal is not found', function()
    snacks_terminal_spy.get = spy.new(function() return nil end)
    ideSidebar.close(configOpts)
    assert
      .spy(snacks_terminal_spy.get).was
      .called_with(configOpts.cmd, configOpts)
    assert.spy(vim.fn.jobstop).was.not_called()
  end)
end)
