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
