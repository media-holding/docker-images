# syntax=docker/dockerfile:1.7

# Production base on FrankenPHP for PHP 8.5.
#
# Two stages are published:
#   runtime -> ghcr.io/media-holding/frankenphp:8.5        what ships to production
#   build   -> ghcr.io/media-holding/frankenphp:8.5-build  the same plus composer and Node
#
# No application code and no secrets inside, and there must never be any.
# See the README next to this file.

ARG NODE_VERSION=24

# Only a source of binaries for the build stage. Never reaches runtime.
FROM node:${NODE_VERSION}-alpine AS node

# ============================================================================
# runtime - PHP extensions, shared by the build and the runtime
# ============================================================================
# FrankenPHP in classic mode (no worker/Octane): Caddy serves static files and
# proxies PHP, the application stays an ordinary stateless Laravel app.
FROM dunglas/frankenphp:1-php8.5-alpine AS runtime

LABEL org.opencontainers.image.title="frankenphp"
LABEL org.opencontainers.image.description="FrankenPHP production base (PHP 8.5), prebuilt"
LABEL org.opencontainers.image.source="https://github.com/media-holding/docker-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.base.name="docker.io/dunglas/frankenphp:1-php8.5-alpine"

ENV TZ=UTC
ENV LANG=C.UTF-8

# pgsql - the database; gd - required by phpoffice/phpspreadsheet, without it
# composer install fails on projects that produce spreadsheets; intl/zip/bcmath
# are basics; pcntl - signal handling in queue:work; opcache - production
# performance.
RUN install-php-extensions \
        pdo_pgsql \
        pgsql \
        gd \
        intl \
        zip \
        bcmath \
        pcntl \
        opcache

# phpredis (cache/sessions/queues) is built from source rather than installed
# through PECL: the pecl.php.net REST channel regularly answers "does not have
# REST info xml available" and breaks the build.
# The toolchain goes into a temporary virtual package and is removed in one go.
#
# A git tag is mutable, so the version alone is not enough - the sha256 is
# verified. When bumping the version, update the checksum too:
#     curl -fsSL <url> | sha256sum
ARG PHPREDIS_VERSION=6.3.0
ARG PHPREDIS_SHA256=cb8f81df1a275599e4f8ddcfec7e1f65ed1953e6f5673649149fd680ebff4cad
RUN set -eux; \
    apk add --no-cache --virtual .phpredis-build $PHPIZE_DEPS zstd-dev lz4-dev; \
    curl -fsSL "https://github.com/phpredis/phpredis/archive/refs/tags/${PHPREDIS_VERSION}.tar.gz" -o /tmp/phpredis.tgz; \
    echo "${PHPREDIS_SHA256}  /tmp/phpredis.tgz" | sha256sum -c -; \
    mkdir -p /tmp/phpredis; \
    tar -xzf /tmp/phpredis.tgz -C /tmp/phpredis --strip-components=1; \
    cd /tmp/phpredis; \
    phpize; \
    ./configure --enable-redis; \
    make -j"$(nproc)"; \
    make install; \
    docker-php-ext-enable redis; \
    cd /; \
    rm -rf /tmp/phpredis /tmp/phpredis.tgz; \
    apk del --no-network .phpredis-build; \
    php -m | grep -qix redis

WORKDIR /app

# ============================================================================
# build - the same plus build tooling
# ============================================================================
# Inherits from runtime, so in the registry both stages share the lower layers:
# a runner that already pulled one tag gets the second almost for free.
FROM runtime AS build

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Node is installed by copying binaries rather than as a package: apk ships its
# own version, which lags behind the one we need, while all we want is exactly
# node+npm at a given version.
# The `node` stage must sit on the same libc as the base (both musl/Alpine right
# now), otherwise the binary will not start. Change the base, change this too.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node -v && npm -v && composer -V
