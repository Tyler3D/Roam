#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-cozy-postgres}"
CONTAINER_NAME="${CONTAINER_NAME:-cozy-postgres}"
POSTGRES_USER="admin"
POSTGRES_PASSWORD="admin"
POSTGRES_DB="cozycorner"
POSTGRES_PORT="5432"

docker build -t "$IMAGE_NAME" -f infra/Dockerfile .

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker start "$CONTAINER_NAME" >/dev/null
  echo "Postgres container '${CONTAINER_NAME}' started."
  exit 0
fi

docker run -d \
  --name "$CONTAINER_NAME" \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -p "${POSTGRES_PORT}:5432" \
  -v "${CONTAINER_NAME}-data:/var/lib/postgresql/data" \
  "$IMAGE_NAME" >/dev/null

echo "Postgres container '${CONTAINER_NAME}' created and started."

