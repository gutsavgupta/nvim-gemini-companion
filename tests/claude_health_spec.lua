describe('claude health checks', function()
  local health = require('gemini.health')
  local calls

  local originalHealth = vim.health

  before_each(function()
    calls = { ok = {}, warn = {}, error = {}, info = {}, start = {} }
    -- Stub vim.health so we can capture reported items without a real
    -- :checkhealth buffer. health.lua resolves `vim.health` at require time, so
    -- the module already holds a reference; patch the fields in place.
    for _, fn in ipairs({ 'ok', 'warn', 'error', 'info', 'start' }) do
      originalHealth[fn] = function(msg) table.insert(calls[fn], msg or '') end
    end
  end)

  it('claudeServerStatus runs without error', function()
    assert.has_no.errors(function() health.claudeServerStatus() end)
  end)

  it('reports claude not active when integration is off', function()
    -- In the test harness claude is not installed / not in cmds, so the
    -- integration is inactive. It should report via info (or ok fallback).
    health.claudeServerStatus()
    local reported = table.concat(calls.info, '\n')
      .. '\n'
      .. table.concat(calls.ok, '\n')
    assert.is_truthy(reported:find('Claude integration not active'))
  end)

  it('full check() includes a Claude CLI line', function()
    assert.has_no.errors(function() health.check() end)
    local all = table.concat(calls.ok, '\n')
      .. table.concat(calls.warn, '\n')
    assert.is_truthy(all:find('Claude Code CLI'))
  end)
end)
