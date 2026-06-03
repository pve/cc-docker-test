# Why?

You want to run Claude code in YoLo mode on a branch of a git repository, that is

```shell
claude --dangerously-skip-permissions
```

This repo deploys containers on a remote host with Claude Code (CC) installed inside it.
So even your local Docker setup, if any, is not touched.

It was originally conceived for testing and developing *nanobot* instances.
That instance can fully control a nanobot instance, including viewing all its files and logfiles.

# Dev Environment

Claude Code runs inside `cc-dev-<instance>` containers on the remote host. Multiple named instances can run simultaneously — one per feature branch or experiment.

Three environments, each with a distinct role: **Bridge** (your laptop), **Deck** (the remote host), **Boiler** (inside the container).

---

```text
  BRIDGE                                       DECK
  (your laptop)                                (remote host, uid root)
 ┌────────────────────────────┐               ┌──────────────────────────────────────────────┐
 │  ~/.ssh/config             │ ─── :22 ─────▶│  dev/.env.dev                                │
 │  .env.dev                  │               │  ~/.ssh/authorized_keys                      │
 │                            │               │                                              │
 │  optionally:               │               │  BOILER                    BOILER            │
 │  Claude Code               │ ── :2222 ────▶│  ┌─────────────────┐    ┌─────────────────┐ │
 │                            │               │  │ CC              │    │ CC              │ │
 └────────────────────────────┘               │  │ workspace/      │    │ workspace/      │ │
                                              │  │ .claude/        │    │ .claude/        │ │
                                              │  │ uid claude      │    │ uid claude      │ │
                                              │  └─────────────────┘    └─────────────────┘ │
                                              └──────────────────────────────────────────────┘

                                                          │ PAT
                                                          ▼
                                                 ┌─────────────────┐
                                                 │     GitHub      │
                                                 └─────────────────┘
```

---

## GitHub Token

Everything in the dev environment authenticates with a single GitHub Personal Access Token (PAT). It is stored in `.env.dev` on the remote host and injected into each container at startup.

### Creating the token

Use a **classic PAT** — fine-grained PATs do not yet fully support pushing to `ghcr.io`.

