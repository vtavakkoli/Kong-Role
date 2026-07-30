local filter

describe("oidc-role request filter", function()
  before_each(function()
    reset_oidc_role_modules()
    _G.ngx = { var = { uri = "/api/invoices" } }
    _G.kong = { log = { warn = function() end } }
    filter = load_plugin_file("oidc-role/filter.lua")
  end)

  it("processes requests when no filters are configured", function()
    assert.is_true(filter.shouldProcessRequest({ filters = nil }))
    assert.is_true(filter.shouldProcessRequest({ filters = {} }))
  end)

  it("skips a request matching a configured pattern", function()
    assert.is_false(filter.shouldProcessRequest({ filters = { "^/api" } }))
  end)

  it("processes a request that does not match", function()
    assert.is_true(filter.shouldProcessRequest({ filters = { "^/health", "^/metrics" } }))
  end)

  it("ignores invalid patterns instead of crashing", function()
    assert.has_no.errors(function()
      assert.is_true(filter.shouldProcessRequest({ filters = { "[" } }))
    end)
  end)
end)
