local OidcHandler = {
  VERSION = "2.0.0",
  PRIORITY = 1000,
}

local utils = require("kong.plugins.oidc-role.utils")
local filter = require("kong.plugins.oidc-role.filter")
local session = require("kong.plugins.oidc-role.session")
local openidc = require("resty.openidc")
local validators = require("resty.jwt-validators")

local function error_response(status, message)
  local headers
  if status == 401 then
    headers = { ["WWW-Authenticate"] = 'Bearer realm="kong"' }
  end

  local public_message = message or "Request denied"
  if status >= 500 then
    public_message = "Internal Server Error"
  end

  return kong.response.exit(status, { message = public_message }, headers)
end

local function get_identity(claims, config)
  local principal = utils.get_claim(claims, config.principal_claim)
  if config.require_principal and (principal == nil or principal == "") then
    return nil, "required principal claim is missing", 401
  end

  return {
    id = principal or utils.get_claim(claims, "sub"),
    username = utils.get_claim(claims, config.username_claim),
  }
end

local function establish_context(claims, config)
  local identity, err, status = get_identity(claims, config)
  if not identity then
    return nil, err, status
  end

  local groups = utils.collect_claim_values(claims, config.authorization_claims)
  if config.require_authorization_claim and #groups == 0 then
    return nil, "required authorization claims are missing", 403
  end

  utils.clear_trusted_headers(config)
  utils.set_credentials(identity)
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
      return nil, "consumer lookup failed", 500
    end

    if consumer then
      kong.client.authenticate(consumer, nil)
      return true
    end
  end

  if config.consumer_mapping_required then
    return nil, "no matching Kong consumer", 403
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
    return nil, "missing bearer token", 401
  end

  local validation = {
    exp = validators.is_not_expired(),
    iat = validators.required(),
    nbf = validators.opt_is_not_before(),
  }

  if config.require_principal
      and type(config.principal_claim) == "string"
      and not config.principal_claim:find(".", 1, true) then
    validation[config.principal_claim] = validators.required()
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
    return nil, "invalid bearer token", 401
  end

  local ok, claim_err = validate_claims(claims, config)
  if not ok then
    return nil, claim_err, 401
  end

  return claims
end

local function introspect(config)
  if not utils.has_bearer_access_token() then
    return nil, "missing bearer token", 401
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
    return nil, "invalid bearer token", 401
  end

  local ok, claim_err = validate_claims(claims, config)
  if not ok then
    return nil, claim_err, 401
  end

  return claims
end

local function authorization_code(config)
  local configured, session_err = session.configure(config)
  if not configured then
    return nil, session_err, 500
  end

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
    return nil, "authentication failed", 401
  end

  local claims = result.user or result.id_token
  if not claims then
    return nil, "identity claims missing", 401
  end

  local ok, claim_err = validate_claims(claims, config)
  if not ok then
    return nil, claim_err, 401
  end

  return claims, nil, nil, result
end

local function authenticate(config)
  if config.auth_mode == "jwt" then
    return verify_jwt(config)
  elseif config.auth_mode == "introspection" then
    return introspect(config)
  elseif config.auth_mode == "authorization_code" then
    return authorization_code(config)
  end

  return nil, "unsupported authentication mode", 500
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

  local claims, err, status, auth_result = authenticate(options)
  if not claims then
    return error_response(status or 401, err)
  end

  local groups, context_err, context_status = establish_context(claims, options)
  if not groups then
    return error_response(context_status or 401, context_err)
  end

  if auth_result then
    if options.expose_access_token and auth_result.access_token then
      utils.inject_access_token(auth_result.access_token, options.access_token_header_name)
    end
    if options.expose_id_token and auth_result.id_token then
      utils.inject_json_header(auth_result.id_token, options.id_token_header_name)
    end
  end

  local ok, mapping_err, mapping_status = map_consumer_legacy(claims, options)
  if not ok then
    return error_response(mapping_status or 403, mapping_err)
  end
end

return OidcHandler