Go to **[github.com/settings/tokens/new](https://github.com/settings/tokens/new)** and select these scopes:

| Scope | Why |
|-------|-----|
| `repo` | Clone, push, PRs, and deploy key management via API |
| `write:packages` | Push images to `ghcr.io` |
| `read:packages` | Pull images from `ghcr.io` |

Set an expiry (90 days recommended) and add a calendar reminder to rotate it before it expires.

### Where it goes

Paste the generated token into `.env.dev` as `GITHUB_TOKEN`. It is passed to each container as an environment variable and used by:

- `gh auth login` — GitHub CLI
- `docker login ghcr.io` — container registry push/pull
- `gh api repos/.../keys` — deploy key management

`.env.dev` is listed in `.gitignore` and must never be committed.

---

## Bridge — Local machine (your laptop)

**Role:** SSH client only. Nothing runs here except your terminal and optionally VS Code.
Presumably though, you can run another Claude Code here to orchestrate your experiments.

### One-time setup

Add entries to `~/.ssh/config` for each container instance you create:

```
# Access to the remote host itself (for bootstrapping only)
Host nanobot-host
  HostName <remote-host>
  User <user>
  IdentityFile ~/.ssh/id_ed25519

# Access directly into a cc-dev container (ongoing work)
Host nanobot-dev
  HostName <remote-host>
  Port 2222
  User root
  IdentityFile ~/.ssh/id_ed25519
```
Note that the containers have the same IP address as their host.
After bootstrap, you only ever use the `nanobot-dev` (port 2222) entry — you SSH straight into the container, bypassing the host.

### Ongoing use after bootstrap

From the Bridge (your laptop):

```bash
ssh nanobot-dev          # terminal into cc-dev-main - The 'Deck'
# or: open VS Code → Remote-SSH → nanobot-dev
```

---

## Deck — Remote host (port 22, bootstrap only)

**Role:** Docker daemon host. You log in here once to bootstrap the cc-dev image and first instance (the 'Boiler'). After that, Claude Code manages everything from inside the container.

### Prerequisites

- QoL: `.ssh/authorized_hosts` filled in
- Docker installed and running, including Docker compose
- Git installed
- Ports 2222–2299 open in firewall
- QoL: update the `/etc/hostname`

### One-time bootstrap

```bash
# Login to the Deck
ssh hetznerhost.griddlejuiz.com

# Clone this repo, the infrastructure repo (public, no auth needed)
git clone https://github.com/pve/cc-yolo-docker.git /root/cc-yolo-docker
cd /root/cc-yolo-docker/dev

# Configure environment (copy example, fill in secrets)
cp .env.dev.example .env.dev
vim .env.dev    # fill in GITHUB_TOKEN, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, SSH_AUTHORIZED_KEY
# your dev environment might need more secrets, see below
# alternatively
# ssh alpine102 git clone https://github.com/pve/cc-yolo-docker.git /root/cc-yolo-docker
# scp .env.dev alpine102:/root/cc-yolo-docker/dev

# Build the cc-dev image locally (architecture)
docker build -f Dockerfile.cc-dev -t cc-dev /root/cc-yolo-docker/dev

# Spawn the first dev instance, and name it. QoL: name it after the branch you'll work on
scripts/spawn-dev.sh main
```

`spawn-dev.sh` prints the assigned SSH port and the `~/.ssh/config` snippet to add locally.

To update the infrastructure later: `git pull` in `/root/cc-yolo-docker`, then rebuild the image.

That's all that happens on the Deck. From here on, Claude Code inside the Boiler manages the dev environment.

---

## Boiler — Inside cc-dev container (port 2222, ongoing)

**Role:** Where all development happens.
Claude Code has full control: code, Docker, git, gh CLI, package builds.

### Prerequisites

None, as all are included in the Dockerfile.

### One-time setup (first SSH session)

This sets up the git repo.

```bash

scp <local files> nanobot-main:
ssh nanobot-main

/opt/cc/scripts/setup-dev.sh
```
or
```
ssh -p <port> -i 
```

Alternatively, run this through 
```
docker exec -u claude cc-dev-dev1 /opt/cc/scripts/setup-dev.sh
```

`setup-dev.sh` is fully automated — no browser, no manual steps:
- Generates SSH keypair, adds it as a deploy key to `pve/nanobot-ai` via GitHub API
- Clones the fork into `/root/workspace`, adds upstream remote, syncs with `HKUDS/nanobot`
- Authenticates gh CLI and logs into ghcr.io — both using `GITHUB_TOKEN`

After this, run `claude` and CC takes over.
This was all created to make `claude --dangerously-skip-permissions` less dangerous.

### What Claude Code can do from inside the container

| Task | How |
|------|-----|
| Edit nanobot source | Full read/write on `/root/workspace` |
| Build + test nanobot | `docker build` + `docker run --rm` (via host Docker socket) |
| Read all logs | `docker logs`, files in `/root/.nanobot/` |
| Commit and push | `git` in `/root/workspace`, SSH key already configured |
| Open pull requests | `gh pr create` |
| Package image to registry | `/root/scripts/package.sh` → pushes to `ghcr.io/pve/nanobot-ai` |
| Spawn additional dev instances | `/root/scripts/spawn-dev.sh feature-x` (has Docker socket) |
| List running instances | `/root/scripts/ls-dev.sh` |
| Sync fork with upstream | `git fetch upstream && git merge --ff-only upstream/main` |

### Ongoing workflow

```bash
ssh nanobot-main # or Connect to: from VScode, which picks up from ~/.ssh/config, and gives you a file browser as well
claude                              # start Claude Code
claude --dangerously-skip-permissions # Run CC in yolo mode.

# CC works autonomously — edits code, runs tests, reads logs, fixes issues
# When ready to package for the next stage (acceptance or production):
/root/scripts/package.sh                 # builds + pushes ghcr.io/pve/nanobot-ai:dev-<sha>

# To work on a parallel branch, CC spawns a new instance:
/root/scripts/spawn-dev.sh feature-x    # creates cc-dev-feature-x, prints new port
```
---

## Instance management

From the Deck:

```bash
# List all dev instances and their SSH ports
/root/scripts/ls-dev.sh

# Stop an instance (preserves volumes)
docker compose -p cc-dev-feature-x -f /path/to/docker-compose.dev.yml stop

# Remove an instance and all its data (destructive)
docker compose -p cc-dev-feature-x -f /path/to/docker-compose.dev.yml down -v
```

---

## File reference

| File | Used by | Purpose |
|------|---------|---------|
| `Dockerfile.cc-dev` | Remote host (build time) | cc-dev image definition |
| `docker-compose.dev.yml` | `spawn-dev.sh` | Declarative container spec |
| `.env.dev.example` | You | Template for secrets and identity |
| `scripts/entrypoint.sh` | Container (PID 1) | Injects `authorized_keys`, starts sshd |
| `scripts/spawn-dev.sh` | Remote host or CC in container | Create a named dev instance |
| `scripts/ls-dev.sh` | Remote host or CC in container | List instances + SSH ports |
| `scripts/setup-dev.sh` | CC in container (once) | Clone fork, auth, deploy key, render CLAUDE.md — fully automated |
| `scripts/package.sh` | CC in container | Build + tag + push image to ghcr.io |
| `CLAUDE.md.template` | `setup-dev.sh` | Template rendered into `/home/claude/CLAUDE.md` on first setup |

---

## Tips

### Tunnel a port from the Boiler to your laptop

If a server is running on port 8000 in the Boiler and port 8000 is already in use locally:

```bash
ssh -L 8001:localhost:8000 alpine323-nano
```

`http://localhost:8001` on the Bridge hits port 8000 in the Boiler. The tunnel goes directly over the SSH connection — no extra port mapping needed on the Deck.
