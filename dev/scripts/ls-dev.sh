#!/usr/bin/env bash
# ls-dev.sh — list all cc-dev instances and their SSH ports

set -euo pipefail

echo "INSTANCE          STATUS     SSH PORT   CONTAINER"
echo "────────────────  ─────────  ─────────  ─────────────────────"

docker ps -a \
    --filter "label=cc.env=dev" \
    --format '{{.Label "cc.instance"}}\t{{.Status}}\t{{.Label "cc.ssh.port"}}\t{{.Names}}' \
| while IFS=$'\t' read -r instance status port name; do
    printf "%-16s  %-9s  %-9s  %s\n" "${instance}" "${status:0:9}" "${port}" "${name}"
done
