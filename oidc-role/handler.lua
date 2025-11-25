local OidcHandler = {
  VERSION  = "1.0.0",
  PRIORITY = 1000,
}
local utils   = require("kong.plugins.oidc-role.utils")
local filter  = require("kong.plugins.oidc-role.filter")
local session = require("kong.plugins.oidc-role.session")
local cjson = require("cjson")

function OidcHandler:access(config)
  ngx.log(ngx.DEBUG, "[oidc-role] effective config → ", cjson.encode(config))
  local oidcConfig = utils.get_options(config, ngx)
  ngx.log(ngx.DEBUG, "[oidc-role] access() start, uri=", ngx.var.request_uri)
  if oidcConfig.skip_already_auth_requests and kong.client.get_credential() then
    ngx.log(ngx.DEBUG, "[oidc-role] skipping already authenticated request")
    return
  end

  if filter.shouldProcessRequest(oidcConfig) then
    ngx.log(ngx.DEBUG, "[oidc-role] shouldProcessRequest → true")
    session.configure(config)
    handle(oidcConfig)
  else
    ngx.log(ngx.DEBUG, "[oidc-role] shouldProcessRequest → false, uri=", ngx.var.request_uri)
  end

  ngx.log(ngx.DEBUG, "[oidc-role] access() done")
end

-- helper to get nested values from a table via “a.b.c” paths
local function get_nested(tbl, path)
  local cur = tbl
  for key in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then
      return nil
    end
    cur = cur[key]
  end
  return cur
end

--─── consumer mapping helper ───────────────────────────────────────────
local function map_consumer(oidcConfig, response)
  ngx.log(ngx.DEBUG, "[oidc-role] map_consumer() begin")
  if not (oidcConfig.consumer_claim and oidcConfig.consumer_by) then
    ngx.log(ngx.DEBUG, "[oidc-role] no consumer_claim/consumer_by configured, skipping map_consumer")
    return
  end

  ngx.log(ngx.DEBUG, "[oidc-role] consumer_claim=", oidcConfig.consumer_claim,
                     " consumer_by=", oidcConfig.consumer_by)

  -- 1) pull out the claim (supports deep paths like "realm_access.roles")
  local claim_val = get_nested(response, oidcConfig.consumer_claim)
  ngx.log(ngx.DEBUG, "[oidc-role] token claim[", oidcConfig.consumer_claim, "] = ", tostring(claim_val))
  if not claim_val then
    ngx.log(ngx.WARN,  "[oidc-role] claim value is nil, cannot map consumer")
    return
  end

  -- 2) build a list of candidates (single-value or array)
  local candidates = {}
  if type(claim_val) == "table" then
    for _, v in ipairs(claim_val) do
      table.insert(candidates, v)
    end

    -- 2a) prioritize the role matching the request path (e.g. "/lob1" → "lob1-user")
    local seg = ngx.var.request_uri:match("^/([^/]+)")
    if seg then
      local desired = seg .. "-user"
      for i, role in ipairs(candidates) do
        if role == desired then
          table.remove(candidates, i)
          table.insert(candidates, 1, role)
          ngx.log(ngx.DEBUG, "[oidc-role] prioritized role → ", desired)
          break
        end
      end
    end
  else
    table.insert(candidates, claim_val)
  end

  -- 3) try each candidate in order
  for _, claim_item in ipairs(candidates) do
    local consumer, err
    local field = oidcConfig.consumer_by

    if field == "username" then
      consumer, err = kong.db.consumers:select_by_username(claim_item)
    elseif field == "custom_id" then
      consumer, err = kong.db.consumers:select_by_custom_id(claim_item)
    elseif field == "id" then
      consumer, err = kong.db.consumers:select({ id = claim_item })
    else
      ngx.log(ngx.ERR, "[oidc-role] unsupported consumer_by=", field)
      return
    end

    if err then
      ngx.log(ngx.ERR, "[oidc-role] error selecting consumer by ", field, ": ", err)
      return
    elseif consumer then
      ngx.log(ngx.DEBUG, "[oidc-role] mapped to consumer id=", consumer.id,
                         " username=", consumer.username,
                         " custom_id=", consumer.custom_id)
      return kong.client.authenticate(consumer, nil)
    else
      ngx.log(ngx.DEBUG, "[oidc-role] no consumer found for ", field, "=", claim_item, ", trying next")
    end
  end

  ngx.log(ngx.WARN, "[oidc-role] map_consumer(): no matching consumer for any claim value")
end

