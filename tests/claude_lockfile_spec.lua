local lockfile = require('gemini.claude.lockfile')
local uv = vim.loop

describe('claude lockfile', function()
  local tmpRoot = '/tmp/ngc-claude-lockfile-test'
  local originalConfigDir = vim.env.CLAUDE_CONFIG_DIR

  before_each(function()
    vim.env.CLAUDE_CONFIG_DIR = tmpRoot
    vim.fn.delete(tmpRoot, 'rf')
  end)

  after_each(function()
    vim.env.CLAUDE_CONFIG_DIR = originalConfigDir
    vim.fn.delete(tmpRoot, 'rf')
  end)

  it('resolves the lock dir under CLAUDE_CONFIG_DIR', function()
    assert.are.equal(tmpRoot .. '/ide', lockfile.get_lock_dir())
  end)

  it('generates a 32-char lowercase-hex auth token', function()
    local token = lockfile.generate_auth_token()
    assert.are.equal(32, #token)
    assert.is_truthy(token:match('^[0-9a-f]+$'))
    -- Two tokens should differ.
    assert.are_not.equal(token, lockfile.generate_auth_token())
  end)

  it('includes the cwd in workspace folders', function()
    local folders = lockfile.get_workspace_folders()
    assert.is_true(#folders >= 1)
    assert.are.equal(vim.fn.getcwd(), folders[1])
  end)

  it('creates a lock file with the expected content', function()
    local token = 'abcdef0123456789abcdef0123456789'
    local ok, path = lockfile.create(54321, token)
    assert.is_true(ok)
    assert.are.equal(tmpRoot .. '/ide/54321.lock', path)

    local data = lockfile.read(54321)
    assert.is_not_nil(data)
    assert.are.equal('ws', data.transport)
    assert.are.equal('Neovim', data.ideName)
    assert.are.equal(token, data.authToken)
    assert.are.equal(vim.fn.getpid(), data.pid)
    assert.is_true(#data.workspaceFolders >= 1)
  end)

  it('rejects an invalid (too-short) auth token', function()
    local ok, err = lockfile.create(54321, 'short')
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find('auth token'))
  end)

  it('removes a lock file', function()
    local token = 'abcdef0123456789abcdef0123456789'
    lockfile.create(54321, token)
    assert.is_not_nil(uv.fs_stat(tmpRoot .. '/ide/54321.lock'))
    assert.is_true(lockfile.remove(54321))
    assert.is_nil(uv.fs_stat(tmpRoot .. '/ide/54321.lock'))
  end)

  it('returns nil when reading a non-existent lock', function()
    assert.is_nil(lockfile.read(11111))
  end)
end)
