FROM kong/kong:latest

USER root

# Install required tools and build dependencies
RUN apt-get update && \
    apt-get install -y luarocks && \
    rm -rf /var/lib/apt/lists/*

# Install kong-oidc
RUN luarocks install kong-oidc
COPY oidc-role /usr/local/share/lua/5.1/kong/plugins/oidc-role
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/oidc-role
# Switch back to the Kong user
USER kong