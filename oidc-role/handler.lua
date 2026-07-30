local OidcHandler = {
  VERSION = "2.0.0",
  PRIORITY = 1000,
}

local utils = require("kong.plugins.oidc-role.utils")
local filter = require("kong.plugins.oidc-role.filter")
local session = require("kong.plugins.oidc-role.session")
local openidc = require("resty.openidc")
local validators = require("resty.jwt-validators")

local function unauthorized(message)
  return kong.response.exit(401, { message = message or "Unauthorized" }, {
    ["WWW-Authenticate"] = 'Bearer realm="kong"',
  })
end

local function get_identity(claims, config)
  local principal = utils.get_claim(claims, config.principal_claim)
  if config.require_principal and (principal == nil or principal == "") then
    return nil, "required principal claim is missing"
  end

  return {
    id = principal or utils.get_claim(claims, "sub"),
    username = utils.get_claim(claims, config.username_claim),
  }
end

local function establish_context(claims, config)
  local identity, err = get_identity(claims, config)
  if not identity then
    return nil, err
  end

  utils.set_credentials(identity)
  utils.clear_trusted_headers(config)

  local groups = utils.collect_claim_values(claims, config.authorization_claims)
  if config.require_authorization_claim and #groups == 0 then
    return nil, "required authorization claims are missing"
  end

  kong.ctx.shared.authenticated_groups = groups
  utils.inject_allowlisted_headers(config.header_names, config.header_claims, claims)

  if config.expose_userinfo then
    utils.inject_json_header(claims, config.userinfo_header_name)
  end

  return groups
end

local function map_consumer_legacy(claims, config)
  if not config.legacy_consumer_mapping then
    return true
  end

  local value = utils.get_claim(claims, config.consumer_claim)
  local candidates = utils.as_string_list(value)

  for _, item in ipairs(candidates) do
    local consumer, err
    if config.consumer_by == "username" then
      consumer, err = kong.db.consumers:select_by_username(item)
    elseif config.consumer_by == "custom_id" then
      consumer, err = kong.db.consumers:select_by_custom_id(item)
    elseif config.consumer_by == "id" then
      consumer, err = kong.db.consumers:select({ id = item })
    end

    if err then
      kong.log.err("oidc-role consumer lookup failed: ", err)
      return nil, "consumer lookup failed"
    end

    if consumer then
      kong.client.authenticate(consumer, nil)
      return true
    end
  end

  if config.consumer_mapping_required then
    return nil, "no matching Kong consumer"
  end

  return true
end

local function validate_claims(claims, config)
  local issuer = utils.get_claim(claims, "iss")
  if config.expected_issuer and issuer ~= config.expected_issuer then
    return nil, "invalid issuer"
  end

  if config.allowed_audiences and #config.allowed_audiences > 0 then
    if not utils.has_common_item(utils.get_claim(claims, "aud"), config.allowed_audiences) then
      return nil, "invalid audience"
    end
  end

  return true
end

local function verify_jwt(config)
  if not utils.has_bearer_access_token() then
    return nil, "missing bearer token"
  end

  local validation = {
    exp = validators.is_not_expired(),
    iat = validators.required(),
    nbf = validators.opt_is_not_before(),
  }

  if config.require_principal then
    validation.sub = validators.required()
  end

  local claims, err = openidc.bearer_jwt_verify({
    accept_none_alg = false,
    accept_unsupported_alg = false,
    token_signing_alg_values_expected = config.allowed_signing_algorithms,
    discovery = config.discovery,
    timeout = config.timeout,
    ssl_verify = config.ssl_verify and "yes" or "no",
    proxy_opts = config.proxy_opts,
  }, validation)

  if err or not claims then
    kong.log.warn("oidc-role JWT validation failed: ", err or "unknown error")
    return nil, "invalid bearer token"
  end

  local ok, claim_err = validate_claims(claims, config)
  if not ok then
    return nil, claim_err
  end

  return claims
end

local function introspect(config)
  if not utils.has_bearer_access_token() then
    return nil, "missing bearer token"
  end

  local claims, err = openidc.introspect({
    client_id = config.client_id,
    client_secret = config.client_secret,
    introspection_endpoint = config.introspection_endpoint,
    introspection_endpoint_auth_method = config.introspection_endpoint_auth_method,
    timeout = config.timeout,
    ssl_verify = config.ssl_verify and "yes" or "no",
    proxy_opts = config.proxy_opts,
  })

  if err or not claims or claims.active == false then
    kong.log.warn("oidc-role token introspection failed: ", err or "inactive token")
    return nil, "invalid bearer token"
  end

  local ok, claim_err = validate_claims(claims, config)
  if not ok then
    return nil, claim_err
  end

  return claims
end

local function authorization_code(config)
  session.configure(config)
  local result, err = openidc.authenticate({
    client_id = config.client_id,
    client_secret = config.client_secret,
    discovery = config.discovery,
    redirect_uri = config.redirect_uri or utils.get_redirect_uri(ngx),
    scope = config.scope,
    response_type = config.response_type,
    ssl_verify = config.ssl_verify and "yes" or "no",
    timeout = config.timeout,
    proxy_opts = config.proxy_opts,
  }, ngx.var.request_uri, config.unauth_action == "auth" and "auth" or "deny")

  if err or not result then
    kong.log.warn("oidc-role authorization-code flow failed: ", err or "unknown error")
    return nil, "authentication failed"
  end

  local claims = result.user or result.id_token
  if not claims then
    return nil, "identity claims missing"
  end

  if config.expose_access_token and result.access_token then
    utils.inject_access_token(result.access_token, config.access_token_header_name)
  end
  if config.expose_id_token and result.id_token then
    utils.inject_json_header(result.id_token, config.id_token_header_name)
  end

  return claims
end

local function authenticate(config)
  if config.auth_mode == "jwt" then
    return verify_jwt(config)
  elseif config.auth_mode == "introspection" then
    return introspect(config)
  elseif config.auth_mode == "authorization_code" then
    return authorization_code(config)
  end

  return nil, "unsupported authentication mode"
end

function OidcHandler:access(config)
  local options = utils.get_options(config, ngx)

  if not filter.shouldProcessRequest(options) then
    return
  end

  if options.skip_already_auth_requests and kong.client.get_credential() then
    return
  end

  kong.log.debug("oidc-role started; mode=", options.auth_mode,
                 ", discovery=", options.discovery)

  local claims, err = authenticate(options)
  if not claims then
    return unauthorized(err)
  end

  local groups, context_err = establish_context(claims, options)
  if not groups then
    return unauthorized(context_err)
  end

  local ok, mapping_err = map_consumer_legacy(claims, options)
  if not ok then
    return unauthorized(mapping_err)
  end
end

return OidcHandler
