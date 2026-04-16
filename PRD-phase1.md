# PRD: Phase 1 — Dev Environment

## Overview
A containerized dev environment on a single remote amd64 host where Claude Code lives inside `cc-dev`, has full control over the nanobot codebase, and packages built images to ghcr.io for downstream environments.

---

## Workflow

```
cc-dev container (remote host)
  │
  ├── edit code in /workspace (nanobot fork)
  ├── docker build → nanobot-dev image
  ├── docker run → ephemeral nanobot-dev-* containers (test/verify)
  ├── read all logs (build logs, container stdout/stderr, nanobot app logs)
  ├── fix, rebuild, re-test
  ├── git commit + push → user's fork on GitHub
  ├── gh pr create → upstream PR
  └── docker push → ghcr.io/<user>/nanobot:<tag>
                         │
                    [Phase 2: acc pulls this image]
```

---

## Container: cc-dev

### Base image
`ubuntu:24.04` (amd64)

### Tools installed in image
| Tool | Purpose |
|------|---------|
| Claude Code CLI (`claude`) | AI coding agent |
| docker CLI | Build images, run/stop/inspect containers, read logs |
| git | Version control |
| gh CLI | GitHub PRs, releases, repo management |
| curl, jq | Scripting and API calls |
| vim | In-container file editing fallback |
| openssh-client | Git over SSH to GitHub |

> Note: Only the Docker **client** binary is installed. The host Docker daemon socket is mounted in.

### Mounts / Volumes
| Mount | Type | Path in container | Purpose |
|-------|------|-------------------|---------|
| `/var/run/docker.sock` | bind (host socket) | `/var/run/docker.sock` | Docker API access |
| `cc-dev-workspace` | named volume | `/workspace` | Nanobot fork source code (persists across container restarts) |
| `cc-dev-home` | named volume | `/root/.claude` | CC config, memory, CLAUDE.md, settings |
| `cc-dev-ssh` | named volume | `/root/.ssh` | SSH keypair for GitHub auth |

### Environment variables (passed at runtime)
| Variable | Purpose |
|----------|---------|
| `GITHUB_TOKEN` | GitHub PAT with `repo` + `packages:write` + `read:packages` scope. Used by gh CLI and docker login to ghcr.io |
| `GIT_AUTHOR_NAME` | Git commit identity |
| `GIT_AUTHOR_EMAIL` | Git commit identity |
| `FORK_REPO` | e.g. `github.com/youruser/nanobot` |

### Network
- Attached to `nanobot-dev-net` only
- No access to `nanobot-acc-net` or `nanobot-prod-net`

### Startup
Container runs persistently (does not exit). Entry: `sleep infinity` or a shell init script that keeps it alive. User enters via:
```bash
# From remote host
docker exec -it cc-dev bash

# Or via VS Code: Remote-SSH to host → Dev Containers → Attach to cc-dev
```

---

## Container: nanobot-dev-* (ephemeral)

Spun up by cc-dev for testing. Short-lived — always `--rm`.

### Image
Built by cc-dev from `/workspace`:
```bash
docker build -t nanobot-dev /workspace
```

### Run pattern
```bash
docker run --rm \
  --network nanobot-dev-net \
  -v nanobot-dev-data:/root/.nanobot \
  --name nanobot-dev-test-<suffix> \
  nanobot-dev \
  agent -m "Hello!"
```

### Named volume
`nanobot-dev-data` — stores nanobot config (`config.json`), workspace, WhatsApp auth. Persists between test runs.

---

## Docker Network
- Name: `nanobot-dev-net`
- Driver: `bridge`
- Scope: dev environment only
- Members: `cc-dev`, `nanobot-dev-*` containers

---

## GitHub Auth

### SSH key (for git push/pull)
- Generated once and stored in `cc-dev-ssh` volume
- Public key added to the nanobot fork as a **deploy key** with write access
- `git remote` uses `git@github.com:<user>/nanobot.git`

