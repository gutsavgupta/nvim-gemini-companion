local persistence = require('gemini.persistence')
local uv = vim.loop

describe('persistence module', function()
  local testFilePath = '/tmp/nvim-gemini-companion-test.json'
  local currentPid = vim.fn.getpid()
  local currentWorkspace = vim.fn.getcwd()

  before_each(function()
    -- Clean up any existing test files
    if uv.fs_stat(testFilePath) then uv.fs_unlink(testFilePath) end
  end)

  after_each(function()
    -- Clean up test files after each test
    if uv.fs_stat(testFilePath) then uv.fs_unlink(testFilePath) end
  end)

  describe('getServerDetailsPath', function()
    it(
      'should return a path with the correct format including CWD hash',
      function()
        local path = persistence.getServerDetailsPath()
        local cwd = vim.fn.getcwd()
        local cwdHash = vim.fn.sha256(cwd)
        local expectedPattern = '/tmp/nvim%-gemini%-companion%-'
          .. string.sub(cwdHash, 1, 12)
          .. '%.json'

        assert.are.equal(type(path), 'string')
        assert.truthy(
          string.match(path, expectedPattern),
          'Path does not match expected pattern: ' .. path
        )
      end
    )

    it(
      'should return different paths for different working directories',
      function()
        local path = persistence.getServerDetailsPath()
        local cwd = vim.fn.getcwd()
        local cwdHash = vim.fn.sha256(cwd)
        local expectedHash = string.sub(cwdHash, 1, 12)
        local hashPattern = '/tmp/nvim%-gemini%-companion%-([a-f0-9]+)%.json'
        local foundHash = string.match(path, hashPattern)

        assert.are.equal(foundHash, expectedHash)
      end
    )
  end)

  describe('readServerDetails', function()
    local testPath = '/tmp/nvim-gemini-companion-test-read.json'

    before_each(function()
      -- Clean up any existing test file
      if uv.fs_stat(testPath) then uv.fs_unlink(testPath) end
    end)

    after_each(function()
      -- Clean up test file after each test
      if uv.fs_stat(testPath) then uv.fs_unlink(testPath) end
    end)

    it('should return nil when file does not exist', function()
      local result = persistence.readServerDetails(testPath)
      assert.are.equal(result, nil)
    end)

    it('should return nil when file contains invalid JSON', function()
      local file = io.open(testPath, 'w')
      file:write('invalid json content')
      file:close()

      local result = persistence.readServerDetails(testPath)
      assert.are.equal(result, nil)
    end)

    it('should return parsed data when file contains valid JSON', function()
      local testData = {
        port = 8080,
        workspace = '/tmp/test',
        pid = 1234,
        timestamp = os.time(),
      }

      local file = io.open(testPath, 'w')
      file:write(vim.fn.json_encode(testData))
      file:close()

      local result = persistence.readServerDetails(testPath)
      assert.are.equal(type(result), 'table')
      assert.are.equal(result.port, testData.port)
      assert.are.equal(result.workspace, testData.workspace)
      assert.are.equal(result.pid, testData.pid)
      assert.are.equal(result.timestamp, testData.timestamp)
    end)

    it('should use default path when no path is provided', function()
      local defaultPath = persistence.getServerDetailsPath()

      -- Create a file at default path
      local testData = {
        port = 9090,
        workspace = '/tmp/default',
      }

      local file = io.open(defaultPath, 'w')
      file:write(vim.fn.json_encode(testData))
      file:close()

      local result = persistence.readServerDetails()
      assert.are.equal(type(result), 'table')
      assert.are.equal(result.port, testData.port)
      assert.are.equal(result.workspace, testData.workspace)

      -- Clean up
      if uv.fs_stat(defaultPath) then uv.fs_unlink(defaultPath) end
    end)
  end)

  describe('writeServerDetails', function()
    local testPath = '/tmp/nvim-gemini-companion-test-write.json'

    before_each(function()
      -- Clean up any existing test file
      if uv.fs_stat(testPath) then uv.fs_unlink(testPath) end
    end)

    after_each(function()
      -- Clean up test file after each test
      if uv.fs_stat(testPath) then uv.fs_unlink(testPath) end
    end)

    it('should create a file with the correct server details', function()
      local testPort = 8080
      local testWorkspace = '/tmp/test'

      persistence.writeServerDetails(testPort, testWorkspace)

      -- Check that the default path file was created
      local defaultPath = persistence.getServerDetailsPath()
      assert.truthy(
        uv.fs_stat(defaultPath),
        'Default path file was not created'
      )

      -- Read the file and verify contents
      local content = persistence.readServerDetails(defaultPath)
      assert.are.equal(type(content), 'table')
      assert.are.equal(content.port, testPort)
      assert.are.equal(content.workspace, testWorkspace)
      assert.are.equal(content.pid, currentPid)
      assert.truthy(content.timestamp and type(content.timestamp) == 'number')
    end)

    it('should overwrite existing file with new server details', function()
      local firstPort = 8080
      local firstWorkspace = '/tmp/test1'
      local secondPort = 9090
      local secondWorkspace = '/tmp/test2'

      persistence.writeServerDetails(firstPort, firstWorkspace)
      local firstContent = persistence.readServerDetails()
      assert.are.equal(firstContent.port, firstPort)

      persistence.writeServerDetails(secondPort, secondWorkspace)
      local secondContent = persistence.readServerDetails()
      assert.are.equal(secondContent.port, secondPort)
      assert.are.equal(secondContent.workspace, secondWorkspace)
    end)
  end)

  describe('getServerDetailsForSameWorkspace', function()
    -- Helper function to create a server details file for a specific workspace
    local function createServerDetailsFile(workspace, port, pid, timestamp)
      local cwdHash = vim.fn.sha256(workspace)
      local shortHash = string.sub(cwdHash, 1, 12)
      local filename =
        string.format('/tmp/nvim-gemini-companion-%s.json', shortHash)
      local data = {
        port = port,
        workspace = workspace,
        pid = pid,
        timestamp = timestamp or os.time(),
      }
      local file = io.open(filename, 'w')
      file:write(vim.fn.json_encode(data))
      file:close()
      return filename
    end

    before_each(function()
      -- Remove all existing nvim-gemini-companion files
      local files = vim.fn.glob('/tmp/nvim-gemini-companion-*.json', true, true)
      for _, file in ipairs(files) do
        if uv.fs_stat(file) then uv.fs_unlink(file) end
      end
    end)

    after_each(function()
      -- Clean up any test files created
      local files = vim.fn.glob('/tmp/nvim-gemini-companion-*.json', true, true)
      for _, file in ipairs(files) do
        if uv.fs_stat(file) then uv.fs_unlink(file) end
      end
    end)

    it('should return nil when no server details files exist', function()
      local result = persistence.getServerDetailsForSameWorkspace()
      assert.are.equal(result, nil)
    end)

    it(
      'should return nil when there are files but none match current workspace',
      function()
        -- Create a server details file with different workspace
        local differentWorkspace = '/tmp/different-workspace'
        if currentWorkspace == differentWorkspace then
          differentWorkspace = '/tmp/another-workspace'
        end
        createServerDetailsFile(differentWorkspace, 8080, currentPid + 1000)

        local result = persistence.getServerDetailsForSameWorkspace()
        assert.are.equal(result, nil)
      end
    )

    it(
      'should return server details when there is a file with matching workspace',
      function()
        -- Create a server details file with the current workspace and a different PID
        local fakePid = currentPid + 1000 -- Fake PID that doesn't exist
        local expectedPort = 8080
        createServerDetailsFile(currentWorkspace, expectedPort, fakePid)

        local result = persistence.getServerDetailsForSameWorkspace()

        assert.are.equal(type(result), 'table')
        assert.are.equal(type(result.details), 'table')
        assert.are.equal(result.details.port, expectedPort)
        assert.are.equal(result.details.workspace, currentWorkspace)
        assert.are.equal(result.details.pid, fakePid)
        assert.are.equal(type(result.isActive), 'boolean')
      end
    )

    it('should return isActive=true when process is active', function()
      -- This is hard to test with a real active process, so we'll test the logic
      -- by creating a file with current PID (which should be active)
      local filename =
        createServerDetailsFile(currentWorkspace, 8080, currentPid)

      local result = persistence.getServerDetailsForSameWorkspace()

      assert.are.equal(type(result), 'table')
      assert.are.equal(type(result.details), 'table')
      assert.are.equal(result.details.workspace, currentWorkspace)
      assert.are.equal(result.isActive, true)
    end)

    it('should return isActive=false when process is not active', function()
      -- Create a server details file with a fake PID (which should not be active)
      local fakePid = 1 -- System PID that's unlikely to exist or be nvim
      local filename = createServerDetailsFile(currentWorkspace, 8080, fakePid)

      local result = persistence.getServerDetailsForSameWorkspace()

      assert.are.equal(type(result), 'table')
      assert.are.equal(type(result.details), 'table')
      assert.are.equal(result.details.workspace, currentWorkspace)
      assert.are.equal(result.isActive, false)
    end)
  end)
end)
