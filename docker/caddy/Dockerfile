# syntax=docker/dockerfile:1

# Stock `caddy:2` has no rate limiter, so build one with the ratelimit
# module (github.com/mholt/caddy-ratelimit, by Caddy's own author) compiled
# in. Used by the `caddy` service in docker-compose.yml; the Caddyfile's
# `rate_limit` directive needs this.

FROM caddy:2-builder-alpine AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Bake the Caddyfile in so the deployment compose file
# (docker-compose.deploy.yml) is the only artifact CI has to copy to the host.
# The root docker-compose.yml still bind-mounts ./Caddyfile over this for local
# iteration; the two are kept identical.
COPY Caddyfile /etc/caddy/Caddyfile
