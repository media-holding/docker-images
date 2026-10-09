# unit — NGINX Unit with PHP

A base image for Laravel applications on NGINX Unit: PHP (ZTS) with extensions
and Unit with its PHP module, built against that same PHP. No application code and
no secrets inside.

Upstream NGINX Unit is archived and no longer released. The image is kept for
applications that still run on it; new projects should prefer
[frankenphp](../frankenphp/README.md).

## What's inside

- base `php:8.3-zts-alpine` (musl);
- NGINX Unit `UNIT_VERSION`, built from source with its PHP module; the sources
  are verified against `UNIT_SHA256`;
- extensions: `pdo_pgsql`, `gd` (FreeType, JPEG, WebP), `intl`, `gettext`,
  `pcntl`, `opcache`, `exif`, `zip`;
- `apcu` and `phpredis` — built from source from GitHub rather than through PECL:
  the `pecl.php.net` REST channel regularly answers "does not have REST info xml
  available". Versions and sha256 checksums live in `images.json`;
- Composer 2, `git`, `make`, `bash`, `procps` and the PostgreSQL client — the same
  image serves local development with the code bind-mounted into `/app`;
- the `unit` user, uid/gid 1000.

## Tags

| Tag | Unit | PHP |
|---|---|---|
| `8.3` | `UNIT_VERSION` from `images.json` | 8.3 |

Immutable variants (`8.3-20260101-a1b2c3d`) are published as well — see the
[README](../../README.md#tags).

## Configuration

The initial Unit configuration is
[`rootfs/docker-entrypoint.d/config.json`](runtimes/8.3/rootfs/docker-entrypoint.d/config.json).
It is applied at build time by `docker-configure.sh` and persisted in
`/var/lib/unit`, so the container starts with it straight away:

- listener on `:80`;
- static files are served from `/app/public`, everything else goes to
  `/app/public/index.php`;
- a dynamic pool of PHP processes: up to 8, 2 kept spare, idle ones stop after
  60 seconds. Without a `processes` setting Unit runs a single PHP process and
  serves requests strictly one at a time.

To change it, put your own `config.json` into `/docker-entrypoint.d/` and apply it
in your `Dockerfile`:

```dockerfile
COPY unit.json /docker-entrypoint.d/config.json
RUN /usr/local/bin/docker-configure.sh
```

PHP settings live in `/usr/local/etc/php/conf.d/php.ini`: production OPcache
(`validate_timestamps=0`) and a 100 MB upload limit. Replacing this file — for
example with a development variant that re-enables `validate_timestamps` — drops
these defaults.

`unitd` is setuid root: the main process binds `:80` and starts the application
processes as `unit`, even when the container runs under uid 1000. Unit does not
compress responses — leave that to the reverse proxy.

## Using it in a project

```dockerfile
FROM ghcr.io/media-holding/unit:8.3
COPY --chown=1000:1000 . /app
RUN composer install --no-dev --optimize-autoloader --no-interaction
```

The `CMD` already starts Unit:
`unitd --no-daemon --control unix:/var/run/control.unit.sock`.

## Updating

`UNIT_VERSION`, `APCU_VERSION`, `PHPREDIS_VERSION` and their `*_SHA256` live in
`images.json`. When bumping a version, update its checksum too:

```bash
curl -fsSL <url> | sha256sum
```
