# frankenphp — production base

A base image for Laravel applications on FrankenPHP: PHP with extensions and
nothing else. No application code and no secrets inside.

FrankenPHP runs in classic mode (no worker/Octane): Caddy serves static files and
proxies PHP, the application stays an ordinary stateless Laravel app.

## What's inside

- base `dunglas/frankenphp:1-php8.5-alpine` (Alpine 3.24, musl);
- extensions via `install-php-extensions`: `pdo_pgsql`, `pgsql`, `gd`, `intl`,
  `zip`, `bcmath`, `pcntl`, `opcache`;
- `phpredis` — built from source from GitHub rather than through PECL: the
  `pecl.php.net` REST channel regularly answers "does not have REST info xml
  available". The version and its sha256 live in `images.json`
  (`PHPREDIS_VERSION`, `PHPREDIS_SHA256`) — a git tag is mutable, so the checksum
  is mandatory.

Alpine was chosen for size: 390 MB against 976 MB for the Debian variant. The
price is build time: `install-php-extensions` compiles `intl` from source
(minutes instead of seconds). For an image that is rebuilt by hand, that trade is
worth it.

## Tags

| Tag | Adds | For |
|---|---|---|
| `8.5` | — | runtime: what ships to production |
| `8.5-build` | Composer 2 and Node 24 with npm | build stage: `composer install`, `npm run build` |

Sizes: 390 MB and 598 MB.

The `build` stage inherits from `runtime`, so in the registry they share the
lower layers: a runner that already pulled one tag gets the second almost for
free.

Both also have immutable variants (`8.5-20260101-a1b2c3d`) — see the
[README](../../README.md#tags).

## Using it in a project

```dockerfile
FROM ghcr.io/media-holding/frankenphp:8.5-build AS build
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN composer dump-autoload --optimize --classmap-authoritative && npm run build && rm -rf node_modules

FROM ghcr.io/media-holding/frankenphp:8.5 AS runtime
COPY --from=build --chown=www-data:www-data /app /app
```

The rest is the usual application wiring: entrypoint, `SERVER_NAME`,
permissions, `USER`. `WORKDIR` in the image is already `/app`.

Two things that are easy to get wrong:

- **TLS.** If a reverse proxy terminates it, set `SERVER_NAME=:80` and
  `CADDY_GLOBAL_OPTIONS="auto_https off"`. Otherwise FrankenPHP tries to issue a
  certificate itself and moves to 443, leaving the proxy without a backend.
- **Port 80 is privileged.** Running as a non-privileged user requires
  `setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp`.

## Updating

`PHPREDIS_VERSION`, `PHPREDIS_SHA256` and `NODE_VERSION` live in `images.json`.
After changing them rebuild **both** tags together (`./scripts/build.sh
frankenphp 8.5` does that on its own) — otherwise `8.5` and `8.5-build` drift
apart and the application ends up built on something other than what it runs on.
