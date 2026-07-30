package = "kong-plugin-oidc-role"
version = "2.0.0-1"

source = {
  url = "git://github.com/vtavakkoli/Kong-Role",
  tag = "v2.0.0",
}

description = {
  summary = "OIDC authentication and claim-based authorization for Kong Community",
  homepage = "https://github.com/vtavakkoli/Kong-Role",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "lua-resty-openidc >= 1.7.6",
}

build = {
  type = "builtin",
  modules = {
    ["kong.plugins.oidc-role.handler"] = "oidc-role/handler.lua",
    ["kong.plugins.oidc-role.schema"] = "oidc-role/schema.lua",
    ["kong.plugins.oidc-role.utils"] = "oidc-role/utils.lua",
    ["kong.plugins.oidc-role.filter"] = "oidc-role/filter.lua",
    ["kong.plugins.oidc-role.session"] = "oidc-role/session.lua",
  },
}
