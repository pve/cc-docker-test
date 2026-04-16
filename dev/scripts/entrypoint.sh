#!/usr/bin/env bash
# entrypoint.sh — runs as PID 1 inside cc-dev
# Writes authorized_keys from SSH_AUTHORIZED_KEY env var, then starts sshd.

set -euo pipefail

# Inject the user's public key so they can SSH straight into the container
if [ -n "${SSH_AUTHORIZED_KEY:-}" ]; then
    echo "${SSH_AUTHORIZED_KEY}" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
else
    echo "WARNING: SSH_AUTHORIZED_KEY is not set. You will not be able to SSH into this container."
fi

# Generate host keys if not already present (needed on first start)
ssh-keygen -A

exec /usr/sbin/sshd -D
