local test_env = require "spec.support.test_env"

local utils
local env

local function contains(list, expected)
  for _, value in ipairs(list) do
    if value == expected then
      return true
    end
  end
  return false
end

describe("oidc-role utilities", function()
  before_each(function()
    reset_oidc_role_modules()
    test_env.install_constants()
    env = test_env.new()
    _G.kong = env.kong
    _G.ngx = env.ngx
    utils = load_plugin_file("oidc-role/utils.lua")
  end)

  it("extracts nested claims and rejects invalid paths", function()
    local claims = { realm_access = { roles = { "reader", "writer" } } }
    assert.same({ "reader", "writer" }, utils.get_claim(claims, "realm_access.roles"))
    assert.is_nil(utils.get_claim(claims, "realm_access.missing"))
    assert.is_nil(utils.get_claim(nil, "sub"))
    assert.is_nil(utils.get_claim(claims, ""))
  end)

  it("normalizes string lists and ignores non-string values", function()
    assert.same({ "reader" }, utils.as_string_list("reader"))
    assert.same({ "reader", "writer" }, utils.as_string_list({ "reader", 42, "writer" }))
    assert.same({}, utils.as_string_list(false))
  end)

  it("collects, sorts, and deduplicates authorization claims", function()
    local claims = {
      realm_access = { roles = { "reader", "writer" } },
      groups = { "reader", "department-gat1" },
    }
    assert.same(
      { "department-gat1", "reader", "writer" },
      utils.collect_claim_values(claims, { "realm_access.roles", "groups" })
    )
  end)

  it("builds a safe redirect URI without query parameters", function()
    env.ngx.var.request_uri = "/callback?code=abc"
    assert.equals("/callback", utils.get_redirect_uri(env.ngx))
    env.ngx.var.request_uri = "/"
    assert.equals("/cb", utils.get_redirect_uri(env.ngx))
  end)

  it("normalizes options, filters, defaults, and proxy settings", function()
    local config = test_env.base_config({
      filters = "^/health,^/metrics",
      ignore_auth_filters = "^/ready",
      allowed_signing_algorithms = nil,
      http_proxy = "http://proxy",
    })
    local options = utils.get_options(config, env.ngx)
    assert.same({ "RS256" }, options.allowed_signing_algorithms)
    assert.same({ "^/health", "^/metrics", "^/ready" }, options.filters)
    assert.equals("http://proxy", options.proxy_opts.http_proxy)
  end)

  it("detects valid bearer headers only", function()
    env.authorization = "Bearer abc.def.ghi"
    assert.is_true(utils.has_bearer_access_token())
    env.authorization = "bearer token"
    assert.is_true(utils.has_bearer_access_token())
    env.authorization = "Basic abc"
    assert.is_false(utils.has_bearer_access_token())
    env.authorization = "Bearer   "
    assert.is_false(utils.has_bearer_access_token())
  end)

  it("matches string and array audiences", function()
    assert.is_true(utils.has_common_item("kong-api", { "kong-api", "other" }))
    assert.is_true(utils.has_common_item({ "account", "kong-api" }, { "kong-api" }))
    assert.is_false(utils.has_common_item({ "account" }, { "kong-api" }))
    assert.is_false(utils.has_common_item(nil, { "kong-api" }))
  end)

  it("clears all trusted identity headers", function()
    utils.clear_trusted_headers({
      userinfo_header_name = "X-UserInfo",
      id_token_header_name = "X-ID-Token",
      access_token_header_name = "X-Access-Token",
      header_names = { "X-Department", "X-Subject" },
    })
    assert.is_true(contains(env.cleared_headers, "X-UserInfo"))
    assert.is_true(contains(env.cleared_headers, "X-ID-Token"))
    assert.is_true(contains(env.cleared_headers, "X-Access-Token"))
    assert.is_true(contains(env.cleared_headers, "X-Department"))
    assert.is_true(contains(env.cleared_headers, "X-Subject"))
  end)

  it("establishes a credential without creating a synthetic consumer", function()
    utils.set_credentials({ id = "user-123", username = "vahid" })
    assert.equals("authenticate", env.calls[1].name)
    assert.is_nil(env.calls[1].consumer)
    assert.same({ id = "user-123", username = "vahid" }, env.calls[1].credential)
    assert.equals("vahid", env.headers["X-Credential-Identifier"])
    assert.is_true(contains(env.cleared_headers, "X-Consumer-ID"))
  end)

  it("injects only allowlisted nested claims", function()
    local claims = {
      sub = "user-123",
      department = { code = "GAT1" },
      groups = { "reader", "writer" },
    }
    utils.inject_allowlisted_headers(
      { "X-Subject", "X-Department", "X-Groups" },
      { "sub", "department.code", "groups" },
      claims
    )
    assert.equals("user-123", env.headers["X-Subject"])
    assert.equals("GAT1", env.headers["X-Department"])
    assert.equals("reader,writer", env.headers["X-Groups"])
  end)

  it("does not inject headers when configuration lengths differ", function()
    utils.inject_allowlisted_headers({ "X-Subject" }, {}, { sub = "user-123" })
    assert.is_nil(env.headers["X-Subject"])
    assert.equals("err", env.calls[1].name)
  end)

  it("injects encoded JSON and bearer access-token headers", function()
    utils.inject_json_header({ sub = "user-123" }, "X-UserInfo")
    assert.is_truthy(env.headers["X-UserInfo"]:match("^base64:"))
    utils.inject_access_token("secret-token", "X-Access-Token")
    assert.equals("Bearer secret-token", env.headers["X-Access-Token"])
  end)
end)
