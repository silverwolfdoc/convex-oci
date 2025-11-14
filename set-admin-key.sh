#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$BASE_DIR/.env"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <ADMIN_KEY|AUTO>"
  echo "  ADMIN_KEY : your convex admin key string (e.g., sk_live_...)"
  echo "  AUTO      : run backend generate_admin_key.sh and capture its output"
  exit 1
fi

KEY_ARG="$1"

if [ "$KEY_ARG" = "AUTO" ]; then
  echo "Generating admin key by running the container helper..."
  # start backend if not running
  docker compose up -d backend
  sleep 3
  # run the script and capture output
  ADMIN_KEY=$(docker compose exec backend ./generate_admin_key.sh 2>/dev/null | grep -oP 'sk_live[a-zA-Z0-9_]{0,200}' | head -1 || true)
  # fall back to raw output if pattern didn't match
  if [ -z "$ADMIN_KEY" ]; then
    ADMIN_KEY=$(docker compose exec backend ./generate_admin_key.sh 2>/dev/null || true)
  fi
  if [ -z "$ADMIN_KEY" ]; then
    echo "Failed to auto-generate admin key. Run the generate script manually:"
    echo "  docker compose exec backend ./generate_admin_key.sh"
    exit 1
  fi
  # Trim whitespace from admin key
  ADMIN_KEY=$(echo "$ADMIN_KEY" | xargs)
  echo "Captured admin key: $ADMIN_KEY"
else
  # Trim whitespace from manually provided admin key
  ADMIN_KEY=$(echo "$KEY_ARG" | xargs)
fi

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Run pre-docker.sh first."
  exit 1
fi

# Backup .env
cp -n "$ENV_FILE" "$ENV_FILE.bak" || true

# Update or add CONVEX_SELF_HOSTED_ADMIN_KEY in .env
if grep -q "^CONVEX_SELF_HOSTED_ADMIN_KEY=" "$ENV_FILE"; then
  # Use platform-specific sed (macOS uses -i '', Linux uses -i)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^CONVEX_SELF_HOSTED_ADMIN_KEY=.*/CONVEX_SELF_HOSTED_ADMIN_KEY=$ADMIN_KEY/" "$ENV_FILE"
  else
    sed -i "s/^CONVEX_SELF_HOSTED_ADMIN_KEY=.*/CONVEX_SELF_HOSTED_ADMIN_KEY=$ADMIN_KEY/" "$ENV_FILE"
  fi
else
  echo "CONVEX_SELF_HOSTED_ADMIN_KEY=$ADMIN_KEY" >> "$ENV_FILE"
fi

echo "Injected admin key into $ENV_FILE (backed up to $ENV_FILE.bak)."

# restart dashboard to pick up new .env
echo "Restarting dashboard service..."
docker compose up -d dashboard

echo "Waiting for services to become ready..."
# Wait for postgres healthy
for i in {1..30}; do
  s=$(docker inspect --format='{{json .State.Health.Status}}' $(docker compose ps -q postgres) 2>/dev/null || echo null)
  if echo "$s" | grep -q healthy; then
    echo "✓ Postgres healthy."
    break
  fi
  echo -n "."
  sleep 2
done

# Wait for backend port to respond locally
for i in {1..30}; do
  if curl -sS --connect-timeout 2 http://127.0.0.1:3210/ >/dev/null 2>&1; then
    echo "✓ Backend responding on 127.0.0.1:3210"
    break
  fi
  echo -n "."
  sleep 1
done

# Check dashboard locally
for i in {1..30}; do
  if curl -sS --connect-timeout 2 http://127.0.0.1:6791/ >/dev/null 2>&1; then
    echo "✓ Dashboard responding on 127.0.0.1:6791"
    break
  fi
  echo -n "."
  sleep 1
done

echo
echo "Done. Quick status:"
docker compose ps

echo
echo "Dashboard admin key is now set. Access dashboard at: http://127.0.0.1:6791"
echo "Or via reverse proxy (if DNS configured): https://dashboard.doctosaurus.com"
echo
echo "If you want to revert, restore the backup:"
echo "  cp $ENV_FILE.bak $ENV_FILE && docker compose restart dashboard"
