# Tasks

## High priority

- **#1 Fork ahead of origin**: `setup-dev.sh` syncs `main` from upstream but never pushes to `origin/main`. Add `git push origin main` after the `--ff-only` merge.

## Medium priority

- ~~**#2 Claude Code cannot self-update in Boiler**~~

## Low priority

- ~~**#3 Shell alias for yolo mode**~~
- **#4 Docker credential store warning**: `docker login ghcr.io` stores credentials unencrypted in `/root/.docker/config.json`. Accept the risk (container is ephemeral) or configure a credential helper.
- **#5 Stale `/root/` paths in README**: The Boiler section still references `/root/workspace`, `/root/scripts/`, `/root/.nanobot/` etc. These should be `/home/claude/workspace`, `/opt/cc/scripts/`, `/home/claude/.nanobot/`.

---

## Completed

| # | Task                     | Completed  | Note                                                                                               |
|---|--------------------------|------------|----------------------------------------------------------------------------------------------------|
| 2 | CC self-update in Boiler | 2026-06-03 | npm prefix -> `/home/claude/.npm-global` via `.npmrc`; system CC stays as fallback; no volume      |
| 3 | yolo alias               | 2026-06-03 | `/etc/profile.d/cc-dev.sh` baked into image                                                        |
