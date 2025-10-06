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
    f:write(string.format('%s\n', os.date())) -- Use a specific format to ensure string type
    io.close(f)
  end
end

--- Read content from a file
-- @param file_path string: Path to the file to read
-- @return string: Content of the file or empty string if error
local function readFileContent(file_path)
  local f = io.open(file_path, 'r')
  if not f then return '' end

  local content = f:read('*a')
  f:close()
  return content
end

--- Create a markdown floating window for announcements
-- @param content string: Markdown content for the announcement
local function showAnnouncementAsFloatingWindow(content)
  -- Create a scratch buffer for the announcement
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = 'markdown'

  -- Set the content
  local lines = {}
  for line in content:gmatch('([^\n]*)\n?') do
    table.insert(lines, line)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Get dimensions
  local width = math.floor(vim.o.columns * 0.6)
  local height = math.min(#lines, math.floor(vim.o.lines * 0.6))

  -- Calculate window position (centered)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    noautocmd = true,
  })

  -- Set window options
  vim.wo[win].winhighlight =
    'Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder'
  vim.bo[buf].modifiable = false

  -- Add close keymap (q or Esc)
  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    'q',
    '<Cmd>close<CR>',
    { noremap = true, silent = true }
  )
  vim.api.nvim_buf_set_keymap(
    buf,
    'n',
    '<Esc>',
    '<Cmd>close<CR>',
    { noremap = true, silent = true }
  )

  -- Close on buffer leave
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  -- Set the window to be read-only
  vim.bo[buf].modifiable = false
end

--- Show a one-time announcement to users in a floating markdown window
-- @param announcement_key string: Unique identifier for the announcement
-- @param file_path string: Path to the markdown file containing the announcement
M.showOneTimeAnnouncement = function(announcement_key, file_path)
  if not hasSeenAnnouncement(announcement_key) then
    local content = readFileContent(file_path)
    if content ~= '' then
      markAnnouncementSeen(announcement_key)
      -- Schedule the announcement to show after the UI is ready
      vim.schedule(function() showAnnouncementAsFloatingWindow(content) end)
    end
  end
end

return M
