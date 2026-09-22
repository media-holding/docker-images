# Working with this repository

## Layout

```
images.json                     manifest: what we build and with which arguments
images/<image>/runtimes/<ver>/  build context, one directory per PHP version
scripts/build.sh                local build with the same parameters as CI
scripts/sync-sail.sh            compares the sail image against upstream laravel/sail
.github/workflows/build.yml     manual build trigger
```

`images.json` is the source of truth: CI computes the build matrix from it and
`build.sh` reads the same file. The only place where the list of images and
versions is duplicated by hand is the `options` of the `image` and `version`
inputs in `build.yml` — GitHub Actions does not support dynamic dropdowns.

## Adding a PHP version to an existing image

Using `sail` and PHP 8.6 as an example:

1. Copy the upstream directory:
   ```bash
   cp -r /path/to/laravel-project/vendor/laravel/sail/runtimes/8.6 images/sail/runtimes/8.6
   ```
2. Carry over the header from a neighbouring version (comment, OCI labels,
   `ARG WWWGROUP=1000`), replacing the version number in it. Do not touch
   anything else in the `Dockerfile` — the whole point is that the body stays
   byte-for-byte identical to upstream.
3. Add `"8.6"` to `versions` in `images.json`.
4. Add `'8.6'` to the `options` of the `version` input in
   `.github/workflows/build.yml`.
5. Check locally: `./scripts/build.sh sail 8.6`.
6. Run the workflow with publishing off, then with it on.

## Adding a new image

1. Create `images/<name>/runtimes/<version>/Dockerfile`. The
   `LABEL org.opencontainers.image.source="https://github.com/media-holding/docker-images"`
   is mandatory: it is what ties the published package back to its sources.
2. Describe a block in `images.json`:
   ```json
   "<name>": {
     "description": "...",
     "package": "<GHCR package name>",
     "context": "images/<name>/runtimes/{version}",
     "versions": ["8.5"],
     "platforms": ["linux/amd64", "linux/arm64"],
     "build_args": { }
   }
   ```
   The `{version}` placeholder in `context` is substituted automatically.

   If a single `Dockerfile` should publish several stages, add the optional
   `targets` field — a map of stage to tag suffix:
   ```json
   "targets": { "build": "-build", "runtime": "" }
   ```
   That is how `frankenphp` produces two images from one context: `8.5` and
   `8.5-build`. Without the field the whole `Dockerfile` is built and the tag
   equals the version.

   Key order matters: merge jobs run serially in this order, so keep the primary
   tag last.
3. Add `<name>` to the `options` of the `image` input in `build.yml`.
4. `./scripts/build.sh <name> <version>` — check that it builds.
5. Run the workflow with `Publish: off`, then with it on.

## Keeping the `sail` image in sync with upstream

Our `images/sail/runtimes/*` is a fork of `vendor/laravel/sail/runtimes/*`. When
`laravel/sail` is updated in a project, upstream may change (a new extension, a
different Node version, a new base) and our image silently drifts from what Sail
would build locally. To check:

```bash
./scripts/sync-sail.sh /path/to/laravel-project
```

The script compares the body of the `Dockerfile` (it ignores our header) and all
the auxiliary files. If there are differences, port them and rebuild:

```bash
./scripts/sync-sail.sh /path/to/laravel-project --apply
git diff
./scripts/build.sh sail all
```

`--apply` substitutes the upstream body while keeping our header. After that you
must run the workflow, otherwise GHCR keeps serving the old image.

## The production image rule

No application code and no secrets inside — anyone able to pull an image can
unpack its layers. The image carries the runtime only. This applies to
`frankenphp` and to anything added later.

`images/swoole/` is still empty — no project uses Octane yet. When one does: base
on `php:<version>-cli` plus `install-php-extensions swoole` and the same set of
extensions as the FrankenPHP base.

## Why arm64 builds on a separate runner

Multi-arch is not built through QEMU but by two jobs on native runners
(`ubuntu-24.04` and `ubuntu-24.04-arm`) whose results are stitched into a single
manifest with `docker buildx imagetools create`. Emulating this image is roughly
four times slower — `apt` fetches and unpacks hundreds of packages.

If native arm64 runners are ever unavailable, `docker/setup-qemu-action` has to
come back — the place is marked with a comment in `build.yml`.
