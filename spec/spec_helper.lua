local function load_plugin_file(path)
  local chunk, err = loadfile(path)
  assert(chunk, err)
  return chunk()
end

_G.load_plugin_file = load_plugin_file

local plugin_modules = {
  ["kong.plugins.oidc-role.utils"] = "oidc-role/utils.lua",
  ["kong.plugins.oidc-role.filter"] = "oidc-role/filter.lua",
  ["kong.plugins.oidc-role.session"] = "oidc-role/session.lua",
  ["kong.plugins.oidc-role.handler"] = "oidc-role/handler.lua",
  ["kong.plugins.oidc-role.schema"] = "oidc-role/schema.lua",
}

for module_name, path in pairs(plugin_modules) do
  local module_path = path
  package.preload[module_name] = function()
    return load_plugin_file(module_path)
  end
end

function _G.reset_oidc_role_modules()
  for module_name in pairs(plugin_modules) do
    package.loaded[module_name] = nil
  end
  package.loaded["resty.openidc"] = nil
  package.loaded["resty.jwt-validators"] = nil
  package.loaded["kong.constants"] = nil
  package.loaded["kong.db.schema.typedefs"] = nil
end
