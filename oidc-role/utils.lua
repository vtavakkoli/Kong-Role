local cjson = require("cjson.safe")
local constants = require("kong.constants")

local M = {}

local function parse_filters(csv)
  local result = {}
  if csv and csv ~= "" then
    for pattern in string.gmatch(csv, "[^,]+") do
      result[#result + 1] = pattern
    end
  end
  return result
end

function M.get_redirect_uri(ngx)
  local uri = ngx.var.request_uri or "/"
  local query = uri:find("?", 1, true)
  if query then
    uri = uri:sub(1, query - 1)
  end
  if uri == "/" then
    return "/cb"
  end
  return uri
end

function M.get_options(config, ngx)
  return {
    auth_mode = config.auth_mode,
    client_id = config.client_id,
    client_secret = config.client_secret,
    discovery = config.discovery,
    expected_issuer = config.expected_issuer,
    allowed_audiences = config.allowed_audiences or {},
    allowed_signing_algorithms = config.allowed_signing_algorithms or { "RS256" },
    introspection_endpoint = config.introspection_endpoint,
    introspection_endpoint_auth_method = config.introspection_endpoint_auth_method,
    timeout = config.timeout,
    ssl_verify = config.ssl_verify,
    redirect_uri = config.redirect_uri or M.get_redirect_uri(ngx),
    scope = config.scope,
    response_type = config.response_type,
    unauth_action = config.unauth_action,
    principal_claim = config.principal_claim,
    username_claim = config.username_claim,
    authorization_claims = config.authorization_claims or {},
    require_principal = config.require_principal,
    require_authorization_claim = config.require_authorization_claim,
    legacy_consumer_mapping = config.legacy_consumer_mapping,
    consumer_mapping_required = config.consumer_mapping_required,
    consumer_claim = config.consumer_claim,
    consumer_by = config.consumer_by,
    skip_already_auth_requests = config.skip_already_auth_requests,
    expose_userinfo = config.expose_userinfo,
    expose_id_token = config.expose_id_token,
    expose_access_token = config.expose_access_token,
    userinfo_header_name = config.userinfo_header_name,
    id_token_header_name = config.id_token_header_name,
    access_token_header_name = config.access_token_header_name,
    header_names = config.header_names or {},
    header_claims = config.header_claims or {},
    filters = parse_filters((config.filters or "") .. "," .. (config.ignore_auth_filters or "")),
    session_secret = config.session_secret,
    proxy_opts = {
      http_proxy = config.http_proxy,
      https_proxy = config.https_proxy,
    },
  }
end

function M.get_claim(source, path)
  if type(source) ~= "table" or type(path) ~= "string" or path == "" then
    return nil
  end

  local current = source
  for key in path:gmatch("[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[key]
  end
  return current
end

function M.as_string_list(value)
  if type(value) == "string" then
    return { value }
  end

  local result = {}
  if type(value) == "table" then
    for _, item in ipairs(value) do
      if type(item) == "string" then
        result[#result + 1] = item
      end
    end
  end
  return result
end

function M.collect_claim_values(claims, paths)
  local seen, result = {}, {}
  for _, path in ipairs(paths or {}) do
    for _, value in ipairs(M.as_string_list(M.get_claim(claims, path))) do
      if not seen[value] then
        seen[value] = true
        result[#result + 1] = value
      end
    end
  end
  table.sort(result)
  return result
end

function M.clear_trusted_headers(config)
  local headers = {
    config.userinfo_header_name,
    config.id_token_header_name,
    config.access_token_header_name,
  }

  for _, header in ipairs(config.header_names or {}) do
    headers[#headers + 1] = header
  end

  for _, header in ipairs(headers) do
    if header and header ~= "" then
      kong.service.request.clear_header(header)
    end
  end
end

function M.set_credentials(identity)
  local credential = {
    id = identity.id,
    username = identity.username,
  }

  kong.client.authenticate(nil, credential)
  kong.service.request.clear_header(constants.HEADERS.CONSUMER_ID)
  kong.service.request.clear_header(constants.HEADERS.CONSUMER_CUSTOM_ID)
  kong.service.request.clear_header(constants.HEADERS.CONSUMER_USERNAME)

  if credential.username then
    kong.service.request.set_header(constants.HEADERS.CREDENTIAL_IDENTIFIER,
                                    credential.username)
  end
end

function M.inject_json_header(value, header_name)
  if not header_name then
    return
  end
  local encoded = cjson.encode(value)
  if encoded then
    kong.service.request.set_header(header_name, ngx.encode_base64(encoded))
  end
end

function M.inject_access_token(token, header_name)
  if header_name and token then
    kong.service.request.set_header(header_name, "Bearer " .. token)
  end
end

function M.inject_allowlisted_headers(header_names, claim_paths, claims)
  if #header_names ~= #claim_paths then
    kong.log.err("oidc-role header_names and header_claims lengths differ")
    return
  end

  for index, header in ipairs(header_names) do
    kong.service.request.clear_header(header)
    local value = M.get_claim(claims, claim_paths[index])
    if type(value) == "table" then
      value = table.concat(M.as_string_list(value), ",")
    end
    if value ~= nil then
      kong.service.request.set_header(header, tostring(value))
    end
  end
end

function M.has_bearer_access_token()
  local header = kong.request.get_header("authorization")
  return type(header) == "string" and header:match("^[Bb][Ee][Aa][Rr][Ee][Rr]%s+%S+") ~= nil
end

function M.has_common_item(left, right)
  local left_values = M.as_string_list(left)
  local right_values = M.as_string_list(right)
  local set = {}
  for _, value in ipairs(right_values) do
    set[value] = true
  end
  for _, value in ipairs(left_values) do
    if set[value] then
      return true
    end
  end
  return false
end

return M
