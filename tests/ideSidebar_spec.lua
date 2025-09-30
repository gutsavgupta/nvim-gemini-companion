-- This file was created on September 26, 2025
-- This file contains tests for the ideSidebar.lua module.

local assert = require('luassert')
local match = require('luassert.match')
local spy = require('luassert.spy')

describe('ideSidebar', function()
  local ideSidebar
  local skterminal_spy
  local term_spy

  before_each(function()
    -- Reset the module to clear the state
    package.loaded['gemini.ideSidebar'] = nil
    package.loaded['snacks.terminal'] = nil

    -- Mock snacks.terminal
    term_spy = {
      toggle = spy.new(function() end),
      hide = spy.new(function() end),
      show = spy.new(function() end),
      focus = spy.new(function() end),
      close = spy.new(function() end),
      on = spy.new(function() end),
      buf_valid = function() return true end,
      buf = 1,
      opts = {},
    }

    skterminal_spy = {
      get = spy.new(function() return term_spy, false end),
    }
    package.loaded['snacks.terminal'] = skterminal_spy

    vim.fn.executable = spy.new(function() return 1 end)
    vim.api.nvim_buf_get_var = spy.new(function() return 123 end)
    vim.api.nvim_chan_send = spy.new(function() end)
    vim.fn.jobstop = spy.new(function() end)
    vim.api.nvim_create_user_command = spy.new(function() end)
    vim.fn.getcwd = spy.new(function() return '/fake/dir' end)
    vim.diagnostic.get = spy.new(function() return {} end)
    vim.defer_fn = spy.new(function(fn) fn() end)

    ideSidebar = require('gemini.ideSidebar')
  end)

  describe('setup', function()
    it('should create user commands', function()
      ideSidebar.setup({ port = 12345 })
      assert.spy(vim.api.nvim_create_user_command).was.called(6)
      assert.spy(vim.api.nvim_create_user_command).was.called_with(
        'GeminiToggle',
        match.is_function(),
        { desc = 'Toggle Gemini/Qwen sidebar' }
      )
      assert
        .spy(vim.api.nvim_create_user_command).was
        .called_with('GeminiClose', match.is_function(), { desc = 'Close Gemini sidebar' })
      assert.spy(vim.api.nvim_create_user_command).was.called_with(
        'GeminiSend',
        match.is_function(),
        {
          nargs = '*',
          range = true,
          desc = 'Send selected text (with provided text) to active sidebar',
        }
      )
      assert.spy(vim.api.nvim_create_user_command).was.called_with(
        'GeminiSendFileDiagnostic',
        match.is_function(),
        { desc = 'Send file diagnostics to active sidebar' }
      )
      assert.spy(vim.api.nvim_create_user_command).was.called_with(
        'GeminiSendLineDiagnostic',
        match.is_function(),
        { desc = 'Send line diagnostics to active sidebar' }
      )
      assert
        .spy(vim.api.nvim_create_user_command).was
        .called_with('GeminiSwitchSidebarStyle', match.is_function(), match.is_table())
    end)

    it('should set up terminal opts for multiple cmds', function()
      ideSidebar.setup({ cmds = { 'gemini', 'qwen' }, port = 12345 })
      local get_calls = skterminal_spy.get.calls
      assert.are.equal(#get_calls, 0) -- setup doesn't call get

      ideSidebar.toggle()
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
    end)

    it('should set GEMINI environment variables', function()
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })
      ideSidebar.toggle()
      local opts = skterminal_spy.get.calls[1].vals[2]
      assert.equal(opts.env.GEMINI_CLI_IDE_WORKSPACE_PATH, '/fake/dir')
      assert.equal(opts.env.GEMINI_CLI_IDE_SERVER_PORT, '12345')
    end)

    it('should set QWEN environment variables', function()
      ideSidebar.setup({ cmd = 'qwen', port = 12345 })
      ideSidebar.toggle()
      local opts = skterminal_spy.get.calls[1].vals[2]
      assert.equal(opts.env.QWEN_CODE_IDE_WORKSPACE_PATH, '/fake/dir')
      assert.equal(opts.env.QWEN_CODE_IDE_SERVER_PORT, '12345')
    end)

    it('should not initialize opts for non-executable commands', function()
      vim.fn.executable = spy.new(function(cmd)
        if cmd == 'gemini' then return 0 end
        return 1
      end)
      ideSidebar.setup({ cmds = { 'gemini', 'qwen' } })
      ideSidebar.toggle()
      -- only qwen should be initialized
      assert.spy(skterminal_spy.get).was.called_with('qwen', match.is_table())
      assert
        .spy(skterminal_spy.get).was
        .not_called_with('gemini', match.is_table())
    end)
  end)

  describe('toggle', function()
    it('should toggle the terminal', function()
      ideSidebar.setup({ cmd = 'gemini' })
      ideSidebar.toggle()
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      assert.spy(term_spy.toggle).was.called(1)
    end)

    it('should not toggle if terminal is newly created', function()
      skterminal_spy.get = spy.new(function() return term_spy, true end)
      ideSidebar.setup({ cmd = 'gemini' })
      ideSidebar.toggle()
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      assert.spy(term_spy.toggle).was.not_called()
    end)
  end)

  describe('switch', function()
    it('should switch between terminals', function()
      ideSidebar.setup({ cmds = { 'gemini', 'qwen' } })

      -- First switch
      ideSidebar.switch()
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      assert.spy(term_spy.hide).was.called(1)
      assert.spy(skterminal_spy.get).was.called_with('qwen', match.is_table())
      assert.spy(term_spy.show).was.called(1)
      assert.spy(term_spy.focus).was.called(1)

      -- Second switch (wraps around)
      ideSidebar.switch()
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      assert.spy(term_spy.hide).was.called(2)
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      assert.spy(term_spy.show).was.called(2)
      assert.spy(term_spy.focus).was.called(2)
    end)
  end)

  describe('close', function()
    it('should close the terminal', function()
      ideSidebar.setup({ cmd = 'gemini' })
      ideSidebar.close()
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      assert.spy(vim.fn.jobstop).was.called_with(123)
      assert.spy(term_spy.on).was.called()
    end)
  end)

  describe('sendText', function()
    it('should send text to the terminal', function()
      ideSidebar.setup({ cmd = 'gemini' })
      local text = 'Hello, Gemini!'
      ideSidebar.sendText(text)
      assert.spy(skterminal_spy.get).was.called_with('gemini', match.is_table())
      local bracketStart = '\27[200~'
      local bracketEnd = '\27[201~\r'
      local bracketedText = bracketStart .. text .. bracketEnd
      assert.spy(vim.api.nvim_chan_send).was.called_with(123, bracketedText)
      assert.spy(term_spy.show).was.called(1)
      assert.spy(term_spy.focus).was.called(1)
    end)
  end)

  describe('sendDiagnostic', function()
    it('should send diagnostics to the terminal', function()
      ideSidebar.setup({ cmd = 'gemini' })
      local diagnostics = {
        {
          lnum = 0,
          severity = vim.diagnostic.severity.ERROR,
          message = 'Test error',
          source = 'test',
        },
      }
      vim.diagnostic.get = spy.new(function() return diagnostics end)
      vim.api.nvim_buf_get_name = spy.new(
        function() return '/fake/file.lua' end
      )
      ideSidebar.sendDiagnostic(1)

      local expected_data = {
        filename = '/fake/file.lua',
        diagnostics = {
          {
            linenumber = 1,
            severity = 'ERROR',
            message = 'Test error',
            source = 'test',
          },
        },
      }

      assert.spy(vim.diagnostic.get).was.called()
      assert.spy(vim.api.nvim_chan_send).was.called()
      local sent_text = vim.api.nvim_chan_send.calls[1].vals[2]
      assert.are.same(expected_data, vim.fn.json_decode(sent_text:sub(7, -8)))
    end)
  end)

  describe('handleGeminiSend', function()
    it(
      'should handle sending selected text when visual selection exists',
      function()
        ideSidebar.setup({ cmd = 'gemini' })
        -- Mock the visual selection functions to simulate a selection
        vim.fn.line = spy.new(function(arg)
          if arg == "'<" then
            return 5
          elseif arg == "'>" then
            return 5
          else
            return 0
          end
        end)
        vim.fn.col = spy.new(function(arg)
          if arg == "'<" then
            return 2
          elseif arg == "'>" then
            return 8
          else
            return 0
          end
        end)
        vim.api.nvim_buf_get_lines = spy.new(
          function() return { 'selected text' } end
        )
        -- Spy on sendText to verify it's called with the correct text
        local sendTextSpy = spy.on(ideSidebar, 'sendText')
        local cmdOpts = { args = 'additional text' }
        ideSidebar.handleGeminiSend(cmdOpts)
        -- Verify sendText was called with the selected text plus the additional text
        -- From 'selected text', substring from index 2 to 8 would be 'elected' (Lua uses 1-based indexing)
        -- start_idx = 2 - 1 = 1, substring(1+1, 8) = 'elected'
        assert.spy(sendTextSpy).was.called_with('elected additional text')
      end
    )

    it('should send provided text when no visual selection exists', function()
      ideSidebar.setup({ cmd = 'gemini' })
      -- Mock the visual selection functions to simulate no selection
      vim.fn.line = spy.new(function(arg)
        if arg == "'<" then
          return 0
        elseif arg == "'>" then
          return 0
        else
          return 0
        end
      end)
      -- Spy on sendText to verify it's called with the correct text
      local sendTextSpy = spy.on(ideSidebar, 'sendText')
      local cmdOpts = { args = 'test text' }
      ideSidebar.handleGeminiSend(cmdOpts)
      -- Verify sendText was called with only the provided text
      assert.spy(sendTextSpy).was.called_with('test text')
    end)

    it('should handle multi-line visual selection', function()
      ideSidebar.setup({ cmd = 'gemini' })
      -- Mock the visual selection functions to simulate a multi-line selection
      vim.fn.line = spy.new(function(arg)
        if arg == "'<" then
          return 1
        elseif arg == "'>" then
          return 3
        else
          return 0
        end
      end)
      vim.fn.col = spy.new(function(arg)
        if arg == "'<" then
          return 1
        elseif arg == "'>" then
          return 3
        else
          return 0
        end
      end)
      vim.api.nvim_buf_get_lines = spy.new(
        function()
          return { 'line 1 content', 'line 2 content', 'line 3 content' }
        end
      )
      -- Spy on sendText to verify it's called with the correct text
      local sendTextSpy = spy.on(ideSidebar, 'sendText')
      local cmdOpts = { args = 'extra text' }
      ideSidebar.handleGeminiSend(cmdOpts)
      -- Verify sendText was called with the selected lines plus the additional text
      -- Lines 1-3 selected (with 0-indexed parameter to nvim_buf_get_lines: 0-3 means lines 1-3 in editor)
      -- First line starts at col 1 (unchanged), last line ends at col 3 ('lin')
      assert
        .spy(sendTextSpy).was
        .called_with('line 1 content\nline 2 content\nlin extra text')
    end)
  end)

  describe('setStyle', function()
    it('should set the style of the terminal', function()
      ideSidebar.setup({ cmd = 'gemini' })
      ideSidebar.setStyle('floating')
      assert.spy(term_spy.hide).was.called(1)
      assert.spy(vim.defer_fn).was.called(1)
      assert.spy(term_spy.toggle).was.called(1)
      assert.equal(term_spy.opts.position, 'float')
    end)
  end)
end)
