#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-cozy-postgres}"
VOLUME_NAME="${VOLUME_NAME:-${CONTAINER_NAME}-data}"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker rm -f "$CONTAINER_NAME" >/dev/null
  echo "Removed container '${CONTAINER_NAME}'."
else
  echo "Container '${CONTAINER_NAME}' not found."
fi

if docker volume ls --format '{{.Name}}' | grep -q "^${VOLUME_NAME}$"; then
  docker volume rm "$VOLUME_NAME" >/dev/null
  echo "Removed volume '${VOLUME_NAME}'."
else
  echo "Volume '${VOLUME_NAME}' not found."
fi

