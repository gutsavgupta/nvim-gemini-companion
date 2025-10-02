----------------------------------------------------------------
--- Default configuration for terminal instances
--- This defines the base settings for all terminal windows
----------------------------------------------------------------
local defaultConfig = {
  cmd = vim.o.shell, -- Command to run in the terminal (defaults to user's shell)
  win = {
    preset = 'floating',
    wo = { -- Window options
      number = false, -- Disable line numbers
      relativenumber = false, -- Disable relative line numbers
      signcolumn = 'yes', -- Keep the sign column visible
      list = false, -- Disable showing whitespace characters
      cursorline = false, -- Disable highlighting current line
      fillchars = { eob = ' ' }, -- Fill end-of-buffer with spaces instead of ~
    },
    highlights = { -- Highlight groups for the terminal window
      TermNormal = { link = 'NormalFloat' }, -- Terminal normal text
      NormalFloat = { link = 'NormalFloat' }, -- Float window normal text
      NormalNC = { link = 'NormalFloat' }, -- Normal text in non-current window
      Normal = { link = 'NormalFloat' }, -- Normal text
      Border = { link = 'FloatBorder' }, -- Border highlight
    },
  },
  id = nil, -- Terminal identifier (required for management)
}

-- Define available window layout presets
local presets = {
  ['right-fixed'] = { -- Vertical split on the right side
    position = 'bo vsp', -- Bottom open, vertical split
    width = 0.4, -- 40% of editor width
    max_width = 120, -- Maximum 120 columns
    preset = 'right-fixed',
  },
  ['left-fixed'] = { -- Vertical split on the left side
    position = 'to vsp', -- Top open, vertical split
    width = 0.4, -- 40% of editor width
    max_width = 120, -- Maximum 120 columns
    preset = 'left-fixed',
  },
  ['bottom-fixed'] = { -- Horizontal split at the bottom
    position = 'bo sp', -- Bottom open, split
    height = 0.4, -- 40% of editor height
    max_height = 120, -- Maximum 120 lines
    preset = 'bottom-fixed',
  },
  ['floating'] = { -- Floating window
    position = 'float', -- Use floating window
    width = 0.7, -- 70% of editor width
    height = 0.7, -- 70% of editor height
    row = 0.15, -- 15% from top of screen
    col = 0.15, -- 15% from left of screen
    relative = 'editor', -- Relative to editor window
    border = 'rounded', -- Rounded border style
    zindex = 1000, -- Z-index for layering
    preset = 'floating',
  },
}
local presetKeys = vim.tbl_keys(presets)

----------------------------------------------------------------
--- Helper functions
----------------------------------------------------------------
-- Helper function to convert relative values to absolute values
-- @param value The value to convert (can be relative or absolute)
-- @param max The maximum value to use for relative calculations
-- @return The absolute value
local function relativeToAbsolute(value, max)
  return value < 1 and math.floor(value * max) or value
end

-- Helper function to resize windows horizontally
-- @param size The size to set (in characters or as a percentage of total lines)
local function hresize(size, maxSize)
  size = relativeToAbsolute(size, vim.o.lines)
  size = math.min(maxSize or vim.o.lines, size)
  vim.cmd('resize ' .. size)
end

-- Helper function to resize windows vertically
-- @param size The size to set (in characters or as a percentage of total columns)
local function vresize(size, maxSize)
  size = relativeToAbsolute(size, vim.o.columns)
  size = math.min(maxSize or vim.o.columns, size)
  vim.cmd('vertical resize ' .. size)
end

----------------------------------------------------------------
--- Terminal class definition
----------------------------------------------------------------
local terminals = {}
local terminal = {}
terminal.__index = terminal

----------------------------------------------------------------
--- Terminal class public methods
----------------------------------------------------------------
-- Factory function to create and manage terminal instances
-- Reuses existing terminals if they exist and are valid
-- @param command The command to run in the terminal (optional)
-- @param config Configuration options for the terminal
-- @return terminal instance
function terminal.create(command, config)
  if not config.id then
    error('Terminal ID is required but was not provided')
  end

  -- Check if terminal with this ID already exists
  if terminals[config.id] then
    if vim.api.nvim_buf_is_valid(terminals[config.id].buf) then
      -- Return existing terminal if buffer is still valid
      return terminals[config.id]
    else
      -- Remove reference to invalid terminal
      terminals[config.id] = nil
    end
  end

  -- Create new terminal instance
  local term = terminal.new(config.id, command, config)
  terminals[config.id] = term
  term:show()

  -- Start the job for the terminal
  local jobConfig = {
    detach = false,
    env = (type(term.config.env) == 'table' and term.config.env) or nil,
    on_exit = function()
      if type(term.config.on_exit) == 'function' then
        term.config.on_exit(term)
      end
      term:exit()
    end,
    term = true,
  }
  vim.fn.jobstart(term.cmd, jobConfig)
  return term
end

-- Show the terminal window according to its configuration
-- Handles both floating and non-floating window types differently
-- @return nil
function terminal:show()
  if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
    self:exit()
    return
  end

  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_set_current_win(self.win)
    goto continue
    return
  end

  -- Handle window creation differently based on preset type
  if self.config.extendedWin.preset == 'floating' then
    -- For floating windows
    self.win = self:createFloatWindow()
  else
    -- For split windows
    self.win = self:createSplitWindow()
  end

  -- Apply window options and highlights
  self:applyWindowOptions()
  self:applyHighlights()

  -- Enter insert mode to allow typing in the terminal
  ::continue::
  vim.cmd('startinsert')
end

-- Hide the terminal window if it is currently open
-- @return nil
function terminal:hide()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end
end

-- Toggle the terminal window visibility
-- Shows the terminal if hidden, hides if visible
-- @return nil
function terminal:toggle()
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    self:hide()
  else
    self:show()
  end
end

-- Close and cleanup the terminal instance
-- Removes buffer, window and its reference from the terminals table
-- @return nil
function terminal:exit()
  -- Delete the buffer if it's valid
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
    pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
  end
  -- Close the window if it's open
  if self.win and vim.api.nvim_win_is_valid(self.win) then
    pcall(vim.api.nvim_win_close, self.win, true)
  end
  -- Remove from terminals table to prevent memory leaks
  if self.id then terminals[self.id] = nil end
end

-- Switch the terminal to a different preset layout
-- @param presetName The name of the preset to switch to
-- @return nil
function terminal:switch(presetName)
  if not presets[presetName] then
    vim.notify(
      string.format(
        'Invalid preset: %s, setting preset to right-fixed',
        presetName
      ),
      vim.log.levels.ERROR
    )
    presetName = 'right-fixed'
  end

  -- Update the preset in the config
  self.config.win.preset = presetName
  self.config.extendedWin = vim.tbl_deep_extend(
    'force',
    vim.deepcopy(self.config.win),
    vim.deepcopy(presets[presetName])
  )
  return presetName
end

-- Get available preset keys for terminal layouts
-- @return table of preset keys
function terminal.getPresetKeys() return presetKeys end

-- Get active terminals
-- @return table of terminal instances
function terminal.getActiveTerminals() return terminals end

----------------------------------------------------------------
--- Terminal class helper/private methods
----------------------------------------------------------------
function terminal.new(id, command, config)
  local self = setmetatable({}, terminal)
  self.id = id
  self.buf = vim.api.nvim_create_buf(false, true)

  vim.bo[self.buf].buflisted = false
  vim.bo[self.buf].bufhidden = 'hide'
  vim.bo[self.buf].swapfile = false
  vim.bo[self.buf].modifiable = false
  vim.bo[self.buf].filetype = 'terminalGemini'
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = self.buf,
    callback = function()
      local curWin = vim.api.nvim_get_current_win()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if win ~= curWin then
          vim.api.nvim_set_current_win(win)
          return
        end
      end
    end,
  })

  self.config = vim.tbl_deep_extend(
    'force',
    vim.deepcopy(defaultConfig),
    config and vim.deepcopy(config) or {}
  )
  self.cmd = command or self.config.cmd
  local preset = presets[self.config.win.preset] and self.config.win.preset
    or 'floating'
  self.config.extendedWin = vim.tbl_deep_extend(
    'force',
    vim.deepcopy(self.config.win),
    vim.deepcopy(presets[preset])
  )

  if type(self.config.on_buf) == 'function' then
    self.config.on_buf(self.buf)
  end
  return self
