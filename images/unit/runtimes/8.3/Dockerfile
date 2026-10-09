# syntax=docker/dockerfile:1.7

# NGINX Unit with PHP 8.3 (ZTS, Alpine) -> ghcr.io/media-holding/unit:8.3
#
# Unit serves static files from /app/public and passes everything else to
# /app/public/index.php. Composer, git, make and the PostgreSQL client are
# included, so the same image works for local development with the code
# bind-mounted into /app.
#
# No application code and no secrets inside, and there must never be any.
# See the README next to this file.

ARG PHP_VERSION=8.3

# ============================================================================
# unit - builds unitd and its PHP module against the same PHP as the runtime
# ============================================================================
FROM php:${PHP_VERSION}-zts-alpine AS unit

# A git tag is mutable, so the version alone is not enough - the sha256 is
# verified. When bumping the version, update the checksum too:
#     curl -fsSL <url> | sha256sum
ARG UNIT_VERSION=1.34.2
ARG UNIT_SHA256=0586d511868cd78d5da05391a52e4dc33e2632d2dc69db1b63ed6d8a78cfce22

RUN set -eux; \
    apk add --no-cache --virtual .unit-build build-base linux-headers openssl-dev pcre2-dev; \
    curl -fsSL --retry 5 --retry-all-errors "https://github.com/nginx/unit/archive/refs/tags/${UNIT_VERSION}.tar.gz" -o /tmp/unit.tgz; \
    echo "${UNIT_SHA256}  /tmp/unit.tgz" | sha256sum -c -; \
    mkdir -p /usr/src/unit; \
    tar -xzf /tmp/unit.tgz -C /usr/src/unit --strip-components=1; \
    cd /usr/src/unit; \
    # Unit builds with -Werror, and GCC 15 (current Alpine) flags hex lookup
    # tables in its sources that intentionally omit the trailing NUL.
    ./configure \
        --cc-opt="-Wno-error=unterminated-string-initialization" \
        --prefix=/usr \
        --statedir=/var/lib/unit \
        --control=unix:/var/run/control.unit.sock \
        --runstatedir=/var/run \
        --pid=/var/run/unit.pid \
        --logdir=/var/log \
        --log=/var/log/unit.log \
        --tmpdir=/var/tmp \
        --user=unit \
        --group=unit \
        --openssl; \
    ./configure php; \
    make -j"$(nproc)"; \
    make install

# ============================================================================
# runtime
# ============================================================================
FROM php:${PHP_VERSION}-zts-alpine

LABEL org.opencontainers.image.title="unit"
LABEL org.opencontainers.image.description="NGINX Unit with PHP 8.3 (ZTS, Alpine), prebuilt"
LABEL org.opencontainers.image.source="https://github.com/media-holding/docker-images"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.base.name="docker.io/library/php:8.3-zts-alpine"

WORKDIR /app

# apcu and phpredis are built from source rather than installed through PECL:
# the pecl.php.net REST channel regularly answers "does not have REST info xml
# available" and breaks the build. Their sources go into the PHP source tree,
# so docker-php-ext-install builds them together with the bundled extensions.
#
# Runtime libraries are derived from what the built modules actually link
# against (scanelf), then the whole toolchain is removed in one go.
ARG APCU_VERSION=5.1.28
ARG APCU_SHA256=0e60ba9d0fa4021c57a70c071f3d8f71de236275d084e560d5959fec4edd8c32
ARG PHPREDIS_VERSION=6.3.0
ARG PHPREDIS_SHA256=cb8f81df1a275599e4f8ddcfec7e1f65ed1953e6f5673649149fd680ebff4cad
RUN set -eux; \
    apk add --no-cache --virtual .php-build $PHPIZE_DEPS linux-headers \
        freetype-dev libpng-dev libwebp-dev libjpeg-turbo-dev \
        icu-dev gettext-dev libzip-dev libpq-dev; \
    docker-php-source extract; \
    curl -fsSL --retry 5 --retry-all-errors "https://github.com/krakjoe/apcu/archive/refs/tags/v${APCU_VERSION}.tar.gz" -o /tmp/apcu.tgz; \
    echo "${APCU_SHA256}  /tmp/apcu.tgz" | sha256sum -c -; \
    curl -fsSL --retry 5 --retry-all-errors "https://github.com/phpredis/phpredis/archive/refs/tags/${PHPREDIS_VERSION}.tar.gz" -o /tmp/phpredis.tgz; \
    echo "${PHPREDIS_SHA256}  /tmp/phpredis.tgz" | sha256sum -c -; \
    mkdir -p /usr/src/php/ext/apcu /usr/src/php/ext/redis; \
    tar -xzf /tmp/apcu.tgz -C /usr/src/php/ext/apcu --strip-components=1; \
    tar -xzf /tmp/phpredis.tgz -C /usr/src/php/ext/redis --strip-components=1; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" \
        apcu redis gd pdo_pgsql intl gettext pcntl opcache exif zip; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
            | tr ',' '\n' | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache $runDeps; \
    apk del --no-network .php-build; \
    docker-php-source delete; \
    rm -rf /tmp/*; \
    php -m | grep -qix apcu; \
    php -m | grep -qix redis

# Tools for running the application and working with it inside the container.
RUN apk add --no-cache bash git make postgresql-client procps

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

COPY --from=unit /usr/sbin/unitd /usr/sbin/unitd
COPY --from=unit /usr/lib/unit/ /usr/lib/unit/

COPY rootfs/ /

# unitd is setuid root: the main process has to bind :80 and switch the
# application processes to the unit user even when the container itself runs
# under that uid (user: "1000:1000").
#
# The initial configuration (rootfs/docker-entrypoint.d/config.json) is applied
# at build time and persisted in /var/lib/unit, so the container starts with it
# straight away. To replace it, put another config.json into
# /docker-entrypoint.d/ and run docker-configure.sh again in your Dockerfile.
RUN set -eux; \
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' /usr/sbin/unitd /usr/lib/unit/modules/*.so \
            | tr ',' '\n' | sort -u \
            | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache $runDeps; \
    addgroup -g 1000 unit; \
    adduser -D -u 1000 -G unit -s /sbin/nologin unit; \
    chown root:root /usr/sbin/unitd; \
    chmod u+s /usr/sbin/unitd; \
    mkdir -p /var/lib/unit; \
    /usr/local/bin/docker-configure.sh; \
    unitd --version

STOPSIGNAL SIGTERM

EXPOSE 80

CMD ["unitd", "--no-daemon", "--control", "unix:/var/run/control.unit.sock"]
