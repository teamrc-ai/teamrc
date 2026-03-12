# Dockerfile for teamrc relay server
# Multi-stage build using mix release for a minimal production image.
#
# Build:  docker build -t teamrc .
# Run:    docker run -p 4000:4000 --env-file .env teamrc

# =============================================================================
# Build stage
# =============================================================================
FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20250407-slim AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app/teamrc

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Cache dependencies (changes less often than app code)
COPY teamrc/mix.exs teamrc/mix.lock ./
RUN mix deps.get --only $MIX_ENV

COPY teamrc/config/config.exs teamrc/config/prod.exs config/
RUN mix deps.compile

# Install tailwind and esbuild binaries for asset compilation
RUN mix tailwind.install --if-missing && mix esbuild.install --if-missing

# Copy templates (compile-time path resolves to /app/templates)
COPY templates /app/templates

# Copy app source
COPY teamrc/priv priv
COPY teamrc/lib lib
COPY teamrc/assets assets
COPY teamrc/rel rel
COPY teamrc/config/runtime.exs config/

# Compile first (generates phoenix-colocated hooks), then build assets
RUN mix compile
RUN mix assets.deploy
RUN mix release

# =============================================================================
# Runtime stage — minimal image with just the release
# =============================================================================
FROM debian:bookworm-20250407-slim

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody:nogroup /app

# Copy the compiled release
COPY --from=builder --chown=nobody:nogroup /app/teamrc/_build/prod/rel/teamrc ./

# Copy templates (needed at runtime by Teamrc.Catalog)
COPY --from=builder --chown=nobody:nogroup /app/templates /app/templates

USER nobody

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

# Runs migrations then starts the server
CMD ["/app/bin/docker-entrypoint"]
