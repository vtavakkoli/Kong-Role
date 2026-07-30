local test_env = require "spec.support.test_env"

local env
local openidc
local handler

local function install_dependencies()
  test_env.install_constants()

  openidc = {
    bearer_jwt_verify = function()
      return env.jwt_claims, env.jwt_error
    end,
    introspect = function()
      return env.introspection_claims, env.introspection_error
    end,
    authenticate = function()
      return env.authorization_result, env.authorization_error
    end,
  }

  package.preload["resty.openidc"] = function()
    return openidc
  end
  package.preload["resty.jwt-validators"] = function()
    return {
      is_not_expired = function() return function() return true end end,
      required = function() return function(value) return value ~= nil end end,
      opt_is_not_before = function() return function() return true end end,
    }
  end
end

local function load_handler()
  package.loaded["kong.plugins.oidc-role.utils"] = nil
  package.loaded["kong.plugins.oidc-role.filter"] = nil
  package.loaded["kong.plugins.oidc-role.session"] = nil
  package.loaded["kong.plugins.oidc-role.handler"] = nil
  package.loaded["resty.openidc"] = nil
  package.loaded["resty.jwt-validators"] = nil
  install_dependencies()
  return require "kong.plugins.oidc-role.handler"
end

local function find_authentication_with_consumer()
  for _, call in ipairs(env.calls) do
    if call.name == "authenticate" and call.consumer ~= nil then
      return call
    end
  end
end

describe("oidc-role handler", function()
  before_each(function()
    reset_oidc_role_modules()
    env = test_env.new()
    env.jwt_claims = test_env.valid_claims()
    env.introspection_claims = test_env.valid_claims({ active = true })
    env.authorization_result = {
      user = test_env.valid_claims(),
      access_token = "access-token",
      id_token = test_env.valid_claims(),
    }
    _G.kong = env.kong
    _G.ngx = env.ngx
    handler = load_handler()
  end)

  it("authenticates a JWT and propagates all authorization groups", function()
    local result = handler:access(test_env.base_config())
    assert.is_nil(result)
    assert.same(
      { "department-gat1", "invoice-reader", "invoice-writer", "offline_access" },
      env.kong.ctx.shared.authenticated_groups
    )
    assert.equals("vahid", env.headers["X-Credential-Identifier"])
    assert.is_nil(env.headers["X-UserInfo"])
    assert.is_nil(env.headers["X-Access-Token"])
  end)

  it("clears spoofed headers before injecting allowlisted claims", function()
    env.headers["X-Subject"] = "attacker"
    local config = test_env.base_config({
      header_names = { "X-Subject" },
      header_claims = { "sub" },
    })
    handler:access(config)
    assert.equals("user-123", env.headers["X-Subject"])
  end)

  it("returns 401 when a bearer token is missing", function()
    env.authorization = nil
    local result = handler:access(test_env.base_config())
    assert.equals(401, result.status)
    assert.equals("missing bearer token", result.body.message)
  end)

  it("returns 401 for a token with the wrong issuer", function()
    env.jwt_claims.iss = "https://attacker.example"
    local result = handler:access(test_env.base_config())
    assert.equals(401, result.status)
    assert.equals("invalid issuer", result.body.message)
  end)

  it("returns 401 for a token with the wrong audience", function()
    env.jwt_claims.aud = { "account" }
    local result = handler:access(test_env.base_config())
    assert.equals(401, result.status)
    assert.equals("invalid audience", result.body.message)
  end)

  it("supports a custom principal claim without requiring sub", function()
    env.jwt_claims.sub = nil
    env.jwt_claims.client_id = "machine-client"
    local config = test_env.base_config({ principal_claim = "client_id" })
    local result = handler:access(config)
    assert.is_nil(result)
    assert.equals("machine-client", env.calls[2].credential.id)
  end)

  it("returns 403 when authorization claims are required but absent", function()
    env.jwt_claims.resource_access = nil
    env.jwt_claims.realm_access = nil
    env.jwt_claims.groups = nil
    local config = test_env.base_config({ require_authorization_claim = true })
    local result = handler:access(config)
    assert.equals(403, result.status)
  end)

  it("uses introspection mode and rejects inactive tokens", function()
    local config = test_env.base_config({ auth_mode = "introspection" })
    assert.is_nil(handler:access(config))

    env.introspection_claims = { active = false }
    local result = handler:access(config)
    assert.equals(401, result.status)
  end)

  it("supports authorization-code mode and explicit token exposure", function()
    local config = test_env.base_config({
      auth_mode = "authorization_code",
      client_secret = "client-secret",
      session_secret = "valid-secret",
      expose_access_token = true,
      expose_id_token = true,
    })
    local result = handler:access(config)
    assert.is_nil(result)
    assert.equals("decoded-session-secret", env.ngx.var.session_secret)
    assert.equals("Bearer access-token", env.headers["X-Access-Token"])
    assert.is_truthy(env.headers["X-ID-Token"]:match("^base64:"))
  end)

  it("returns 500 for an invalid authorization-code session secret", function()
    local called = false
    openidc.authenticate = function()
      called = true
    end
    local config = test_env.base_config({
      auth_mode = "authorization_code",
      client_secret = "client-secret",
      session_secret = "invalid",
    })
    local result = handler:access(config)
    assert.equals(500, result.status)
    assert.is_false(called)
  end)

  it("skips configured unauthenticated paths", function()
    env.ngx.var.uri = "/health"
    local config = test_env.base_config({ filters = "^/health" })
    local result = handler:access(config)
    assert.is_nil(result)
    assert.equals(0, #env.calls)
  end)

  it("skips processing when another plugin already authenticated", function()
    env.current_credential = { id = "existing" }
    local config = test_env.base_config({ skip_already_auth_requests = true })
    local result = handler:access(config)
    assert.is_nil(result)
    assert.equals(0, #env.calls)
  end)

  it("supports optional legacy consumer mapping", function()
    env.consumer_results["user-123"] = {
      id = "consumer-id",
      username = "consumer-user",
      custom_id = "user-123",
    }
    local config = test_env.base_config({
      legacy_consumer_mapping = true,
      consumer_claim = "sub",
      consumer_by = "custom_id",
    })
    assert.is_nil(handler:access(config))
    local call = find_authentication_with_consumer()
    assert.is_not_nil(call)
    assert.equals("consumer-id", call.consumer.id)
  end)

  it("returns 403 when required legacy consumer mapping is absent", function()
    local config = test_env.base_config({
      legacy_consumer_mapping = true,
      consumer_mapping_required = true,
    })
    local result = handler:access(config)
    assert.equals(403, result.status)
  end)
end)