end

-- Helper method to create and configure a floating window
-- @return window handle
function terminal:createFloatWindow()
  local winc = {
    relative = self.config.extendedWin.relative,
    row = relativeToAbsolute(self.config.extendedWin.row, vim.o.lines),
    col = relativeToAbsolute(self.config.extendedWin.col, vim.o.columns),
    width = relativeToAbsolute(self.config.extendedWin.width, vim.o.columns),
    height = relativeToAbsolute(self.config.extendedWin.height, vim.o.lines),
    border = self.config.extendedWin.border,
    zindex = self.config.extendedWin.zindex,
    style = 'minimal',
  }
  return vim.api.nvim_open_win(self.buf, true, winc)
end

-- Helper method to create and configure a split window
-- @return window handle
function terminal:createSplitWindow()
  vim.cmd(self.config.extendedWin.position)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, self.buf)
  if self.config.extendedWin.width then
    vresize(self.config.extendedWin.width, self.config.extendedWin.max_width)
  end
  if self.config.extendedWin.height then
    hresize(self.config.extendedWin.height, self.config.extendedWin.max_height)
  end
  return win
end

-- Helper method to apply window options from configuration
function terminal:applyWindowOptions()
  for k, v in pairs(self.config.extendedWin.wo) do
    pcall(function() vim.wo[self.win][k] = v end)
  end
end

-- Helper method to apply highlight configurations
function terminal:applyHighlights()
  for k, v in pairs(self.config.extendedWin.highlights) do
    pcall(function()
      if v.link then
        vim.api.nvim_set_hl(0, k, { link = v.link })
      else
        vim.api.nvim_set_hl(0, k, v)
      end
    end)
  end
end

----------------------------------------------------------------
--- Module ends
----------------------------------------------------------------
return terminal
