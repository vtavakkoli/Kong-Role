ARG KONG_VERSION=3.6
FROM kong/kong:${KONG_VERSION}

USER root

# Install dependencies required for LuaRocks package installation.
RUN apt-get update \
  && apt-get install -y --no-install-recommends luarocks \
  && rm -rf /var/lib/apt/lists/*

# Install upstream OIDC dependency used by this plugin.
RUN luarocks install kong-oidc

# Install custom plugin into Kong's plugin path.
COPY oidc-role /usr/local/share/lua/5.1/kong/plugins/oidc-role
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/oidc-role

USER kong
