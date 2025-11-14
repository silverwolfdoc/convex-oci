#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <ADMIN_KEY|AUTO>"
  echo "  ADMIN_KEY : your convex admin key string"
  echo "  AUTO      : run backend generate_admin_key.sh and capture its output"
  exit 1
fi

KEY_ARG="$1"

if [ "$KEY_ARG" = "AUTO" ]; then
  echo "Generating admin key by running the container helper..."
  # start backend if not running
  docker compose up -d backend
  sleep 2
  # run the script and capture output
  ADMIN_KEY=$(docker compose exec backend ./generate_admin_key.sh 2>/dev/null | sed -n 's/.*\(sk_live[[:alnum:]]\{0,200\}\).*/\1/p')
  # fall back to raw output if pattern didn't match
  if [ -z "$ADMIN_KEY" ]; then
    ADMIN_KEY=$(docker compose exec backend ./generate_admin_key.sh 2>/dev/null || true)
  fi
  if [ -z "$ADMIN_KEY" ]; then
    echo "Failed to auto-generate admin key. Run the generate script manually:"
    echo "  docker compose exec backend ./generate_admin_key.sh"
    exit 1
  fi
  echo "Captured admin key."
else
  ADMIN_KEY="$KEY_ARG"
fi

# backup compose
cp -n "$COMPOSE_FILE" "$COMPOSE_FILE.admin.bak" || true

# replace existing placeholder or prior key (simple sed)
escaped_key=$(printf '%s\n' "$ADMIN_KEY" | sed -e 's/[\/&]/\\&/g')
if grep -q "REPLACE_WITH_ADMIN_KEY" "$COMPOSE_FILE"; then
  sed -i "s/REPLACE_WITH_ADMIN_KEY/$escaped_key/g" "$COMPOSE_FILE"
else
  # attempt to replace any previous CONVEX_SELF_HOSTED_ADMIN_KEY line
  sed -i "s/CONVEX_SELF_HOSTED_ADMIN_KEY=.*/CONVEX_SELF_HOSTED_ADMIN_KEY=$escaped_key/g" "$COMPOSE_FILE" || true
fi

echo "Injected admin key into docker-compose.yml (backed up to docker-compose.yml.admin.bak)."

# restart dashboard
echo "Restarting dashboard service..."
docker compose up -d dashboard

echo "Waiting for services to become ready..."
# Wait for postgres healthy
for i in {1..30}; do
  s=$(docker inspect --format='{{json .State.Health.Status}}' $(docker compose ps -q postgres) 2>/dev/null || echo null)
  if echo "$s" | grep -q healthy; then
    echo "Postgres healthy."
    break
  fi
  echo -n "."
  sleep 2
done

# Wait for backend port to respond locally
for i in {1..30}; do
  if curl -sS --connect-timeout 2 http://127.0.0.1:3210/ >/dev/null 2>&1; then
    echo "Backend responding on 127.0.0.1:3210"
    break
  fi
  echo -n "."
  sleep 1
done

# Check dashboard locally
for i in {1..30}; do
  if curl -sS --connect-timeout 2 http://127.0.0.1:6791/ >/dev/null 2>&1; then
    echo "Dashboard responding on 127.0.0.1:6791"
    break
  fi
  echo -n "."
  sleep 1
done

echo
echo "Done. Quick status:"
docker compose ps

echo
echo "If you want to revert the admin key injection, restore the backup:"
echo "  cp $COMPOSE_FILE.admin.bak $COMPOSE_FILE && docker compose up -d dashboard"
