local utils = require "kong.plugins.oidc-role.utils"

describe("oidc-role utilities", function()
  it("extracts nested claims", function()
    local claims = { realm_access = { roles = { "reader", "writer" } } }
    assert.same({ "reader", "writer" }, utils.get_claim(claims, "realm_access.roles"))
  end)

  it("collects and deduplicates authorization claims", function()
    local claims = {
      realm_access = { roles = { "reader", "writer" } },
      groups = { "reader", "department-gat1" },
    }
    assert.same(
      { "department-gat1", "reader", "writer" },
      utils.collect_claim_values(claims, { "realm_access.roles", "groups" })
    )
  end)

  it("matches string and array audiences", function()
    assert.is_true(utils.has_common_item("kong", { "kong", "other" }))
    assert.is_true(utils.has_common_item({ "account", "kong" }, { "kong" }))
    assert.is_false(utils.has_common_item({ "account" }, { "kong" }))
  end)
end)
