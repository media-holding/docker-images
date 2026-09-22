#!/usr/bin/env bash
#
# Local image build with the same parameters as CI.
# Use it to check a Dockerfile before running the workflow.
#
#   ./scripts/build.sh sail 8.5              # build for the current architecture
#   ./scripts/build.sh sail 8.5 --push       # build multi-arch and push to GHCR
#   ./scripts/build.sh sail all              # every version of the image
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/images.json"
REGISTRY="${REGISTRY:-ghcr.io}"
NAMESPACE="${NAMESPACE:-media-holding}"

usage() {
    echo "Usage: $0 <image> <version|all> [--push]" >&2
    echo >&2
    echo "Available images:" >&2
    jq -r 'to_entries[] | select(.key | startswith("$") | not)
           | "  \(.key)\t\(.value.versions | join(", "))"' "$MANIFEST" >&2
    exit 1
}

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ $# -ge 2 ] || usage

IMAGE="$1"
VERSION="$2"
PUSH="${3:-}"

jq -e --arg i "$IMAGE" 'has($i)' "$MANIFEST" >/dev/null 2>&1 || {
    echo "Image '$IMAGE' not found in images.json" >&2
    usage
}

# "all" expands into the list of versions and recurses into this same script.
if [ "$VERSION" = "all" ]; then
    for v in $(jq -r --arg i "$IMAGE" '.[$i].versions[]' "$MANIFEST"); do
        "$0" "$IMAGE" "$v" ${PUSH:+"$PUSH"}
    done
    exit 0
fi

jq -e --arg i "$IMAGE" --arg v "$VERSION" \
    '.[$i].versions | index($v)' "$MANIFEST" >/dev/null || {
    echo "Version '$VERSION' is not declared for image '$IMAGE' in images.json" >&2
    exit 1
}

PACKAGE=$(jq -r --arg i "$IMAGE" '.[$i].package' "$MANIFEST")
CONTEXT=$(jq -r --arg i "$IMAGE" --arg v "$VERSION" \
    '.[$i].context | sub("\\{version\\}"; $v)' "$MANIFEST")
PLATFORMS=$(jq -r --arg i "$IMAGE" '.[$i].platforms | join(",")' "$MANIFEST")

BUILD_ARGS=()
while IFS= read -r arg; do
    BUILD_ARGS+=(--build-arg "$arg")
done < <(jq -r --arg i "$IMAGE" \
    '.[$i].build_args // {} | to_entries[] | "\(.key)=\(.value)"' "$MANIFEST")

# A multi-arch manifest cannot be loaded into the local Docker daemon, only pushed.
# So without --push we build for a single (current) architecture and load it into
# `docker images`.
if [ "$PUSH" = "--push" ]; then
    OUTPUT=(--platform "$PLATFORMS" --push)
else
    OUTPUT=(--load)
fi

# targets is a map of Dockerfile stage to tag suffix. No field (sail) means a
# single unnamed stage: the whole Dockerfile is built and the tag equals the version.
while IFS=$'\t' read -r TARGET SUFFIX; do
    TAG="$REGISTRY/$NAMESPACE/$PACKAGE:$VERSION$SUFFIX"

    echo "==> $TAG  (context: $CONTEXT${TARGET:+, target: $TARGET})"
    docker buildx build \
        "${OUTPUT[@]}" \
        "${BUILD_ARGS[@]}" \
        ${TARGET:+--target "$TARGET"} \
        --tag "$TAG" \
        --file "$REPO_ROOT/$CONTEXT/Dockerfile" \
        "$REPO_ROOT/$CONTEXT"
done < <(jq -r --arg i "$IMAGE" \
    '(.[$i].targets // {"": ""}) | to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST")
