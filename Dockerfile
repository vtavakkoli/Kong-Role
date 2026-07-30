ARG KONG_VERSION=3.6
FROM kong/kong:${KONG_VERSION}

USER root

# Install LuaRocks for the runtime dependency used directly by oidc-role.
RUN apt-get update \
  && apt-get install -y --no-install-recommends luarocks ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Install the exact OpenID Connect library imported by the plugin. Pin the
# version and registry so builds do not depend on third-party Kong OIDC rocks
# or the base image's optional LuaRocks mirrors.
RUN luarocks install lua-resty-openidc 1.8.0-1 \
  --server=https://luarocks.org

# Install custom plugin into Kong's plugin path.
COPY oidc-role /usr/local/share/lua/5.1/kong/plugins/oidc-role
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/oidc-role

USER kong
