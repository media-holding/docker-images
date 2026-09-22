#!/usr/bin/env bash
#
# Compares images/sail/runtimes/* against upstream laravel/sail from any project.
# Run it after every `composer update laravel/sail`: if upstream changed, the image
# has to be rebuilt, otherwise it silently drifts from what Sail would build locally.
#
#   ./scripts/sync-sail.sh /path/to/laravel-project          # show the diff
#   ./scripts/sync-sail.sh /path/to/laravel-project --apply  # port the changes
#
# --apply rewrites our Dockerfiles with the upstream body while KEEPING our header
# (everything above the `ARG NODE_VERSION` line). Other files are copied as is.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${1:-}"
MODE="${2:-}"

[ -n "$PROJECT" ] || { echo "Usage: $0 <path-to-laravel-project> [--apply]" >&2; exit 1; }

UPSTREAM="$PROJECT/vendor/laravel/sail/runtimes"
[ -d "$UPSTREAM" ] || { echo "$UPSTREAM not found - is laravel/sail installed?" >&2; exit 1; }

status=0

for dir in "$REPO_ROOT"/images/sail/runtimes/*/; do
    version=$(basename "$dir")
    src="$UPSTREAM/$version"

    if [ ! -d "$src" ]; then
        echo "!! $version: upstream has no such version, skipping"
        continue
    fi

    for file in Dockerfile php.ini start-container supervisord.conf; do
        if [ "$file" = "Dockerfile" ]; then
            # Compare the body only: our header (comment, labels, WWWGROUP) differs
            # by design and should not show up in the diff every time.
            ours=$(sed -n '/^ARG NODE_VERSION/,$p' "$dir/$file")
            theirs=$(sed -n '/^ARG NODE_VERSION/,$p' "$src/$file")
        else
            ours=$(cat "$dir/$file")
            theirs=$(cat "$src/$file")
        fi

        if [ "$ours" != "$theirs" ]; then
            status=1
            echo "!! $version/$file differs from upstream:"
            diff <(echo "$ours") <(echo "$theirs") | sed 's/^/     /' || true

            if [ "$MODE" = "--apply" ]; then
                if [ "$file" = "Dockerfile" ]; then
                    header=$(sed -n '1,/^ARG NODE_VERSION/p' "$dir/$file" | sed '$d')
                    { echo "$header"; echo "$theirs"; } > "$dir/$file"
                else
                    cp "$src/$file" "$dir/$file"
                fi
                echo "   -> updated"
            fi
        fi
    done
done

if [ $status -eq 0 ]; then
    echo "Everything matches upstream."
elif [ "$MODE" = "--apply" ]; then
    echo
    echo "Changes ported. Review git diff, build (./scripts/build.sh sail all)"
    echo "and run the workflow, otherwise GHCR keeps serving the old image."
    status=0
else
    echo
    echo "Re-run with --apply to port the changes."
fi

exit $status
