local schema

local function config_fields_by_name(value)
  local fields = {}
  for _, entry in ipairs(value.fields[3].config.fields) do
    for name, definition in pairs(entry) do
      fields[name] = definition
    end
  end
  return fields
end

describe("oidc-role schema", function()
  before_each(function()
    reset_oidc_role_modules()
    package.preload["kong.db.schema.typedefs"] = function()
      return {
        no_consumer = { type = "foreign", reference = "consumers" },
        protocols_http = { type = "set", default = { "http", "https" } },
      }
    end
    schema = load_plugin_file("oidc-role/schema.lua")
  end)

  it("uses JWT mode and secure transport defaults", function()
    local fields = config_fields_by_name(schema)
    assert.equals("jwt", fields.auth_mode.default)
    assert.is_true(fields.ssl_verify.default)
    assert.same({ "RS256" }, fields.allowed_signing_algorithms.default)
  end)

  it("does not expose sensitive identity material by default", function()
    local fields = config_fields_by_name(schema)
    assert.is_false(fields.expose_userinfo.default)
    assert.is_false(fields.expose_id_token.default)
    assert.is_false(fields.expose_access_token.default)
  end)

  it("separates the principal claim from authorization claims", function()
    local fields = config_fields_by_name(schema)
    assert.equals("sub", fields.principal_claim.default)
    assert.same(
      { "resource_access.kong.roles", "realm_access.roles", "groups" },
      fields.authorization_claims.default
    )
    assert.is_false(fields.legacy_consumer_mapping.default)
  end)

  it("requires mode-specific configuration through entity checks", function()
    local checks = schema.fields[3].config.entity_checks
    assert.equals("introspection", checks[1].conditional.if_match.eq)
    assert.equals("introspection_endpoint", checks[1].conditional.then_field)
    assert.equals("authorization_code", checks[2].conditional.if_match.eq)
    assert.equals("client_secret", checks[2].conditional.then_field)
  end)
end)