--─── main handler ────────────────────────────────────────────────────────────
function handle(oidcConfig)
  ngx.log(ngx.DEBUG, "[oidc-role] handle() start")

  -- 1) Bearer JWT
  if oidcConfig.bearer_jwt_auth_enable then
    ngx.log(ngx.DEBUG, "[oidc-role] branch=verify_bearer_jwt")
    local resp = verify_bearer_jwt(oidcConfig)
    if resp then
      ngx.log(ngx.DEBUG, "[oidc-role] verify_bearer_jwt → success")
      utils.setCredentials(resp)
      utils.injectGroups(resp, oidcConfig.groups_claim)
      utils.injectHeaders(oidcConfig.header_names, oidcConfig.header_claims, {resp})
      if not oidcConfig.disable_userinfo_header then
        utils.injectUser(resp, oidcConfig.userinfo_header_name)
      end
      map_consumer(oidcConfig, resp)
      ngx.log(ngx.DEBUG, "[oidc-role] handle() end (bearer_jwt)")
      return
    end
    ngx.log(ngx.DEBUG, "[oidc-role] verify_bearer_jwt → no token or invalid")
  end

  -- 2) Introspection
  if oidcConfig.introspection_endpoint then
    ngx.log(ngx.DEBUG, "[oidc-role] branch=introspect")
    local resp = introspect(oidcConfig)
    if resp then
      ngx.log(ngx.DEBUG, "[oidc-role] introspect → success")
      utils.setCredentials(resp)
      utils.injectGroups(resp, oidcConfig.groups_claim)
      utils.injectHeaders(oidcConfig.header_names, oidcConfig.header_claims, {resp})
      if not oidcConfig.disable_userinfo_header then
        utils.injectUser(resp, oidcConfig.userinfo_header_name)
      end
      map_consumer(oidcConfig, resp)
      ngx.log(ngx.DEBUG, "[oidc-role] handle() end (introspect)")
      return
    end
    ngx.log(ngx.DEBUG, "[oidc-role] introspect → no token or invalid")
  end

  -- 3) Code flow
  ngx.log(ngx.DEBUG, "[oidc-role] branch=make_oidc")
  local full = make_oidc(oidcConfig)
  if full then
    ngx.log(ngx.DEBUG, "[oidc-role] authenticate() → success")
    local cred = full.user or full.id_token
    utils.setCredentials(cred)
    if full.user and full.user[oidcConfig.groups_claim] then
      utils.injectGroups(full.user, oidcConfig.groups_claim)
    elseif full.id_token then
      utils.injectGroups(full.id_token, oidcConfig.groups_claim)
    end
    utils.injectHeaders(oidcConfig.header_names, oidcConfig.header_claims, {full.user, full.id_token})
    if not oidcConfig.disable_userinfo_header and full.user then
      utils.injectUser(full.user, oidcConfig.userinfo_header_name)
    end
    if not oidcConfig.disable_access_token_header and full.access_token then
      utils.injectAccessToken(full.access_token, oidcConfig.access_token_header_name, oidcConfig.access_token_as_bearer)
    end
    if not oidcConfig.disable_id_token_header and full.id_token then
      utils.injectIDToken(full.id_token, oidcConfig.id_token_header_name)
    end

    map_consumer(oidcConfig, cred)
    ngx.log(ngx.DEBUG, "[oidc-role] handle() end (code flow)")
    return
  end

  ngx.log(ngx.DEBUG, "[oidc-role] handle() end (no response)")
end


--─── helper functions below unchanged ───────────────────────────────────────

function make_oidc(oidcConfig)
  ngx.log(ngx.DEBUG, "[oidc-role] make_oidc() calling authenticate: ", ngx.var.request_uri)
  local action = (oidcConfig.unauth_action ~= "auth") and "deny" or "auth"
  local res, err = require("resty.openidc").authenticate(oidcConfig, ngx.var.request_uri, action)
  if err then
    if err == "unauthorized request" then
      return kong.response.error(ngx.HTTP_UNAUTHORIZED)
    end
    if oidcConfig.recovery_page_path then
      ngx.log(ngx.DEBUG, "[oidc-role] redirect to recovery: ", oidcConfig.recovery_page_path)
      ngx.redirect(oidcConfig.recovery_page_path)
    end
    return kong.response.error(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end
  return res
end


function introspect(oidcConfig)
  if utils.has_bearer_access_token() or oidcConfig.bearer_only == "yes" then
    ngx.log(ngx.DEBUG, "[oidc-role] introspect() verifying bearer token")
    local res, err = (oidcConfig.use_jwks == "yes")
      and require("resty.openidc").bearer_jwt_verify(oidcConfig)
      or require("resty.openidc").introspect(oidcConfig)
    if err then
      ngx.log(ngx.WARN, "[oidc-role] introspect error: ", err)
      if oidcConfig.bearer_only == "yes" then
        ngx.header["WWW-Authenticate"] = 'Bearer realm="'..oidcConfig.realm..'",error="'..err..'"'
        return kong.response.error(ngx.HTTP_UNAUTHORIZED)
      end
      return nil
    end
    ngx.log(ngx.DEBUG, "[oidc-role] introspect() success")
    return res
  end
  return nil
end


function verify_bearer_jwt(oidcConfig)
  if not utils.has_bearer_access_token() then
    ngx.log(ngx.DEBUG, "[oidc-role] verify_bearer_jwt() no bearer token")
    return nil
  end
  ngx.log(ngx.DEBUG, "[oidc-role] verify_bearer_jwt() start")
  -- ... rest unchanged ...
  local json, err = require("resty.openidc").bearer_jwt_verify({
    accept_none_alg                   = false,
    accept_unsupported_alg            = false,
    token_signing_alg_values_expected = oidcConfig.bearer_jwt_auth_signing_algs,
    discovery                         = oidcConfig.discovery,
    timeout                           = oidcConfig.timeout,
    ssl_verify                        = oidcConfig.ssl_verify,
  }, {
    iss = require("resty.jwt-validators").equals(oidcConfig.discovery),
    sub = require("resty.jwt-validators").required(),
    aud = function(val) return utils.has_common_item(val, oidcConfig.client_id) end,
    exp = require("resty.jwt-validators").is_not_expired(),
    iat = require("resty.jwt-validators").required(),
    nbf = require("resty.jwt-validators").opt_is_not_before(),
  })
  if err then
    ngx.log(ngx.ERR, "[oidc-role] bearer_jwt_verify failed: ", err)
    return nil
  end
  ngx.log(ngx.DEBUG, "[oidc-role] bearer_jwt_verify() success")
  return json
end


return OidcHandler
