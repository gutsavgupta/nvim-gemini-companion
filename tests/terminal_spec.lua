--- Tests for terminal module's public methods
--- This file contains tests for the terminal module's public methods

local terminal = require('gemini.terminal')

describe('Terminal module tests', function()
  local testId = 'test-terminal'
  local capturedOutput = {}

  before_each(function()
    -- Clean up any existing terminal with the test ID
    local activeTerminals = terminal.getActiveTerminals()
    if activeTerminals[testId] then
      local existingTerm = activeTerminals[testId]
      existingTerm:exit()
    end
    capturedOutput = {}
  end)

  after_each(function()
    -- Clean up test terminal after each test
    local activeTerminals = terminal.getActiveTerminals()
    if activeTerminals[testId] then
      local term = activeTerminals[testId]
      term:exit()
    end
    capturedOutput = {}
  end)

  describe('create method tests', function()
    it('should create a terminal with valid ID', function()
      -- Test that creating a terminal with a valid ID works
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Verify the terminal was created
      assert.are.same(type(term), 'table')
      assert.are.equal(testId, term.id)
      assert.are.same(type(term.buf), 'number')
      assert.is_true(vim.api.nvim_buf_is_valid(term.buf))
    end)

    it('should throw error when ID is not provided', function()
      -- Test that creating a terminal without an ID throws an error
      local config = {
        win = {
          preset = 'floating',
        },
      }
      local success, result = pcall(terminal.create, nil, config)
      assert.is_false(success)
      assert.is_truthy(
        string.find(result, 'Terminal ID is required but was not provided')
      )
    end)

    it('should reuse existing terminal if it is still valid', function()
      -- Create a terminal first
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term1 = terminal.create(nil, config)

      -- Try to create another terminal with the same ID
      local term2 = terminal.create(nil, config)

      -- Verify they are the same instance
      assert.are.equal(term1, term2)
      assert.are.equal(term1.id, term2.id)
    end)

    it('should create new terminal if existing one is invalid', function()
      -- Create a terminal first
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term1 = terminal.create(nil, config)

      -- Close the buffer to make it invalid
      if term1.buf and vim.api.nvim_buf_is_valid(term1.buf) then
        vim.api.nvim_buf_delete(term1.buf, { force = true })
      end

      -- Try to create another terminal with the same ID
      local term2 = terminal.create(nil, config)

      -- Verify they are different instances
      assert.are_not.equal(term1, term2)
    end)
  end)

  describe('show method tests', function()
    it('should show the terminal window', function()
      -- Create a terminal first
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Hide the terminal first to ensure it's hidden
      term:hide()

      -- Verify window is not valid before show
      assert.is_false(term.win and vim.api.nvim_win_is_valid(term.win))

      -- Show the terminal
      term:show()

      -- Verify window is now valid
      assert.is_true(term.win and vim.api.nvim_win_is_valid(term.win))
    end)

    it('should handle invalid buffer gracefully', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Delete the buffer to make it invalid
      if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
        vim.api.nvim_buf_delete(term.buf, { force = true })
      end

      -- Show should handle invalid buffer gracefully (no error)
      local success = pcall(function() term:show() end)
      assert.is_true(success)
    end)
  end)

  describe('hide method tests', function()
    it('should hide the terminal window if it is open', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Show the terminal first to ensure it's visible
      term:show()

      -- Verify window is valid before hide
      assert.is_true(term.win and vim.api.nvim_win_is_valid(term.win))

      -- Hide the terminal
      term:hide()

      -- Verify window is no longer valid
      assert.is_false(term.win and vim.api.nvim_win_is_valid(term.win))
    end)

    it('should handle invalid window gracefully', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Close the window to make it invalid
      if term.win and vim.api.nvim_win_is_valid(term.win) then
        vim.api.nvim_win_close(term.win, true)
      end

      -- Hide should handle invalid window gracefully (no error)
      local success = pcall(function() term:hide() end)
      assert.is_true(success)
    end)
  end)

  describe('toggle method tests', function()
    it('should show the terminal if it is hidden', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Hide the terminal first
      term:hide()

      -- Verify window is not valid before toggle
      assert.is_false(term.win and vim.api.nvim_win_is_valid(term.win))

      -- Toggle should show the terminal
      term:toggle()

      -- Verify window is now valid
      assert.is_true(term.win and vim.api.nvim_win_is_valid(term.win))
    end)

    it('should hide the terminal if it is visible', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Show the terminal first
      term:show()

      -- Verify window is valid before toggle
      assert.is_true(term.win and vim.api.nvim_win_is_valid(term.win))

      -- Toggle should hide the terminal
      term:toggle()

      -- Verify window is no longer valid
      assert.is_false(term.win and vim.api.nvim_win_is_valid(term.win))
    end)
  end)

  describe('exit method tests', function()
    it('should close and cleanup the terminal instance', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Show the terminal to ensure it has a window
      term:show()

      -- Verify terminal is active
      assert.is_true(term.buf and vim.api.nvim_buf_is_valid(term.buf))
      assert.is_true(term.win and vim.api.nvim_win_is_valid(term.win))
      assert.is_not_nil(terminal.getActiveTerminals()[testId])

      -- Exit the terminal
      term:exit()

      -- Verify terminal is cleaned up
      assert.is_false(term.buf and vim.api.nvim_buf_is_valid(term.buf))
      assert.is_false(term.win and vim.api.nvim_win_is_valid(term.win))
      assert.is_nil(terminal.getActiveTerminals()[testId])
    end)

    it('should handle invalid buffer and window gracefully', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Show the terminal first
      term:show()

      -- Delete the buffer and close the window to make them invalid
      if term.buf and vim.api.nvim_buf_is_valid(term.buf) then
        vim.api.nvim_buf_delete(term.buf, { force = true })
      end
      if term.win and vim.api.nvim_win_is_valid(term.win) then
        vim.api.nvim_win_close(term.win, true)
      end

      -- Exit should handle invalid buffer and window gracefully (no error)
      local success = pcall(function() term:exit() end)
      assert.is_true(success)
    end)
  end)

  describe('switch method tests', function()
    it('should switch the terminal to a different preset layout', function()
      -- Create a terminal with floating preset
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Verify initial preset
      assert.are.equal('floating', term.config.win.preset)

      -- Switch to bottom-fixed preset
      term:switch('bottom-fixed')

      -- Verify preset has changed
      assert.are.equal('bottom-fixed', term.config.win.preset)

      -- Verify that config.win has been extended with bottom-fixed preset options
      assert.are.equal('bo sp', term.config.extendedWin.position)
      assert.are.equal(0.4, term.config.extendedWin.height)
    end)

    it('should handle invalid preset gracefully', function()
      -- Create a terminal
      local config = {
        id = testId,
        win = {
          preset = 'floating',
        },
      }
      local term = terminal.create(nil, config)

      -- Verify initial preset is floating
      assert.are.equal('floating', term.config.win.preset)

      -- Switch to invalid preset - should default to 'right-fixed'
      term:switch('invalid-preset')

      -- Verify preset has changed to the default 'right-fixed'
      assert.are.equal('right-fixed', term.config.win.preset)
    end)
  end)

  describe('getPresetKeys method tests', function()
    it('should return available preset keys for terminal layouts', function()
      -- Call the getPresetKeys method
      local presetKeys = terminal.getPresetKeys()

      -- Verify the return value is a table
      assert.are.same(type(presetKeys), 'table')

      -- Verify that it contains the expected preset keys
      local expectedPresets =
        { 'right-fixed', 'left-fixed', 'bottom-fixed', 'floating' }
      for _, expectedPreset in ipairs(expectedPresets) do
        local found = false
        for _, preset in ipairs(presetKeys) do
          if preset == expectedPreset then
            found = true
            break
          end
        end
        assert.is_true(
          found,
          'Preset key ' .. expectedPreset .. ' not found in returned keys'
        )
      end
    end)
  end)

  describe('getActiveTerminals method tests', function()
    it('should return a table of active terminal instances', function()
      -- Get active terminals before creating any
      local activeBefore = terminal.getActiveTerminals()

      -- Create a terminal
      local config = {
        id = testId,
        preset = 'floating',
      }
      local term = terminal.create(nil, config)

      -- Get active terminals after creating
      local activeAfter = terminal.getActiveTerminals()

      -- Verify that the returned value is a table
      assert.are.same(type(activeAfter), 'table')

      -- Verify that the new terminal is in the active terminals table
      assert.is_not_nil(activeAfter[testId])
      assert.are.equal(term, activeAfter[testId])
    end)

    it('should return empty table when no active terminals exist', function()
      -- Ensure no terminals exist by cleaning up any existing ones
      local activeTerminals = terminal.getActiveTerminals()
      for id, term in pairs(activeTerminals) do
        term:exit()
      end

      -- Get active terminals
      local active = terminal.getActiveTerminals()

      -- Verify that the returned value is an empty table
      assert.are.same(type(active), 'table')
      assert.are.equal(0, vim.tbl_count(active))
    end)
  end)
end)
