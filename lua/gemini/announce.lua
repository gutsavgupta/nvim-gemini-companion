--- Utility functions for nvim-gemini-companion
-- @module announce
local M = {}

--- Check if announcement has been shown before
-- @param announcementKey string: Unique key for the announcement
-- @return boolean: True if announcement has been seen before
local function hasSeenAnnouncement(announcementKey)
  local configDir = vim.fn.stdpath('data')
  local announcementFile = configDir
    .. '/nvim-gemini-companion/'
    .. announcementKey
    .. '.txt'

  local f = io.open(announcementFile, 'r')
  if f then
    io.close(f)
    return true
  end
  return false
end

--- Mark announcement as seen
-- @param announcementKey string: Unique key for the announcement
local function markAnnouncementSeen(announcementKey)
  local configDir = vim.fn.stdpath('data')
  local announcementDir = configDir .. '/nvim-gemini-companion'

  -- Create directory if it doesn't exist
  vim.fn.mkdir(announcementDir, 'p')

  local announcementFile = announcementDir .. '/' .. announcementKey .. '.txt'
  local f = io.open(announcementFile, 'w')
  if f then
    f:write(string.format('%s\n', os.date())) -- Use a specific format to ensure string type
    io.close(f)
  end
end

--- Read content from a file
-- @param filePath string: Path to the file to read
-- @return string: Content of the file or empty string if error
local function readFileContent(filePath)
  local f = io.open(filePath, 'r')
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
  vim.wo[win].wrap = true
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

--- Get announcement versions sorted in alphabetical order
-- @return table: Sorted list of announcement version names
M.getAnnouncementVersions = function()
  local announcement_files =
    vim.api.nvim_get_runtime_file('lua/gemini/announcements/*.md', true)
  local versions = {}

  for _, file in ipairs(announcement_files) do
    local version = file:match('([^/]+)%.md')
    if version then table.insert(versions, version) end
  end

  table.sort(versions)

  return versions
end

--- Show a one-time announcement to users in a floating markdown window
-- This function is used to show all unseen announcements during setup
M.showOneTimeAnnouncement = function()
  local versions = M.getAnnouncementVersions()
  local unseen_content = {}
  local unseen_keys = {}

  for i = #versions, 1, -1 do
    local version = versions[i]
    local announcementKey = version .. '_announcement'
    if not hasSeenAnnouncement(announcementKey) then
      local runtime_files = vim.api.nvim_get_runtime_file(
        'lua/gemini/announcements/' .. version .. '.md',
        false
      )
      if #runtime_files > 0 then
        local announcement_path = runtime_files[1]
        local content = readFileContent(announcement_path)
        if content and content ~= '' then
          table.insert(unseen_content, content)
          table.insert(unseen_keys, announcementKey)
        end
      end
    end
  end

  if #unseen_content > 0 then
    local combined_content = table.concat(unseen_content, '\n\n---\n\n')
    for _, key in ipairs(unseen_keys) do
      markAnnouncementSeen(key)
    end
    vim.schedule(
      function() showAnnouncementAsFloatingWindow(combined_content) end
    )
  end
end

--- Show announcement to users in a floating markdown window without tracking if seen
-- @param version string|nil: Version of the announcement to show, or nil for latest
M.showAnnouncement = function(version)
  local versions = M.getAnnouncementVersions()

  if #versions == 0 then
    vim.notify('No announcements found.', vim.log.levels.WARN)
    return
  end

  -- Determine which version to show
  local targetVersion = version
  if targetVersion == nil or targetVersion == '' then
    targetVersion = versions[#versions] -- Show latest if no version specified
  end

  -- Check if the requested version exists
  local versionExists = false
  for _, v in ipairs(versions) do
    if v == targetVersion then
      versionExists = true
      break
    end
  end

  if not versionExists then
    vim.notify(
      'Invalid announcement version: '
        .. targetVersion
        .. '. Available versions: '
        .. table.concat(versions, ', '),
      vim.log.levels.WARN
    )
    return
  end

  -- Get the file path for the requested version
  local runtime_files = vim.api.nvim_get_runtime_file(
    'lua/gemini/announcements/' .. targetVersion .. '.md',
    false
  )

  if #runtime_files > 0 then
    local announcement_path = runtime_files[1]
    local content = readFileContent(announcement_path)
    if content ~= '' then
      vim.schedule(function() showAnnouncementAsFloatingWindow(content) end)
    else
      vim.notify(
        'Announcement file is empty: ' .. targetVersion .. '.md',
        vim.log.levels.WARN
      )
    end
  else
    vim.notify(
      'Announcement file not found: ' .. targetVersion .. '.md',
      vim.log.levels.WARN
    )
  end
end

M.setup = function()
  M.showOneTimeAnnouncement()
  vim.api.nvim_create_user_command(
    'GeminiAnnouncement',
    function(opts) M.showAnnouncement(opts.args or nil) end,
    {
      desc = 'Show plugin announcements',
      nargs = '?',
      complete = function(arg_lead, _, _)
        local versions = M.getAnnouncementVersions()
        local matches = {}

        for _, version in ipairs(versions) do
          if version:match('^' .. vim.pesc(arg_lead)) then
            table.insert(matches, version)
          end
        end

        return matches
      end,
    }
  )
end

return M
