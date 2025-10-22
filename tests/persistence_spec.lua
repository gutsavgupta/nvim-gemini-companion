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
      'should return a path with the correct format including current PID',
      function()
        local path = persistence.getServerDetailsPath()
        local expectedPattern = '/tmp/nvim%-gemini%-companion%-'
          .. currentPid
          .. '%.json'

        assert.are.equal(type(path), 'string')
        assert.truthy(
          string.match(path, expectedPattern),
          'Path does not match expected pattern: ' .. path
        )
      end
    )

    it('should return different paths for different nvim instances', function()
      local path = persistence.getServerDetailsPath()
      local pidPattern = '/tmp/nvim%-gemini%-companion%-(%d+)%.json'
      local foundPid = string.match(path, pidPattern)

      assert.are.equal(tonumber(foundPid), currentPid)
    end)
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

  describe('getStaleServerDetail', function()
    -- Helper function to create a fake stale server file
    local function createStaleServerFile(pid, port, workspace, timestamp)
      local filename = string.format('/tmp/nvim-gemini-companion-%d.json', pid)
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

    it('should return nil when no stale files exist', function()
      local result = persistence.getStaleServerDetail()
      assert.are.equal(result, nil)
    end)

    it(
      'should return nil when there are files but none match current workspace',
      function()
        -- Create a stale file with different workspace
        local differentWorkspace = '/tmp/different-workspace'
        if currentWorkspace == differentWorkspace then
          differentWorkspace = '/tmp/another-workspace'
        end
        createStaleServerFile(1111, 8080, differentWorkspace)

        local result = persistence.getStaleServerDetail()
        assert.are.equal(result, nil)
      end
    )

    it(
      'should return stale server details when there is a stale file with matching workspace',
      function()
        -- Create a stale server file with the current workspace and a different PID
        local fakePid = currentPid + 1000 -- Fake PID that doesn't exist
        local expectedPort = 8080
        createStaleServerFile(fakePid, expectedPort, currentWorkspace)

        local result = persistence.getStaleServerDetail()

        assert.are.equal(type(result), 'table')
        assert.are.equal(result.port, expectedPort)
        assert.are.equal(result.workspace, currentWorkspace)
        assert.are.equal(result.pid, fakePid)
      end
    )

    it('should remove the stale file after returning its details', function()
      -- Create a stale server file with the current workspace and a different PID
      local fakePid = currentPid + 2000 -- Fake PID that doesn't exist
      local filename = createStaleServerFile(fakePid, 9090, currentWorkspace)

      -- Verify file exists before calling the function
      assert.truthy(uv.fs_stat(filename), 'Test file was not created')

      local result = persistence.getStaleServerDetail()

      -- Verify that the function returned the data
      assert.truthy(result, 'Function should have returned stale details')
      assert.are.equal(result.pid, fakePid)

      -- Verify that the file has been removed
      assert.falsy(uv.fs_stat(filename), 'Stale file should have been removed')
    end)

    it(
      'should not return details for a file with the same PID as current process',
      function()
        -- Create a server file with the current PID (should not be considered stale)
        createStaleServerFile(currentPid, 7070, currentWorkspace)

        local result = persistence.getStaleServerDetail()
        assert.are.equal(result, nil)
      end
    )
  end)
end)
