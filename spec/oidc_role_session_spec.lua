local test_env = require "spec.support.test_env"
local session
local env

describe("oidc-role session configuration", function()
  before_each(function()
    reset_oidc_role_modules()
    env = test_env.new()
    _G.kong = env.kong
    _G.ngx = env.ngx
    session = load_plugin_file("oidc-role/session.lua")
  end)

  it("accepts configurations without a session secret", function()
    local ok, err = session.configure({})
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("decodes and installs a valid session secret", function()
    local ok, err = session.configure({ session_secret = "valid-secret" })
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equals("decoded-session-secret", env.ngx.var.session_secret)
  end)

  it("rejects invalid base64 session secrets", function()
    local ok, err = session.configure({ session_secret = "invalid" })
    assert.is_nil(ok)
    assert.equals("invalid session secret", err)
    assert.equals("err", env.calls[1].name)
  end)
end)
