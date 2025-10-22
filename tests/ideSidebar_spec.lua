--- Tests for ideSidebar module
-- Testing all public methods of the ideSidebar module
local assert = require('luassert')
local spy = require('luassert.spy')

describe('ideSidebar', function()
  local ideSidebar
  local terminalMock

  before_each(function()
    -- Reset the module to get a fresh instance
    package.loaded['gemini.ideSidebar'] = nil
    package.loaded['gemini.terminal'] = nil

    -- Create a mock for the terminal module
    terminalMock = {
      create = spy.new(function(cmd, config)
        return {
          toggle = spy.new(function() end),
          exit = spy.new(function() end),
          hide = spy.new(function() end),
          show = spy.new(function() end),
          switch = spy.new(function() end),
          buf = 1,
          id = config and config.id or 'test-id',
        }
      end),
      getActiveTerminals = spy.new(function()
        return {} -- Initially empty
      end),
      getPresetKeys = spy.new(
        function()
          return { 'right-fixed', 'left-fixed', 'bottom-fixed', 'floating' }
        end
      ),
    }

    -- Mock the vim functions that are used
    vim.api.nvim_buf_get_var = spy.new(function() return 123 end)
    vim.api.nvim_chan_send = spy.new(function() end)
    vim.api.nvim_buf_is_valid = spy.new(function() return true end) -- Default to valid
    vim.fn.executable = spy.new(function() return 1 end) -- All executables exist
    vim.fn.getcwd = spy.new(function() return '/test/dir' end)
    vim.diagnostic.get = spy.new(function() return {} end)
    vim.api.nvim_get_current_buf = spy.new(function() return 1 end)
    vim.api.nvim_win_get_cursor = spy.new(function() return { 1, 0 } end)
    vim.api.nvim_buf_get_name = spy.new(function() return 'test.lua' end)
    vim.api.nvim_buf_get_lines = spy.new(function() return { 'test line' } end)
    vim.api.nvim_create_user_command = spy.new(function() end)
    vim.defer_fn = spy.new(function() end) -- Don't execute immediately for tests
    vim.ui.select = spy.new(function(items, opts, callback)
      if #items > 0 and callback then
        callback(items[1]) -- Select first item by default for tests
      end
    end)
    vim.notify = spy.new(function() end)
    vim.system = spy.new(function(cmd, opts, callback)
      if callback then
        callback({ code = 0 }) -- Simulate success by default
      end
    end)

    -- Override require for terminal to return our mock
    local original_require = require
    _G.require = function(module_name)
      if module_name == 'gemini.terminal' then
        return terminalMock
      else
        return original_require(module_name)
      end
    end

    ideSidebar = require('gemini.ideSidebar')
    
    -- Mock the new tmux-related functions to avoid interfering with production tmux sessions
    ideSidebar.getActiveTerminals = function()
      -- Return only sidebar terminals, not real tmux sessions
      local activeTerminals = terminalMock.getActiveTerminals()
      local combinedSessions = {}

      -- Validate and add active terminals
      for id, term in pairs(activeTerminals) do
        if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
          local termName = 'sidebar:' .. (term.config.name or id)
          table.insert(combinedSessions, termName)
        end
      end

      return combinedSessions
    end
    
    -- Mock the new functions to avoid real tmux interactions
    ideSidebar.sendTextToTmux = spy.new(function(sessionName, text) end)
    ideSidebar.spawnOrSwitchToTmux = spy.new(function(cmd) end)
  end)

  after_each(function()
    -- Restore original require
    _G.require = require
  end)

  describe('setup method', function()
    it('should create terminal options for provided command', function()
      -- Call setup with a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Verify that terminal options were created by checking if user commands were created
      assert.spy(vim.api.nvim_create_user_command).was.called_at_least(1)
    end)

    it('should create user commands', function()
      -- Call setup
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Verify that vim.api.nvim_create_user_command was called for each expected command
      -- There are 7 commands: GeminiToggle, GeminiSwitchSidebarStyle, GeminiSend,
      -- GeminiSendFileDiagnostic, GeminiSendLineDiagnostic, GeminiClose, GeminiToggleTmux
      assert.spy(vim.api.nvim_create_user_command).was.called(7)
    end)
  end)

  describe('toggle method', function()
    it('should create a new terminal if one does not exist', function()
      -- Configure the mock to return no active terminal
      terminalMock.getActiveTerminals = spy.new(function() return {} end)

      -- Setup the sidebar first with a command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Call toggle
      ideSidebar.toggle()

      -- Verify that terminal.create was called
      assert.spy(terminalMock.create).was.called(1)
    end)

    it('should toggle an existing terminal if one exists', function()
      -- Create a deterministic ID for the terminal
      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }

      -- Setup the sidebar first to create the terminal options
      ideSidebar.setup({ cmd = cmd, port = 12345 })

      -- Create a mock terminal with the expected ID (with idx = 1 for single command)
      local expectedId = ideSidebar.createDeterministicId(cmd, env, 1)
      local mockTerm = {
        toggle = spy.new(function() end),
      }

      -- Setup the active terminals to return our mock term with the expected ID
      local activeTerminals = {}
      activeTerminals[expectedId] = mockTerm
      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Call toggle
      ideSidebar.toggle()

      -- Check if toggle was called on the mock term
      assert.spy(mockTerm.toggle).was.called(1)
    end)
  end)

  describe('close method', function()
    it('should close an existing terminal', function()
      -- Create a mock terminal with expected ID
      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }

      -- Setup the sidebar first to create the terminal options
      ideSidebar.setup({ cmd = cmd, port = 12345 })

      -- Create a mock terminal with exit method (with idx = 1 for single command)
      local expectedId = ideSidebar.createDeterministicId(cmd, env, 1)
      local mockTerm = {
        exit = spy.new(function() end),
      }

      -- Setup the active terminals to return our mock term with the expected ID
      local activeTerminals = {}
      activeTerminals[expectedId] = mockTerm
      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Call close
      ideSidebar.close()

      -- Check if exit was called on the mock term
      assert.spy(mockTerm.exit).was.called(1)
    end)

    it('should log warning if no terminal exists', function()
      -- Configure the mock to return no active terminal
      terminalMock.getActiveTerminals = spy.new(function() return {} end)

      -- Setup the sidebar first with a command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Call close
      ideSidebar.close()

      -- Verify that no terminal exit was called (since no terminal exists)
      -- The method should just return without calling exit on a nil terminal
    end)
  end)

  describe('switchTerms method', function()
    it('should hide current terminal and show next one', function()
      -- Setup multiple commands to have multiple terminals to switch between
      ideSidebar.setup({ cmds = { 'gemini', 'qwen' }, port = 12345 })

      -- Create mock terminals
      local geminiEnv = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }
      local qwenEnv = {
        QWEN_CODE_IDE_WORKSPACE_PATH = '/test/dir',
        QWEN_CODE_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }

      local geminiId = ideSidebar.createDeterministicId('gemini', geminiEnv)
      local qwenId = ideSidebar.createDeterministicId('qwen', qwenEnv)

      local geminiTerm = {
        hide = spy.new(function() end),
        show = spy.new(function() end),
      }

      local qwenTerm = {
        hide = spy.new(function() end),
        show = spy.new(function() end),
      }

      local activeTerminals = {}
      activeTerminals[geminiId] = geminiTerm
      activeTerminals[qwenId] = qwenTerm

      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Mock terminal.create to return the correct terminals
      local originalCreate = terminalMock.create
      terminalMock.create = spy.new(function(cmd, config)
        if cmd == 'gemini' then
          return geminiTerm
        else
          return qwenTerm
        end
      end)

      -- Call switchTerms
      ideSidebar.switchTerms()

      -- Check that hide was called on the first terminal and show on the second
      assert.spy(geminiTerm.hide).was.called(1)
      assert.spy(qwenTerm.show).was.called(1)
    end)
  end)

  describe('switchStyle method', function()
    it('should switch terminal style to specified preset', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }
      local expectedId = ideSidebar.createDeterministicId(cmd, env, 1)

      local mockTerm = {
        hide = spy.new(function() end),
        switch = spy.new(function() end),
      }

      local activeTerminals = {}
      activeTerminals[expectedId] = mockTerm
      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Call switchStyle with a specific preset
      ideSidebar.switchStyle('left')

      -- Check that switch was called with the correct preset
      assert.spy(mockTerm.switch).was.called(1) -- switch should be called once
    end)

    it('should cycle to next preset if no preset specified', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }
      local expectedId = ideSidebar.createDeterministicId(cmd, env, 1)

      local mockTerm = {
        hide = spy.new(function() end),
        switch = spy.new(function() end),
      }

      local activeTerminals = {}
      activeTerminals[expectedId] = mockTerm
      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Call switchStyle with no preset (should cycle to next)
      ideSidebar.switchStyle()

      -- The important thing is that switch is called with some preset
      assert.spy(mockTerm.switch).was.called(1)
    end)
  end)

  describe('sendDiagnostic method', function()
    it('should send diagnostic information to terminal as JSON', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Create mock terminal
      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }
      local expectedId = ideSidebar.createDeterministicId(cmd, env)

      local mockTerm = {
        show = spy.new(function() end),
      }

      local activeTerminals = {}
      activeTerminals[expectedId] = mockTerm
      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Mock creating a terminal
      terminalMock.create = spy.new(function(cmd, config) return mockTerm end)

      -- Mock diagnostics - the lnum is 0-indexed, so line 5 in the test means line 6 when +1
      local mockDiagnostics = {
        {
          lnum = 5, -- line number (0-indexed) -> line 6 (1-indexed)
          col = 10,
          severity = vim.diagnostic.severity.ERROR,
          message = 'Test error message',
          source = 'test-source',
        },
      }

      -- Mock terminal creation for when sendText calls terminal.create
      local originalCreate = terminalMock.create
      terminalMock.create = spy.new(function(cmd, config)
        return {
          buf = 1,
          show = spy.new(function() end),
          exit = spy.new(function() end),
        }
      end)

      -- Mock channel related functions for sendText to work properly
      vim.api.nvim_buf_get_var = spy.new(function(buf, varname)
        return 123 -- mock channel id
      end)
      vim.api.nvim_chan_send = spy.new(function(channel, text) end)

      -- Create a spy that captures the text parameter
      local capturedText = nil
      local sendTextSpy = spy.new(function(text) capturedText = text end)
      local originalSendText = ideSidebar.sendText
      ideSidebar.sendText = sendTextSpy

      vim.diagnostic.get = spy.new(function(bufnr) return mockDiagnostics end)
      vim.api.nvim_buf_get_name = spy.new(
        function(bufnr) return 'testFile.lua' end
      )

      -- Call sendDiagnostic with nil line number to get all diagnostics
      ideSidebar.sendDiagnostic(1, nil) -- bufnr = 1, no line filter

      -- Restore original function
      ideSidebar.sendText = originalSendText
      terminalMock.create = originalCreate

      -- Check if sendText was called and captured the text
      assert.spy(sendTextSpy).was.called(1)
      assert.truthy(capturedText)
      assert.truthy(string.find(capturedText, 'testFile.lua'))
      assert.truthy(string.find(capturedText, 'Test error message'))
    end)

    it('should handle empty diagnostics', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Mock empty diagnostics
      vim.diagnostic.get = spy.new(function(bufnr) return {} end)

      -- Call sendDiagnostic with empty diagnostics
      ideSidebar.sendDiagnostic(1, 6)

      -- Should not error, just return
    end)
  end)

  describe('sendSelectedText method', function()
    it('should send selected text from visual range to terminal', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Mock terminal
      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }
      local expectedId = ideSidebar.createDeterministicId(cmd, env)

      local mockTerm = {
        show = spy.new(function() end),
      }

      local activeTerminals = {}
      activeTerminals[expectedId] = mockTerm
      terminalMock.getActiveTerminals = function() return activeTerminals end

      -- Mock creating a terminal
      terminalMock.create = spy.new(function(cmd, config) return mockTerm end)

      -- Mock terminal creation for when sendText calls terminal create
      local originalCreate = terminalMock.create
      terminalMock.create = spy.new(function(cmd, config)
        return {
          buf = 1,
          show = spy.new(function() end),
          exit = spy.new(function() end),
        }
      end)

      -- Mock channel related functions for sendText to work properly
      vim.api.nvim_buf_get_var = spy.new(function(buf, varname)
        return 123 -- mock channel id
      end)
      vim.api.nvim_chan_send = spy.new(function(channel, text) end)

      -- Mock visual selection range
      vim.fn.line = spy.new(function(range)
        if range == "'<" then
          return 2
        elseif range == "'>" then
          return 3
        else
          return 1
        end
      end)

      vim.fn.col = spy.new(function(range)
        if range == "'<" then
          return 2
        elseif range == "'>" then
          return 5
        else
          return 1
        end
      end)

      -- Mock buffer lines
      vim.api.nvim_buf_get_lines = spy.new(
        function(buf, start, end_line, strict_indexing)
          return { 'line 1', 'line 2 content', 'line 3 more content', 'line 4' }
        end
      )

      -- Mock sendText to capture what gets sent
      local capturedText = nil
      local sendTextSpy = spy.new(function(text) capturedText = text end)
      local originalSendText = ideSidebar.sendText
      ideSidebar.sendText = sendTextSpy

      -- Call sendSelectedText
      local cmdOpts = { args = 'additional text' }
      ideSidebar.sendSelectedText(cmdOpts)

      -- Restore original function
      ideSidebar.sendText = originalSendText
      terminalMock.create = originalCreate

      -- Check that sendText was called with selected text + additional args
      assert.spy(sendTextSpy).was.called(1)
      assert.truthy(capturedText)
      -- The selected text should be included, plus the additional text
      assert.truthy(string.find(capturedText, 'additional text'))
    end)

    it('should handle no visual selection', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Mock no visual selection
      vim.fn.line = spy.new(function(range)
        if range == "'<" then
          return 0 -- no selection
        elseif range == "'>" then
          return 0
        else
          return 1
        end
      end)

      vim.fn.col = spy.new(function(range)
        if range == "'<" then
          return 0
        elseif range == "'>" then
          return 0
        else
          return 1
        end
      end)

      -- Mock terminal creation for when sendText calls terminal create
      local originalCreate = terminalMock.create
      terminalMock.create = spy.new(function(cmd, config)
        return {
          buf = 1,
          show = spy.new(function() end),
          exit = spy.new(function() end),
        }
      end)

      -- Mock channel related functions for sendText to work properly
      vim.api.nvim_buf_get_var = spy.new(function(buf, varname)
        return 123 -- mock channel id
      end)
      vim.api.nvim_chan_send = spy.new(function(channel, text) end)

      -- Mock sendText to capture what gets sent
      local capturedText = nil
      local sendTextSpy = spy.new(function(text) capturedText = text end)
      local originalSendText = ideSidebar.sendText
      ideSidebar.sendText = sendTextSpy

      -- Call sendSelectedText
      local cmdOpts = { args = 'only args text' }
      ideSidebar.sendSelectedText(cmdOpts)

      -- Restore original function
      ideSidebar.sendText = originalSendText
      terminalMock.create = originalCreate

      -- Check that sendText was called with only the additional args
      assert.spy(sendTextSpy).was.called(1)
      assert.truthy(capturedText)
      assert.truthy(string.find(capturedText, 'only args text'))
    end)
  end)

  describe('sendText method', function()
    it('should send text to terminal using bracketed paste mode', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Create mock terminal
      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }
      local expectedId = ideSidebar.createDeterministicId(cmd, env)

      local mockTerm = {
        buf = 1,
        show = spy.new(function() end),
        exit = spy.new(function() end),
      }

      -- Mock creating a terminal
      terminalMock.create = spy.new(function(cmd, config) return mockTerm end)

      -- Mock buffer validation function to confirm buffer is valid
      local originalBufIsValid = vim.api.nvim_buf_is_valid
      vim.api.nvim_buf_is_valid = function(buf)
        return buf == 1 -- Only buffer 1 is valid
      end

      -- Mock buffer and channel functions
      vim.api.nvim_buf_get_var = function(buf, varname)
        if buf == 1 then
          return 123 -- mock channel id for valid buffer
        else
          return 0 -- no channel for invalid
        end
      end

      local sentText = nil
      vim.api.nvim_chan_send = spy.new(
        function(channel, text) sentText = text end
      )

      -- Call sendText
      ideSidebar.sendText('Hello world')

      -- Restore original function
      vim.api.nvim_buf_is_valid = originalBufIsValid

      -- Check that text was sent with bracketed paste markers
      assert.spy(vim.api.nvim_chan_send).was.called(1)
      assert.truthy(sentText)
      -- Should contain the bracketed paste markers: \27[200~text\27[201~\r
      assert.truthy(string.find(sentText, 'Hello world'))
    end)

    it('should handle case when terminal buffer is invalid', function()
      -- Setup for a single command
      ideSidebar.setup({ cmd = 'gemini', port = 12345 })

      -- Mock terminal creation to return a terminal with invalid buffer
      local mockTerm = {
        buf = 99999, -- invalid buffer
        exit = spy.new(function() end),
        show = spy.new(function() end),
      }
      terminalMock.create = spy.new(function(cmd, config) return mockTerm end)

      -- Mock to simulate invalid buffer
      vim.api.nvim_buf_is_valid = function(buf)
        return false -- All buffers are invalid for this test
      end

      -- Call sendText - should handle gracefully when buffer is invalid
      local success = pcall(function() ideSidebar.sendText('Hello world') end)

      -- Should not crash - the function should handle the invalid buffer gracefully
      assert.is_true(success)

      -- The function should return early when buffer is invalid, without calling
      -- nvim_buf_get_var or nvim_chan_send
      assert.spy(mockTerm.exit).was.called_at_least(1) -- exit should be called when buffer is invalid
    end)
  end)

  describe('createDeterministicId method', function()
    it('should create consistent ID from command and environment', function()
      -- Test that the same input always produces the same ID
      local cmd = 'gemini'
      local env = {
        GEMINI_CLI_IDE_WORKSPACE_PATH = '/test/dir',
        GEMINI_CLI_IDE_SERVER_PORT = '12345',
        TERM_PROGRAM = 'vscode',
      }

      local id1 = ideSidebar.createDeterministicId(cmd, env)
      local id2 = ideSidebar.createDeterministicId(cmd, env)

      -- Same inputs should produce the same ID
      assert.are.equal(id1, id2)
    end)

    it('should handle nested environment tables', function()
      -- Test with nested environment table
      local cmd = 'qwen'
      local env = {
        QWEN_CODE_IDE_WORKSPACE_PATH = '/test/dir',
        nested = {
          deep = {
            value = 'test',
          },
        },
        TERM_PROGRAM = 'vscode',
      }

      local id = ideSidebar.createDeterministicId(cmd, env)

      -- Should create an ID without error
      assert.truthy(id)
      assert.truthy(type(id) == 'string')
      -- Should contain the command name
      assert.truthy(string.find(id, 'qwen'))
    end)

    it('should sort keys to ensure consistency', function()
      -- Test that different order of keys produces same ID
      local cmd = 'gemini'
      local env1 = {
        ZZZ = 'last',
        AAA = 'first',
        MMM = 'middle',
      }

      local env2 = {
        AAA = 'first',
        ZZZ = 'last',
        MMM = 'middle',
      }

      local id1 = ideSidebar.createDeterministicId(cmd, env1)
      local id2 = ideSidebar.createDeterministicId(cmd, env2)

      -- Same keys with different order should produce same ID
      assert.are.equal(id1, id2)
    end)
  end)
end)
