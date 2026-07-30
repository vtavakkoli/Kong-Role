local M = {}

local function record(target, name)
  return function(...)
    target[#target + 1] = { name = name, args = { ... } }
  end
end

function M.new()
  local env = {
    calls = {},
    headers = {},
    cleared_headers = {},
    authorization = "Bearer test-token",
    current_credential = nil,
    consumer_results = {},
    consumer_errors = {},
  }

  env.kong = {
    ctx = { shared = {} },
    request = {
      get_header = function(name)
        if string.lower(name) == "authorization" then
          return env.authorization
        end
      end,
    },
    response = {
      exit = function(status, body, headers)
        env.response = { status = status, body = body, headers = headers }
        return env.response
      end,
      error = function(status, message)
        env.response = { status = status, body = message }
        return env.response
      end,
    },
    client = {
      authenticate = function(consumer, credential)
        env.calls[#env.calls + 1] = {
          name = "authenticate",
          consumer = consumer,
          credential = credential,
        }
      end,
      get_credential = function()
        return env.current_credential
      end,
    },
    service = {
      request = {
        clear_header = function(header)
          env.cleared_headers[#env.cleared_headers + 1] = header
          env.headers[header] = nil
        end,
        set_header = function(header, value)
          env.headers[header] = value
        end,
      },
    },
    log = {
      debug = record(env.calls, "debug"),
      warn = record(env.calls, "warn"),
      err = record(env.calls, "err"),
    },
    db = {
      consumers = {
        select_by_username = function(_, value)
          return env.consumer_results[value], env.consumer_errors[value]
        end,
        select_by_custom_id = function(_, value)
          return env.consumer_results[value], env.consumer_errors[value]
        end,
        select = function(_, key)
          return env.consumer_results[key.id], env.consumer_errors[key.id]
        end,
      },
    },
  }

  env.ngx = {
    HTTP_INTERNAL_SERVER_ERROR = 500,
    var = {
      uri = "/api",
      request_uri = "/api?x=1",
      session_secret = nil,
    },
    encode_base64 = function(value)
      return "base64:" .. value
    end,
    decode_base64 = function(value)
      if value == "invalid" then
        return nil
      end
      if value == "valid-secret" then
        return "decoded-session-secret"
      end
      return "decoded:" .. tostring(value)
    end,
  }

  return env
end

function M.install_constants()
  package.preload["kong.constants"] = function()
    return {
      HEADERS = {
        CONSUMER_ID = "X-Consumer-ID",
        CONSUMER_CUSTOM_ID = "X-Consumer-Custom-ID",
        CONSUMER_USERNAME = "X-Consumer-Username",
        CREDENTIAL_IDENTIFIER = "X-Credential-Identifier",
      },
    }
  end
end

function M.base_config(overrides)
  local config = {
    auth_mode = "jwt",
    client_id = "kong-api",
    client_secret = nil,
    discovery = "https://idp.example/realms/ma01/.well-known/openid-configuration",
    expected_issuer = "https://idp.example/realms/ma01",
    allowed_audiences = { "kong-api" },
    allowed_signing_algorithms = { "RS256" },
    introspection_endpoint = "https://idp.example/introspect",
    introspection_endpoint_auth_method = "client_secret_post",
    timeout = 10000,
    ssl_verify = true,
    redirect_uri = "/callback",
    scope = "openid",
    response_type = "code",
    unauth_action = "deny",
    session_secret = nil,
    principal_claim = "sub",
    username_claim = "preferred_username",
    authorization_claims = {
      "resource_access.kong-api.roles",
      "realm_access.roles",
      "groups",
    },
    require_principal = true,
    require_authorization_claim = false,
    legacy_consumer_mapping = false,
    consumer_mapping_required = false,
    consumer_claim = "sub",
    consumer_by = "custom_id",
    skip_already_auth_requests = false,
    expose_userinfo = false,
    expose_id_token = false,
    expose_access_token = false,
    userinfo_header_name = "X-UserInfo",
    id_token_header_name = "X-ID-Token",
    access_token_header_name = "X-Access-Token",
    header_names = {},
    header_claims = {},
    filters = nil,
    ignore_auth_filters = nil,
    http_proxy = nil,
    https_proxy = nil,
  }

  for key, value in pairs(overrides or {}) do
    config[key] = value
  end
  return config
end

function M.valid_claims(overrides)
  local claims = {
    sub = "user-123",
    preferred_username = "vahid",
    iss = "https://idp.example/realms/ma01",
    aud = { "account", "kong-api" },
    exp = 4102444800,
    iat = 1700000000,
    resource_access = {
      ["kong-api"] = { roles = { "invoice-reader", "invoice-writer" } },
    },
    realm_access = { roles = { "offline_access" } },
    groups = { "department-gat1" },
  }

  for key, value in pairs(overrides or {}) do
    claims[key] = value
  end
  return claims
end

return M
