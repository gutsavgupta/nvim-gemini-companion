--- Utility functions for nvim-gemini-companion
-- @module util
local M = {}

--- Check if announcement has been shown before
-- @param announcement_key string: Unique key for the announcement
-- @return boolean: True if announcement has been seen before
local function hasSeenAnnouncement(announcement_key)
  local config_dir = vim.fn.stdpath('data')
  local announcement_file = config_dir
    .. '/nvim-gemini-companion/'
    .. announcement_key
    .. '.txt'

  local f = io.open(announcement_file, 'r')
  if f then
    io.close(f)
    return true
  end
  return false
end

--- Mark announcement as seen
-- @param announcement_key string: Unique key for the announcement
local function markAnnouncementSeen(announcement_key)
  local config_dir = vim.fn.stdpath('data')
  local announcement_dir = config_dir .. '/nvim-gemini-companion'

  -- Create directory if it doesn't exist
  vim.fn.mkdir(announcement_dir, 'p')

  local announcement_file = announcement_dir
    .. '/'
    .. announcement_key
    .. '.txt'
  local f = io.open(announcement_file, 'w')
  if f then
    f:write(os.date())
    io.close(f)
  end
end

--- Show a one-time announcement to users
-- @param announcement_key string: Unique identifier for the announcement
-- @param title string: Title for the notification
-- @param message string: Content of the notification
M.showOneTimeAnnouncement = function(announcement_key, title, message)
  if not hasSeenAnnouncement(announcement_key) then
    vim.notify(message, vim.log.levels.INFO, { title = title })
    markAnnouncementSeen(announcement_key)
  end
end

return M
