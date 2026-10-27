# frankenphp — production base

A base image for Laravel applications on FrankenPHP: PHP with extensions and
nothing else. No application code and no secrets inside.

FrankenPHP runs in classic mode (no worker/Octane): Caddy serves static files and
proxies PHP, the application stays an ordinary stateless Laravel app.

## What's inside

- base `dunglas/frankenphp:<FRANKENPHP_VERSION>-php<PHP_RELEASE>-alpine`
  (Alpine, musl), pinned to an exact PHP patch release — see
  [Versions](#versions);
- extensions via `install-php-extensions`: `pdo_pgsql`, `pgsql`, `gd`, `exif`,
  `gettext`, `intl`, `zip`, `bcmath`, `pcntl`, `opcache`;
- `psql` / `pg_dump` (`postgresql18-client`) — `artisan migrate` loads the schema
  dump through `psql` on an empty database;
- `phpredis` — built from source from GitHub rather than through PECL: the
  `pecl.php.net` REST channel regularly answers "does not have REST info xml
  available". The version and its sha256 live in `images.json`
  (`PHPREDIS_VERSION`, `PHPREDIS_SHA256`) — a git tag is mutable, so the checksum
  is mandatory.

Alpine was chosen for size: 390 MB against 976 MB for the Debian variant. The
price is build time: `install-php-extensions` compiles `intl` from source
(minutes instead of seconds). For an image that is rebuilt by hand, that trade is
worth it.

## Versions

| PHP | Pinned release | Runtime directory |
|---|---|---|
| 8.5 | 8.5.12 | `runtimes/8.5` |
| 8.4 | 8.4.27 | `runtimes/8.4` |
| 8.3 | 8.3.36 | `runtimes/8.3` |
| 8.2 | 8.2.35 | `runtimes/8.2` |

These are the releases that fix CVE-2026-109618 and CVE-2026-109619
(unauthenticated RCE; PHP-FPM, mod_php and FrankenPHP are all affected). Do not
go below them.

The base is pinned to `<FRANKENPHP_VERSION>-php<PHP_RELEASE>-alpine` rather than
the floating `1-php8.x-alpine`: a floating tag that is cached on a builder can
silently bring back a vulnerable PHP. The build also checks that the PHP inside
is exactly `PHP_RELEASE` and fails otherwise.

## Tags

| Tag | Adds | For |
|---|---|---|
| `8.x` | — | runtime: what ships to production |
| `8.x-build` | Composer 2 and Node 24 with npm | build stage: `composer install`, `npm run build` |

Sizes for 8.5: 390 MB and 598 MB.

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

Things that are easy to get wrong:

- **TLS.** If a reverse proxy terminates it, set `SERVER_NAME=:80` and
  `CADDY_GLOBAL_OPTIONS="auto_https off"`. Otherwise FrankenPHP tries to issue a
  certificate itself and moves to 443, leaving the proxy without a backend.
- **Port 80 is privileged.** Running as a non-privileged user requires
  `setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp`.
  Caddy also writes to `/data/caddy` and `/config/caddy`, which belong to root:
  `chown` them to that user.
- **Healthcheck in non-web containers.** The image inherits upstream's
  `HEALTHCHECK` (`curl localhost:2019/metrics`, the Caddy admin endpoint). A
  container running `horizon`, `queue:work` or `schedule:work` from the same
  image has no Caddy, turns `unhealthy`, and Swarm keeps restarting it. Disable
  the check for such services (`healthcheck: { disable: true }`).

## Updating

`FRANKENPHP_VERSION`, `PHPREDIS_VERSION`, `PHPREDIS_SHA256` and `NODE_VERSION`
live in `images.json` and are shared by every PHP version. The PHP patch release
is `ARG PHP_RELEASE` in each `runtimes/<version>/Dockerfile`.

To pick up a PHP security release: check that the tag exists on Docker Hub
(`dunglas/frankenphp:<FRANKENPHP_VERSION>-php<new release>-alpine`), bump
`PHP_RELEASE` (and `FRANKENPHP_VERSION` if the new PHP only ships with a newer
FrankenPHP), update the table above and rebuild.

After any change rebuild **both** tags of a version together (`./scripts/build.sh
frankenphp 8.5` does that on its own, `all` rebuilds every version) — otherwise
`8.5` and `8.5-build` drift apart and the application ends up built on something
other than what it runs on.
