ARG KONG_VERSION=3.6
FROM kong/kong:${KONG_VERSION}

USER root

ARG LUA_RESTY_OPENIDC_VERSION=1.8.0
ARG LUA_RESTY_JWT_VERSION=0.2.3

# Kong 3.6 ships an older LuaRocks client that cannot reliably parse the
# current large public mirror manifest. Vendor the exact upstream Lua modules
# required by oidc-role from pinned releases instead of resolving dependencies
# through mutable or incompatible LuaRocks mirrors.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && mkdir -p /usr/local/share/lua/5.1/resty \
  && curl --fail --silent --show-error --location \
       "https://raw.githubusercontent.com/zmartzone/lua-resty-openidc/v${LUA_RESTY_OPENIDC_VERSION}/lib/resty/openidc.lua" \
       --output /usr/local/share/lua/5.1/resty/openidc.lua \
  && curl --fail --silent --show-error --location \
       "https://raw.githubusercontent.com/cdbattags/lua-resty-jwt/v${LUA_RESTY_JWT_VERSION}/lib/resty/jwt.lua" \
       --output /usr/local/share/lua/5.1/resty/jwt.lua \
  && curl --fail --silent --show-error --location \
       "https://raw.githubusercontent.com/cdbattags/lua-resty-jwt/v${LUA_RESTY_JWT_VERSION}/lib/resty/jwt-validators.lua" \
       --output /usr/local/share/lua/5.1/resty/jwt-validators.lua \
  && curl --fail --silent --show-error --location \
       "https://raw.githubusercontent.com/cdbattags/lua-resty-jwt/v${LUA_RESTY_JWT_VERSION}/lib/resty/evp.lua" \
       --output /usr/local/share/lua/5.1/resty/evp.lua \
  && grep -q "_VERSION = \"${LUA_RESTY_OPENIDC_VERSION}\"" \
       /usr/local/share/lua/5.1/resty/openidc.lua \
  && grep -q "_VERSION = \"${LUA_RESTY_JWT_VERSION}\"" \
       /usr/local/share/lua/5.1/resty/jwt.lua \
  && grep -q "_VERSION = \"${LUA_RESTY_JWT_VERSION}\"" \
       /usr/local/share/lua/5.1/resty/jwt-validators.lua \
  && grep -q "_VERSION = \"${LUA_RESTY_JWT_VERSION}\"" \
       /usr/local/share/lua/5.1/resty/evp.lua \
  && rm -rf /var/lib/apt/lists/*

# Install custom plugin into Kong's plugin path.
COPY oidc-role /usr/local/share/lua/5.1/kong/plugins/oidc-role
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/oidc-role \
  /usr/local/share/lua/5.1/resty/openidc.lua \
  /usr/local/share/lua/5.1/resty/jwt.lua \
  /usr/local/share/lua/5.1/resty/jwt-validators.lua \
  /usr/local/share/lua/5.1/resty/evp.lua

USER kong