### GITHUB_TOKEN (for gh CLI + GHCR)
- Fine-grained PAT or classic PAT
- Required scopes: `repo`, `packages:write`, `read:packages`
- Passed as env var at container startup
- `gh auth login --with-token <<< $GITHUB_TOKEN` run on first start
- `echo $GITHUB_TOKEN | docker login ghcr.io -u <github-user> --password-stdin` for image push

---

## Image Packaging (ghcr.io)

After code is working and tests pass, CC packages the image:

```bash
# Tag with git short SHA for traceability
GIT_SHA=$(git -C /workspace rev-parse --short HEAD)

docker build -t ghcr.io/<user>/nanobot:dev-${GIT_SHA} /workspace
docker push ghcr.io/<user>/nanobot:dev-${GIT_SHA}

# Also update floating :dev tag
docker tag ghcr.io/<user>/nanobot:dev-${GIT_SHA} ghcr.io/<user>/nanobot:dev
docker push ghcr.io/<user>/nanobot:dev
```

Tags:
- `ghcr.io/<user>/nanobot:dev-<sha>` — immutable, per-commit
- `ghcr.io/<user>/nanobot:dev` — floating, always latest dev build
- `ghcr.io/<user>/nanobot:<semver>` — (future) stable release for acc/prod

---

## What CC Can See in Dev

| Capability | How |
|-----------|-----|
| Nanobot source code | `/workspace` (full read/write) |
| Build logs | `docker build` stdout |
| Container stdout/stderr | `docker logs nanobot-dev-test-*` |
| Nanobot app logs | Written to `/root/.nanobot/` in the `nanobot-dev-data` volume; readable via `docker run --rm -v nanobot-dev-data:/data alpine cat /data/...` |
| Docker events | `docker events --filter name=nanobot-dev-*` |
| Container state | `docker inspect`, `docker ps` |
| Git history | `git log`, `git diff` in `/workspace` |

---

## Files to Create

| File | Purpose |
|------|---------|
| `cc-docker-test/Dockerfile.cc-dev` | cc-dev container image |
| `cc-docker-test/docker-compose.dev.yml` | Orchestrates cc-dev + networking + volumes |
| `cc-docker-test/.env.dev.example` | Template for required env vars |
| `cc-docker-test/scripts/setup-dev.sh` | One-time remote host setup (create network, volumes, clone fork, init SSH key) |
| `cc-docker-test/scripts/package.sh` | Image build + tag + push to ghcr.io (run by CC inside cc-dev) |

---

## Setup Sequence (one-time, run on remote host)

1. Clone this repo to remote host
2. Copy `.env.dev.example` → `.env.dev`, fill in tokens and user details
3. `docker compose -f docker-compose.dev.yml up -d` → creates network, volumes, starts cc-dev
4. `docker exec cc-dev /scripts/setup-dev.sh` → clones fork, configures git, logs into gh and ghcr.io, generates SSH key
5. User adds displayed public key to GitHub fork as deploy key
6. `docker exec -it cc-dev bash` → CC is ready

---

## Acceptance Criteria for Phase 1

- [ ] `cc-dev` container starts and stays running
- [ ] CC can edit files in `/workspace` and see changes persist after container restart
- [ ] `docker build` of nanobot succeeds from inside cc-dev
- [ ] Ephemeral `nanobot-dev-*` container runs and CC can read its logs
- [ ] `git push` to fork succeeds from inside cc-dev
- [ ] `gh pr create` works from inside cc-dev
- [ ] `docker push` to ghcr.io succeeds with correct tags
- [ ] cc-dev has no network path to `nanobot-acc-net` or `nanobot-prod-net`

---

## Open Questions / Decisions Deferred to Phase 2

- Nanobot config (provider + API key) for the dev volume — set up during onboard
- Promotion trigger: how acc picks up a new `:dev` tag from ghcr.io
- Whether `nanobot-dev-data` is pre-seeded from acc/prod config or starts fresh
