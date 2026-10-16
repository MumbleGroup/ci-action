# mumble-group / ci

Centralized Gitea Actions for Mumble projects.

## Composite action: build & push Docker image to Harbor

Builds a Docker image and pushes it to Harbor (`harbor.m0.mumble.cloud`) with
`:latest` and `:<commit-sha>` tags. The build/login/push logic lives here once —
projects just call the action in one step.

### Usage (in a project repo)

`.github/workflows/build.yml` (Gitea Actions reads `.github/workflows/` too):

```yaml
name: Build image
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mumble-group/ci@main
        with:
          image: <slug>/<slug>_b      # e.g. vpsmanager/vpsmanager_b
          # context: backend          # optional, default "."
          password: ${{ secrets.REGISTRY_PASSWORD }}
```

### Requirements
- Org secret `REGISTRY_PASSWORD` (Harbor `admin` password) — already set at org level.
- A Harbor project matching `<slug>` must exist.
- An online Actions runner with label `ubuntu-latest`.
- This repo (`ci`) must be readable by the runner — kept **public**.

### Inputs
| input | default | meaning |
|-------|---------|---------|
| `image` | (required) | image path without registry, e.g. `vpsmanager/vpsmanager_b` |
| `context` | `.` | build context / Dockerfile dir |
| `registry` | `harbor.m0.mumble.cloud` | registry host |
| `username` | `admin` | registry user |
| `password` | (required) | registry password (pass `secrets.REGISTRY_PASSWORD`) |
| `build-args` | | extra build args, one `KEY=value` per line |
| `secret-files` | | BuildKit secrets from files on the runner, one `id=path` per line (see below) |
| `sourcemaps` | `false` | `true` = upload the frontend sourcemaps after the push (see below) |
| `sourcemaps-stage` | `build` | Dockerfile stage holding the built files with the `.map` |
| `sourcemaps-path` | `/app/dist` | directory of the built files in that stage |
| `sourcemaps-url-prefix` | `~/` | URL prefix of those files in the browser |
| `sourcemaps-required` | `false` | `true` = a failed upload fails the job (default: warning only) |
| `sentry-auth-token` | | tracker token with `project:releases` (`secrets.SENTRY_AUTH_TOKEN`) |
| `sentry-url` | `https://errors.mumble.group` | tracker URL (`vars.SENTRY_URL`) |
| `sentry-org` | `mumble` | organization slug on the tracker (`vars.SENTRY_ORG`) |
| `sentry-project` | | project slug on the tracker (`vars.SENTRY_PROJECT`) |
| `sentry-cli-version` | `2.58.6` | `@sentry/cli` used for the upload |

Every build gets the build args `GIT_COMMIT`, `BUILD_DATE`, `SENTRY_RELEASE` and `VITE_RELEASE`
(the last two = commit sha: the release the SDK reports and the sourcemaps are uploaded with).

## Build secrets (private registries)

A dependency from a private registry (e.g. the Nuxt layer `@mumble/nuxt-name-com` on the Gitea
npm registry) needs a token during the build. It goes in as a BuildKit secret, never as a build
arg (those end up in the image metadata) and never copied into the context. Write the file in a
step before the action, pass its path:

```yaml
      - name: npm registry credentials for the build
        env:
          NPM_REGISTRY_TOKEN: ${{ secrets.NPM_REGISTRY_TOKEN }}
        run: |
          umask 077
          printf '@mumble:registry=https://git.mumble.group/api/packages/mumble-group/npm/\n//git.mumble.group/api/packages/mumble-group/npm/:_authToken=%s\n' "$NPM_REGISTRY_TOKEN" > "$RUNNER_TEMP/.npmrc"
      - uses: MumbleGroup/ci-action@main
        with:
          image: <slug>/<slug>_f
          secret-files: |
            npmrc=${{ runner.temp }}/.npmrc
```

```dockerfile
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc,required=true \
    pnpm install --frozen-lockfile
```

The sourcemap upload rebuilds its stage with the same secrets.

## Sourcemaps (GlitchTip / Sentry)

Stack traces of a minified frontend are unreadable without the sourcemaps. With `sourcemaps: true`
the action, after pushing the image, rebuilds the `sourcemaps-stage` of the Dockerfile (same build
args, so it comes from the cache and the file names match the pushed image), copies
`sourcemaps-path` out of it and uploads it with `@sentry/cli`: release = commit sha, created and
linked to the project, then finalized. A failed upload is a warning: the image is already pushed.

The `.map` files must never be in the final image (the source code would be public). Standard
Vite frontend:

```js
// vite.config.js
export default defineConfig({ build: { sourcemap: 'hidden' } })   // .map files, no reference in the .js
```

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
ARG VITE_RELEASE
ENV VITE_RELEASE=$VITE_RELEASE
RUN npm run build

# what is published: the same files without the .map
FROM build AS public
RUN find /app/dist -name '*.map' -delete

FROM nginx:alpine
COPY --from=public /app/dist /usr/share/nginx/html
```

The SDK reports the same release: `Sentry.init({ ..., release: import.meta.env.VITE_RELEASE })`.

Workflow step (the token and the variables are set on the repo by MumbleCode's
`ensure_error_tracking_projects`, nobody copies them):

```yaml
      - uses: MumbleGroup/ci-action@main
        with:
          image: <slug>/<slug>_f
          username: robot$mumble-ci
          password: ${{ secrets.HARBOR_REGISTRY_PASSWORD }}
          build-args: |
            VITE_SENTRY_DSN=${{ vars.VITE_SENTRY_DSN }}
          sourcemaps: true
          sentry-auth-token: ${{ secrets.SENTRY_AUTH_TOKEN }}
          sentry-url: ${{ vars.SENTRY_URL }}
          sentry-org: ${{ vars.SENTRY_ORG }}
          sentry-project: ${{ vars.SENTRY_PROJECT }}
```

Check after the deploy: `curl -o /dev/null -w '%{http_code}' https://<site>/assets/<file>.js.map`
must give 404 (or the SPA's index.html, never the map), and a new error on the tracker shows the
original file and line.
