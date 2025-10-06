--- Tests for util module
-- Testing the main functionality of the util module with simplified tests
local assert = require('luassert')
local spy = require('luassert.spy')
local util = require('gemini.util')

describe('util', function()
  local tempFilePath = '/tmp/test_announcement_content.md'

  describe('showOneTimeAnnouncement', function()
    local originalStdpath, originalMkdir, originalSchedule
    local originalIoOpen, originalIoClose

    before_each(function()
      -- Create a test file with announcement content
      local tempFile = io.open(tempFilePath, 'w')
      if tempFile then
        tempFile:write('# Test Announcement\n\nThis is a test announcement.')
        tempFile:close()
      end

      -- Store original functions
      originalStdpath = vim.fn.stdpath
      originalMkdir = vim.fn.mkdir
      originalSchedule = vim.schedule
      originalIoOpen = io.open
      originalIoClose = io.close

      -- Mock necessary functions
      vim.fn.stdpath = spy.new(function(path)
        if path == 'data' then
          return '/tmp'
        else
          return originalStdpath(path)
        end
      end)
      vim.fn.mkdir = spy.new(function() return 0 end)
      vim.schedule = spy.new(function(fn) fn() end) -- Execute immediately for testing

      io.close = spy.new(function(_) end) -- Mock io.close

      io.open = spy.new(function(path, mode)
        if path:match('test_announcement.txt') and mode == 'r' then
          -- Return nil to simulate file not found (first time)
          return nil
        elseif mode == 'w' then
          -- Return a mock file handle with write and close methods
          local mockFile = {
            write = function(_, _) return true end,
            close = function(_) return true end,
          }
          return mockFile
        elseif path == tempFilePath then
          local mockFile = {
            read = function(_, arg)
              if arg == '*a' then
                return '# Test Announcement\n\nThis is a test announcement.'
              end
              return nil
            end,
            close = function() end,
          }
          return mockFile
        else
          return nil
        end
      end)
    end)

    after_each(function()
      -- Restore original functions
      vim.fn.stdpath = originalStdpath
      vim.fn.mkdir = originalMkdir
      vim.schedule = originalSchedule
      io.open = originalIoOpen
      io.close = originalIoClose

      -- Clean up test files
      os.remove(tempFilePath)
      local seenFilePath = '/tmp/nvim-gemini-companion/test_announcement.txt'
      os.remove(seenFilePath)
    end)

    it('should show announcement if not seen before', function()
      util.showOneTimeAnnouncement('test_announcement', tempFilePath)

      -- Should have scheduled the announcement to be shown
      assert.spy(vim.schedule).was.called(1)
    end)

    it('should not show announcement if already seen', function()
      -- Simulate file already exists by changing io.open behavior
      local originalOpen = io.open
      local originalClose = io.close
      io.open = spy.new(function(path, mode)
        if path:match('already_seen_announcement.txt') and mode == 'r' then
          -- Return a mock file handle to simulate file exists (already seen)
          return { close = function() end }
        elseif path == tempFilePath then
          local mockFile = {
            read = function(_, arg)
              if arg == '*a' then
                return '# Test Announcement\n\nThis is a test announcement.'
              end
              return nil
            end,
            close = function() end,
          }
          return mockFile
        elseif mode == 'w' then
          -- Return a mock file handle with write and close methods
          local mockFile = {
            write = function(_, _) return true end,
            close = function(_) return true end,
          }
          return mockFile
        else
          return nil
        end
      end)
      io.close = spy.new(function(_) end)

      util.showOneTimeAnnouncement('already_seen_announcement', tempFilePath)

      -- Should not have scheduled anything since the announcement was already seen
      assert.spy(vim.schedule).was.called(0)

      -- Restore mocks
      io.open = originalOpen
      io.close = originalClose
    end)

    it('should not show announcement if file does not exist', function()
      util.showOneTimeAnnouncement('test_announcement', '/nonexistent/file.md')

      -- Should not have scheduled anything since the file doesn't exist
      assert.spy(vim.schedule).was.called(0)
    end)
  end)
end)
