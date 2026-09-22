# docker-images

Base Docker images for media-holding projects. Built here once and published to
GHCR so that projects don't rebuild the same thing locally.

## Images

| Image | Package | Tags | Purpose |
|---|---|---|---|
| `sail` | `ghcr.io/media-holding/sail` | `8.5`, `8.4`, `8.3` | Ready-made Laravel Sail runtime for local development |
| `frankenphp` | `ghcr.io/media-holding/frankenphp` | `8.5`, `8.5-build` | Production base on FrankenPHP: runtime and build stage |
| `swoole` | — | — | Production base on Octane/Swoole. **Planned, not built yet** |

### Tags

- `8.5` — floating, always points at the latest build. This is what projects pin.
  `frankenphp` also has `8.5-build`: the same base plus Composer and Node for the
  build stage, see [images/frankenphp](images/frankenphp/README.md).
- `8.5-20260101-a1b2c3d` — immutable, tied to one specific build. Needed to roll
  back when a rebuild breaks something: a rebuild overwrites the floating tag and
  the previous image is left in the registry without a name.

There is deliberately no `latest` tag: the PHP version in the tag is mandatory
anyway, and `latest` would only be confusing.

## The `sail` image

A byte-for-byte copy of the Laravel Sail runtime
(`vendor/laravel/sail/runtimes/<version>`), built ahead of time. It contains
exactly what Sail would build locally: Ubuntu 24.04, PHP from the sury
repository with the full set of extensions (`pgsql`, `gd`, `redis`, `swoole`,
`imagick`, `pcov`, `xdebug`, `mongodb`, `memcached`…), Composer + cpx, Node 24
with npm/pnpm/bun/yarn, Playwright dependencies, PostgreSQL 18 and MySQL
clients, the `sail` user, `supervisord` and `start-container` as the entrypoint.

There are two differences from upstream, both in the `Dockerfile` header: the OCI
labels and `ARG WWWGROUP=1000` (in Sail this argument is required and comes from
the host; here the image is built ahead of time, so the value is baked in). The
uid stays flexible — on startup `start-container` runs `usermod -u $WWWUSER sail`,
so permissions on the bind mount are not broken.

### Using it in a project

In `compose.yaml`, drop the `build:` block and point at the prebuilt image:

```yaml
x-app: &app
    image: 'ghcr.io/media-holding/sail:8.5'
    extra_hosts:
        - 'host.docker.internal:host-gateway'
    environment:
        WWWUSER: '${WWWUSER}'      # required: start-container fixes the uid from it
        LARAVEL_SAIL: 1
    volumes:
        - '.:/var/www/html'
```

`laravel/sail` stays in `require-dev`: its directory still provides the SQL that
creates the test database, and the `./vendor/bin/sail` binary still works.

To update the image locally: `docker compose pull`.

Start the environment with `./vendor/bin/sail up -d` rather than a bare
`docker compose up`: the `WWWUSER` variable is set by the `sail` script itself
(`WWWUSER=$UID`). Without it the entrypoint doesn't know which uid to run as and
the container fails with `unable to find user`. That is upstream behaviour, not a
quirk of the prebuilt image.

## The `frankenphp` image

A production base for Laravel on FrankenPHP: PHP 8.5 with a set of extensions
(`pdo_pgsql`, `pgsql`, `gd`, `intl`, `zip`, `bcmath`, `pcntl`, `opcache`) and
phpredis built from source. Published as two tags — `8.5` for the runtime and
`8.5-build` with Composer and Node for the application build stage.

There is no application code inside: a project adds its own on top with its own
`Dockerfile`. See [images/frankenphp/README.md](images/frankenphp/README.md).

## Building

Builds are manual: **Actions → Build images → Run workflow**. The form selects
the image, the PHP version, the architectures and whether to publish. Clear the
`Publish` checkbox to only check that the Dockerfile builds.

Locally, with the same parameters:

```bash
./scripts/build.sh sail 8.5
```

To compare our copies of the Sail runtime against upstream after
`composer update laravel/sail` in any project:

```bash
./scripts/sync-sail.sh /path/to/laravel-project
```

## Adding an image or a PHP version

See [CONTRIBUTING.md](CONTRIBUTING.md).
