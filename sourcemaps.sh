#!/usr/bin/env bash
# Upload the sourcemaps of a frontend build to GlitchTip/Sentry (release = commit sha).
#
# The final image must not contain the .map files (the source would be public): they are taken
# from the Dockerfile stage that builds the bundle (SM_STAGE, default "build"), rebuilt from the
# same cache with the same build args as the pushed image, so the file names match what the
# browser runs. Then: release created and linked to the project, files uploaded, release finalized.
#
# Env: SM_CONTEXT SM_STAGE SM_PATH SM_URL_PREFIX SM_REQUIRED SM_CLI_VERSION SM_RELEASE
#      SM_BUILD_DATE SM_BUILD_ARGS SM_SECRET_FILES, SENTRY_AUTH_TOKEN SENTRY_URL SENTRY_ORG SENTRY_PROJECT.
set -uo pipefail

export SENTRY_URL="${SENTRY_URL:-https://errors.mumble.group}"
export SENTRY_ORG="${SENTRY_ORG:-mumble}"
SM_CONTEXT="${SM_CONTEXT:-.}"
SM_STAGE="${SM_STAGE:-build}"
SM_PATH="${SM_PATH:-/app/dist}"
SM_URL_PREFIX="${SM_URL_PREFIX:-~/}"
SM_CLI_VERSION="${SM_CLI_VERSION:-2.58.6}"
SM_BUILD_DATE="${SM_BUILD_DATE:-}"
SM_BUILD_ARGS="${SM_BUILD_ARGS:-}"
SM_SECRET_FILES="${SM_SECRET_FILES:-}"
OUT="${RUNNER_TEMP:-/tmp}/sourcemaps-${SM_RELEASE:-local}"
TAG="ci-sourcemaps:${SM_RELEASE:-local}"

fail() {
  if [ "${SM_REQUIRED:-false}" = "true" ]; then
    echo "::error::sourcemaps: $*"
    exit 1
  fi
  echo "::warning::sourcemaps: $* (image already pushed; set sourcemaps-required: true to fail the job)"
  exit 0
}

[ -n "${SM_RELEASE:-}" ] || fail "no release (commit sha)"

# Same build args as the pushed image, so the build stage comes from the cache.
args=(--build-arg "GIT_COMMIT=$SM_RELEASE" --build-arg "BUILD_DATE=$SM_BUILD_DATE"
      --build-arg "SENTRY_RELEASE=$SM_RELEASE" --build-arg "VITE_RELEASE=$SM_RELEASE")
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  [ -n "$line" ] && args+=(--build-arg "$line")
done <<< "$SM_BUILD_ARGS"
# Same BuildKit secrets too: a stage that mounts one (e.g. a private npm registry) does not
# build without it when the cache misses.
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  [ -n "$line" ] && args+=(--secret "id=${line%%=*},src=${line#*=}")
done <<< "$SM_SECRET_FILES"

echo "sourcemaps: building stage '$SM_STAGE' of $SM_CONTEXT"
DOCKER_BUILDKIT=1 docker build -q --target "$SM_STAGE" "${args[@]}" -t "$TAG" "$SM_CONTEXT" >/dev/null \
  || fail "docker build --target $SM_STAGE failed (is there a stage named '$SM_STAGE'? see sourcemaps-stage)"

rm -rf "$OUT" && mkdir -p "$OUT"
cid=$(docker create "$TAG") || fail "docker create failed"
docker cp "$cid:$SM_PATH/." "$OUT/" >/dev/null
cp_status=$?
docker rm -f "$cid" >/dev/null
docker rmi "$TAG" >/dev/null 2>&1 || true
[ "$cp_status" -eq 0 ] || fail "$SM_PATH not found in stage $SM_STAGE (see sourcemaps-path)"

maps=$(find "$OUT" -name '*.map' | wc -l)
[ "$maps" -gt 0 ] || fail "no .map in $SM_PATH: build with sourcemaps on (Vite: build.sourcemap = 'hidden')"
echo "sourcemaps: $maps .map files, release $SM_RELEASE -> $SENTRY_URL $SENTRY_ORG/${SENTRY_PROJECT:-?}"

[ -n "${SENTRY_PROJECT:-}" ] || fail "sentry-project missing: pass vars.SENTRY_PROJECT (ensure_error_tracking_projects sets it)"
[ -n "${SENTRY_AUTH_TOKEN:-}" ] || fail "sentry-auth-token missing: pass secrets.SENTRY_AUTH_TOKEN (ensure_error_tracking_projects sets it)"

command -v npx >/dev/null || fail "npx not found on the runner (Node.js needed for @sentry/cli)"
cli() { npx --yes "@sentry/cli@$SM_CLI_VERSION" "$@"; }
# The release must exist and be linked to the project: GlitchTip matches the files of a release
# only for the projects of that release.
cli releases new -p "$SENTRY_PROJECT" "$SM_RELEASE" || fail "releases new failed"
cli sourcemaps upload --release "$SM_RELEASE" --url-prefix "$SM_URL_PREFIX" "$OUT" \
  || fail "sourcemaps upload failed"
cli releases finalize "$SM_RELEASE" || fail "releases finalize failed"
rm -rf "$OUT"
echo "sourcemaps: uploaded"
