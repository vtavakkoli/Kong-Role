ARG KONG_VERSION=3.6
FROM kong/kong:${KONG_VERSION}

USER root

ARG LUA_RESTY_OPENIDC_VERSION=1.8.0

# Kong 3.6 ships an older LuaRocks client that cannot reliably parse the
# current large public mirror manifest. Install the single upstream module
# directly from its pinned release instead of resolving an unrelated
# third-party Kong OIDC plugin and its dependency graph at image-build time.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl ca-certificates \
  && mkdir -p /usr/local/share/lua/5.1/resty \
  && curl --fail --silent --show-error --location \
       "https://raw.githubusercontent.com/zmartzone/lua-resty-openidc/v${LUA_RESTY_OPENIDC_VERSION}/lib/resty/openidc.lua" \
       --output /usr/local/share/lua/5.1/resty/openidc.lua \
  && grep -q "_VERSION = \"${LUA_RESTY_OPENIDC_VERSION}\"" \
       /usr/local/share/lua/5.1/resty/openidc.lua \
  && rm -rf /var/lib/apt/lists/*

# Install custom plugin into Kong's plugin path.
COPY oidc-role /usr/local/share/lua/5.1/kong/plugins/oidc-role
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/oidc-role \
  /usr/local/share/lua/5.1/resty/openidc.lua

USER kong
