#!/usr/bin/env bash
# entrypoint.sh — runs as PID 1 inside cc-dev
# Writes authorized_keys and environment for SSH sessions, then starts sshd.

set -euo pipefail

# Inject the user's public key so they can SSH straight into the container
if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
    mkdir -p /home/claude/.ssh
    echo "${SSH_AUTHORIZED_KEY}" > /home/claude/.ssh/authorized_keys
    chmod 600 /home/claude/.ssh/authorized_keys
else
    echo "WARNING: SSH_AUTHORIZED_KEY is not set. You will not be able to SSH into this container."
fi

# Write env vars to ~/.ssh/environment so SSH sessions inherit them.
# Requires PermitUserEnvironment yes in sshd_config (set in Dockerfile).
rm -f /home/claude/.ssh/environment
for var in GITHUB_TOKEN GITHUB_USER FORK_REPO_PATH UPSTREAM_URL REGISTRY \
           GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
           CLAUDE_CODE_OAUTH_TOKEN; do
    if [ -n "${!var:-}" ]; then
        echo "${var}=${!var}" >> /home/claude/.ssh/environment
    fi
done
chmod 600 /home/claude/.ssh/environment

# Persist /home/claude/.claude.json inside the home volume so it survives rebuilds.
# Claude Code writes config here; the home volume covers /home/claude/.claude/ (a directory)
# but not /home/claude/.claude.json (a separate file). We store the real file inside the
# volume and symlink it back.
CLAUDE_JSON_STORE="/home/claude/.claude/.claude.json"
CLAUDE_JSON_LINK="/home/claude/.claude.json"
if [ -f "${CLAUDE_JSON_LINK}" ] && [ ! -L "${CLAUDE_JSON_LINK}" ]; then
    mv "${CLAUDE_JSON_LINK}" "${CLAUDE_JSON_STORE}"
fi
[ -f "${CLAUDE_JSON_STORE}" ] || echo '{}' > "${CLAUDE_JSON_STORE}"
ln -sf "${CLAUDE_JSON_STORE}" "${CLAUDE_JSON_LINK}"

# Ensure claude owns its home directory contents
chown -R claude:claude /home/claude

# Generate host keys if not already present (needed on first start)
ssh-keygen -A

exec /usr/sbin/sshd -D
