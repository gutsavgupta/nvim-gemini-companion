--- Tests for announce module
-- Testing the main functionality of the announce module with simplified tests
local announce = require('gemini.announce')
local assert = require('luassert')
local spy = require('luassert.spy')

describe('announce', function()
  describe('showOneTimeAnnouncement', function()
    local originalStdpath, originalMkdir, originalSchedule, originalNvimGetRuntimeFile
    local originalIoOpen, originalIoClose

    before_each(function()
      -- Store original functions
      originalStdpath = vim.fn.stdpath
      originalMkdir = vim.fn.mkdir
      originalSchedule = vim.schedule
      originalNvimGetRuntimeFile = vim.api.nvim_get_runtime_file
      originalIoOpen = io.open
      originalIoClose = io.close

      -- Mock necessary functions with spies
      vim.fn.stdpath = spy.new(function(path)
        if path == 'data' then
          return '/tmp'
        else
          return originalStdpath(path)
        end
      end)
      vim.fn.mkdir = spy.new(function() return 0 end)
      vim.schedule = spy.new(function(fn) fn() end) -- Execute immediately for testing

      -- Mock the runtime file to return the existing announcement file
      vim.api.nvim_get_runtime_file = spy.new(function(path)
        if path:match('announcements') then
          return {
            '/mock/path/lua/gemini/announcements/v0.5_release.md',
            '/mock/path/lua/gemini/announcements/v0.6_release.md',
          }
        else
          return {}
        end
      end)

      io.close = spy.new(function(_) end) -- Mock io.close

      io.open = spy.new(function(path, mode)
        if mode == 'w' then
          -- Return a mock file handle with write and close methods
          local mockFile = {
            write = function(_, _) return true end,
            close = function(_) return true end,
          }
          return mockFile
        elseif path:match('v0.5_release.md') then
          local mockFile = {
            read = function(_, arg)
              if arg == '*a' then return 'content v0.5' end
              return nil
            end,
            close = function() end,
          }
          return mockFile
        elseif path:match('v0.6_release.md') then
          local mockFile = {
            read = function(_, arg)
              if arg == '*a' then return 'content v0.6' end
              return nil
            end,
            close = function() end,
          }
          return mockFile
        else
          -- For reading seen files, the behavior is defined in each test
          return nil
        end
      end)
    end)

    after_each(function()
      -- Restore original functions
      vim.fn.stdpath = originalStdpath
      vim.fn.mkdir = originalMkdir
      vim.schedule = originalSchedule
      vim.api.nvim_get_runtime_file = originalNvimGetRuntimeFile
      io.open = originalIoOpen
      io.close = originalIoClose

      -- Clean up test files
      os.remove('/tmp/test_announcement_v0.5_release.txt')
      os.remove('/tmp/test_announcement_v0.6_release.txt')
    end)

    it('should show announcements if none are seen', function()
      local originalOpen = io.open
      io.open = spy.new(function(path, mode)
        if
          (
            path:match('v0.5_release_announcement')
            or path:match('v0.6_release_announcement')
          ) and mode == 'r'
        then
          return nil -- not seen
        end
        return originalOpen(path, mode)
      end)

      vim.schedule:clear()
      announce.showOneTimeAnnouncement()
      assert.spy(vim.schedule).was.called(1)
      io.open = originalOpen
    end)

    it('should not show announcements if all are seen', function()
      local originalOpen = io.open
      io.open = spy.new(function(path, mode)
        if
          (
            path:match('v0.5_release_announcement')
            or path:match('v0.6_release_announcement')
          ) and mode == 'r'
        then
          return { close = function() end } -- seen
        end
        return originalOpen(path, mode)
      end)

      vim.schedule:clear()
      announce.showOneTimeAnnouncement()
      assert.spy(vim.schedule).was.called(0)
      io.open = originalOpen
    end)

    it('should show one announcement if one is seen', function()
      local originalOpen = io.open
      io.open = spy.new(function(path, mode)
        if path:match('v0.5_release_announcement') and mode == 'r' then
          return { close = function() end } -- seen
        end
        if path:match('v0.6_release_announcement') and mode == 'r' then
          return nil -- not seen
        end
        return originalOpen(path, mode)
      end)

      vim.schedule:clear()
      announce.showOneTimeAnnouncement()
      assert.spy(vim.schedule).was.called(1)
      io.open = originalOpen
    end)

    it(
      'should not show announcement if no announcement files are available',
      function()
        local originalGetRuntimeFile = vim.api.nvim_get_runtime_file
        vim.api.nvim_get_runtime_file = spy.new(function(_, _)
          return {} -- Return empty table to simulate no announcement files
        end)

        vim.schedule:clear()
        announce.showOneTimeAnnouncement()
        -- Should not have scheduled anything since no announcement files exist
        assert.spy(vim.schedule).was.called(0)
        -- Restore original
        vim.api.nvim_get_runtime_file = originalGetRuntimeFile
      end
    )
  end)

  describe('getAnnouncementVersions', function()
    local originalNvimGetRuntimeFile

    before_each(
      function() originalNvimGetRuntimeFile = vim.api.nvim_get_runtime_file end
    )

    after_each(
      function() vim.api.nvim_get_runtime_file = originalNvimGetRuntimeFile end
    )

    it('should return a sorted list of announcement versions', function()
      -- Mock to return some test files
      vim.api.nvim_get_runtime_file = spy.new(function(path, _)
        if path:match('announcements') then
          return {
            '/mock/path/lua/gemini/announcements/v0.5_release.md',
            '/mock/path/lua/gemini/announcements/v0.4_release.md',
            '/mock/path/lua/gemini/announcements/v0.6_release.md',
          }
        end
        return {}
      end)

      local versions = announce.getAnnouncementVersions()
      assert.are.equal(3, #versions)
      assert.are.same(
        { 'v0.4_release', 'v0.5_release', 'v0.6_release' },
        versions
      )
    end)

    it('should return empty table when no announcement files exist', function()
      -- Mock to return empty list
      vim.api.nvim_get_runtime_file = spy.new(function(path)
        if path:match('announcements') then return {} end
        return {}
      end)

      local versions = announce.getAnnouncementVersions()
      -- Should return empty table
      assert.are.equal(0, #versions)
    end)
  end)

  describe('showAnnouncement', function()
    local originalSchedule, originalNvimGetRuntimeFile, originalIoOpen
    local originalNotify

    before_each(function()
      -- Store original functions
      originalSchedule = vim.schedule
      originalNvimGetRuntimeFile = vim.api.nvim_get_runtime_file
      originalIoOpen = io.open
      originalNotify = vim.notify

      -- Mock necessary functions
      vim.schedule = spy.new(function(fn) fn() end) -- Execute immediately for testing
      vim.notify = spy.new(function() end) -- Mock notifications

      io.open = spy.new(function(path, mode)
        if path:match('v0.5_release.md') and mode == 'r' then
          local mockFile = {
            read = function(_, arg)
              if arg == '*a' then
                return '# Test Announcement\\n\\nThis is a test announcement.'
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

      vim.api.nvim_get_runtime_file = spy.new(function(path, _)
        if path:match('announcements/v0.5_release.md') then
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        else
          return {}
        end
      end)
    end)

    after_each(function()
      -- Restore original functions
      vim.schedule = originalSchedule
      vim.api.nvim_get_runtime_file = originalNvimGetRuntimeFile
      io.open = originalIoOpen
      vim.notify = originalNotify
    end)

    it('should show latest announcement when no version is provided', function()
      vim.api.nvim_get_runtime_file = spy.new(function(path, all)
        if path:match('announcements.*%.md') and all == true then
          -- This is the call from getAnnouncementVersions() to discover all announcement files
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        elseif path:match('announcements/v0.5_release.md') and all == false then
          -- This is the call from showAnnouncement to get the specific file
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        else
          return {}
        end
      end)

      vim.schedule:clear()
      announce.showAnnouncement(nil)

      -- Should have scheduled the announcement to be shown
      assert.spy(vim.schedule).was.called(1)
    end)

    it('should show specific announcement when version is provided', function()
      vim.api.nvim_get_runtime_file = spy.new(function(path, all)
        if path:match('announcements.*%.md') and all == true then
          -- This is the call from getAnnouncementVersions() to discover all announcement files
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        elseif path:match('announcements/v0.5_release.md') and all == false then
          -- This is the call from showAnnouncement to get the specific file
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        else
          return {}
        end
      end)

      vim.schedule:clear()
      announce.showAnnouncement('v0.5_release')

      -- Should have scheduled the announcement to be shown
      assert.spy(vim.schedule).was.called(1)
    end)

    it('should show warning for invalid announcement version', function()
      -- Mock to return a different version to simulate invalid version
      vim.api.nvim_get_runtime_file = spy.new(function(path)
        if path:match('announcements/nonexistent.md') then
          return {}
        else
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        end
      end)

      vim.schedule:clear()
      announce.showAnnouncement('nonexistent')

      -- Should have called vim.notify with warning
      assert.spy(vim.notify).was.called(1)
      assert.spy(vim.schedule).was.called(0)
    end)

    it('should show warning when no announcement files exist', function()
      -- Mock to return empty list for all files
      vim.api.nvim_get_runtime_file = spy.new(function() return {} end)
      vim.schedule:clear()
      announce.showAnnouncement()

      -- Should have called vim.notify with warning
      assert.spy(vim.notify).was.called(1)
      assert.spy(vim.schedule).was.called(0)
    end)
  end)

  describe('setup', function()
    local originalShowOneTimeAnnouncement, originalCreateUserCommand
    local originalNvimGetRuntimeFile

    before_each(function()
      -- Store original functions
      originalShowOneTimeAnnouncement = announce.showOneTimeAnnouncement
      originalCreateUserCommand = vim.api.nvim_create_user_command
      originalNvimGetRuntimeFile = vim.api.nvim_get_runtime_file

      -- Replace showOneTimeAnnouncement with a spy
      announce.__metatable = false -- Disable metatable protection if present
      announce.showOneTimeAnnouncement = spy.new(function() end)
      vim.api.nvim_create_user_command = spy.new(function() end)

      vim.api.nvim_get_runtime_file = function(path, all)
        if path:match('announcements/v0.5_release.md') then
          return { '/mock/path/lua/gemini/announcements/v0.5_release.md' }
        else
          return {}
        end
      end
    end)

    after_each(function()
      -- Restore original functions
      announce.showOneTimeAnnouncement = originalShowOneTimeAnnouncement
      vim.api.nvim_create_user_command = originalCreateUserCommand
      vim.api.nvim_get_runtime_file = originalNvimGetRuntimeFile
    end)

    it('should call showOneTimeAnnouncement and create user command', function()
      announce.setup()
      assert.spy(announce.showOneTimeAnnouncement).was.called(1)
      assert.spy(vim.api.nvim_create_user_command).was.called(1)
    end)
  end)
end)
