# mumble-group / ci

Centralized Gitea Actions for Mumble projects.

## Reusable workflow: build & push Docker image

Builds a Docker image and pushes it to Harbor (`harbor.m0.mumble.cloud`) with
`:latest` and `:<commit-sha>` tags. Logic lives here once — projects just call it.

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
    uses: mumble-group/ci/.gitea/workflows/build-image.yml@main
    with:
      image: <slug>/<slug>_b      # e.g. vpsmanager/vpsmanager_b
      # context: backend          # optional, default "."
    secrets:
      registry_password: ${{ secrets.REGISTRY_PASSWORD }}
```

### Requirements
- Org secret `REGISTRY_PASSWORD` (Harbor `admin` password) — already set at org level.
- A Harbor project matching `<slug>` must exist.
- An online Actions runner with label `ubuntu-latest`.

### Inputs
| input | default | meaning |
|-------|---------|---------|
| `image` | (required) | image path without registry, e.g. `vpsmanager/vpsmanager_b` |
| `context` | `.` | build context / Dockerfile dir |
| `registry` | `harbor.m0.mumble.cloud` | registry host |
| `username` | `admin` | registry user |
