local tools = require('gemini.claude.tools')

describe('claude tools', function()
  -- Capture the (result, err) a handler responds with.
  local function capture()
    local box = {}
    box.respond = function(result, err)
      box.result = result
      box.err = err
      box.called = true
    end
    return box
  end

  describe('get_tool_list', function()
    it('advertises the expected Claude tools', function()
      local list = tools.get_tool_list()
      local names = {}
      for _, t in ipairs(list) do
        names[t.name] = true
        assert.is_truthy(t.description)
        assert.is_truthy(t.inputSchema)
      end
      for _, expected in ipairs({
        'openDiff',
        'openFile',
        'getCurrentSelection',
        'getDiagnostics',
        'getOpenEditors',
        'getWorkspaceFolders',
        'checkDocumentDirty',
        'saveDocument',
        'closeAllDiffTabs',
      }) do
        assert.is_true(names[expected] == true, 'missing tool: ' .. expected)
      end
    end)
  end)

  describe('invoke', function()
    it('returns method-not-found for an unknown tool', function()
      local box = capture()
      tools.invoke('nope', {}, nil, box.respond)
      assert.is_nil(box.result)
      assert.are.equal(-32601, box.err.code)
    end)

    it('getWorkspaceFolders returns a content array of folders', function()
      local box = capture()
      tools.invoke('getWorkspaceFolders', {}, nil, box.respond)
      assert.is_not_nil(box.result)
      assert.is_not_nil(box.result.content)
      local decoded = vim.json.decode(box.result.content[1].text)
      assert.is_true(#decoded.folders >= 1)
    end)

    it('getDiagnostics returns a diagnostics array', function()
      local box = capture()
      tools.invoke('getDiagnostics', {}, nil, box.respond)
      local decoded = vim.json.decode(box.result.content[1].text)
      assert.is_not_nil(decoded.diagnostics)
    end)

    it('checkDocumentDirty reports not-open for an unknown file', function()
      local box = capture()
      tools.invoke(
        'checkDocumentDirty',
        { filePath = '/nonexistent/file.xyz' },
        nil,
        box.respond
      )
      local decoded = vim.json.decode(box.result.content[1].text)
      assert.is_false(decoded.success)
    end)
  end)

  describe('openDiff (blocking)', function()
    local diff = require('gemini.ideDiffManager')
    local originalOpen = diff.open

    after_each(function() diff.open = originalOpen end)

    it('responds FILE_SAVED + content on accept', function()
      diff.open = function(_, _, onClose)
        onClose('final content', 'accepted')
      end
      local box = capture()
      tools.invoke('openDiff', {
        old_file_path = '/tmp/a.txt',
        new_file_path = '/tmp/a.txt',
        new_file_contents = 'final content',
        tab_name = 'a.txt',
      }, { id = 'client_1' }, box.respond)

      assert.is_true(box.called)
      assert.are.equal('FILE_SAVED', box.result.content[1].text)
      assert.are.equal('final content', box.result.content[2].text)
    end)

    it('responds DIFF_REJECTED on reject', function()
      diff.open = function(_, _, onClose)
        onClose('whatever', 'rejected')
      end
      local box = capture()
      tools.invoke('openDiff', {
        old_file_path = '/tmp/a.txt',
        new_file_path = '/tmp/a.txt',
        new_file_contents = 'x',
        tab_name = 'a.txt',
      }, { id = 'client_1' }, box.respond)

      assert.is_true(box.called)
      assert.are.equal('DIFF_REJECTED', box.result.content[1].text)
    end)

    it('rejects missing required params', function()
      local box = capture()
      tools.invoke('openDiff', { tab_name = 'x' }, { id = 'c' }, box.respond)
      assert.is_nil(box.result)
      assert.are.equal(-32602, box.err.code)
    end)
  end)
end)
