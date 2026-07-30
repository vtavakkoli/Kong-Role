local typedefs = require "kong.db.schema.typedefs"

return {
  name = "oidc-role",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    {
      config = {
        type = "record",
        fields = {
          { auth_mode = {
              type = "string",
              default = "jwt",
              one_of = { "jwt", "introspection", "authorization_code" },
          }},
          { client_id = { type = "string", required = true } },
          { client_secret = { type = "string", required = false, referenceable = true } },
          { discovery = { type = "string", required = true } },
          { expected_issuer = { type = "string", required = false } },
          { allowed_audiences = {
              type = "array", required = false,
              elements = { type = "string" }, default = {},
          }},
          { allowed_signing_algorithms = {
              type = "array", required = true,
              elements = { type = "string" }, default = { "RS256" },
          }},
          { introspection_endpoint = { type = "string", required = false } },
          { introspection_endpoint_auth_method = { type = "string", required = false } },
          { timeout = { type = "number", default = 10000 } },
          { ssl_verify = { type = "boolean", default = true } },
          { redirect_uri = { type = "string", required = false } },
          { scope = { type = "string", default = "openid" } },
          { response_type = { type = "string", default = "code" } },
          { unauth_action = {
              type = "string", default = "deny", one_of = { "deny", "auth" },
          }},
          { session_secret = { type = "string", required = false, referenceable = true } },

          { principal_claim = { type = "string", default = "sub" } },
          { username_claim = { type = "string", default = "preferred_username" } },
          { authorization_claims = {
              type = "array", required = true,
              elements = { type = "string" },
              default = { "resource_access.kong.roles", "realm_access.roles", "groups" },
          }},
          { require_principal = { type = "boolean", default = true } },
          { require_authorization_claim = { type = "boolean", default = false } },

          { legacy_consumer_mapping = { type = "boolean", default = false } },
          { consumer_mapping_required = { type = "boolean", default = false } },
          { consumer_claim = { type = "string", default = "sub" } },
          { consumer_by = {
              type = "string", default = "custom_id",
              one_of = { "id", "username", "custom_id" },
          }},

          { skip_already_auth_requests = { type = "boolean", default = false } },
          { expose_userinfo = { type = "boolean", default = false } },
          { expose_id_token = { type = "boolean", default = false } },
          { expose_access_token = { type = "boolean", default = false } },
          { userinfo_header_name = { type = "string", default = "X-UserInfo" } },
          { id_token_header_name = { type = "string", default = "X-ID-Token" } },
          { access_token_header_name = { type = "string", default = "X-Access-Token" } },
          { header_names = {
              type = "array", required = true,
              elements = { type = "string" }, default = {},
          }},
          { header_claims = {
              type = "array", required = true,
              elements = { type = "string" }, default = {},
          }},
          { filters = { type = "string", required = false } },
          { ignore_auth_filters = { type = "string", required = false } },
          { http_proxy = { type = "string", required = false } },
          { https_proxy = { type = "string", required = false } },
        },
        entity_checks = {
          {
            conditional = {
              if_field = "auth_mode",
              if_match = { eq = "introspection" },
              then_field = "introspection_endpoint",
              then_match = { required = true },
            },
          },
          {
            conditional = {
              if_field = "auth_mode",
              if_match = { eq = "authorization_code" },
              then_field = "client_secret",
              then_match = { required = true },
            },
          },
        },
      },
    },
  },
}
