#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"

echo "PRE-Docker setup (Ubuntu 24.04). Files: $COMPOSE_FILE"
echo

# 1. Update & prerequisites
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release apt-transport-https

# 2. Add Docker APT repo (official)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture)
UBU_CODENAME=$(lsb_release -cs || echo "lunar")
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $UBU_CODENAME stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 3. Enable docker
sudo systemctl enable --now docker

# 4. Add local user to docker group (may need logout/login)
if ! id -nG "$USER" | grep -qw docker; then
  echo "Adding $USER to docker group (you may need to log out/in)"
  sudo usermod -aG docker "$USER"
fi

# 5. Create host directories for easy backups
mkdir -p "$BASE_DIR/convex-data" "$BASE_DIR/pgdata" "$BASE_DIR/caddy_data" "$BASE_DIR/caddy_config"
sudo chown -R "$USER":"$USER" "$BASE_DIR/convex-data" "$BASE_DIR/pgdata" "$BASE_DIR/caddy_data" "$BASE_DIR/caddy_config"
chmod 700 "$BASE_DIR/convex-data" "$BASE_DIR/pgdata"

# 6. Ensure compose file exists
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "ERROR: $COMPOSE_FILE not found. Paste the provided docker-compose.yml into $BASE_DIR and run this script again."
  exit 1
fi

# 7. Ask for Cloudflare token (we will inject it)
read -r -p $'Paste your Cloudflare API token (DNS:Edit for doctosaurus.com). It will not be displayed:\n' -s CF_TOKEN
echo
if [ -z "$CF_TOKEN" ]; then
  echo "ERROR: Cloudflare token is empty. Re-run and paste token."
  exit 1
fi

# 8. Generate secrets
INSTANCE_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 16)

# 9. Backup compose and inject values
cp -n "$COMPOSE_FILE" "$COMPOSE_FILE.bak" || true
# Use sed -i (GNU sed expected on Ubuntu)
sed -i "s/REPLACE_WITH_INSTANCE_SECRET/$INSTANCE_SECRET/g" "$COMPOSE_FILE"
sed -i "s/REPLACE_WITH_POSTGRES_PASSWORD/$POSTGRES_PASSWORD/g" "$COMPOSE_FILE"
# Escape any slashes in token for safe sed replacement
escaped_token=$(printf '%s\n' "$CF_TOKEN" | sed -e 's/[\/&]/\\&/g')
sed -i "s/REPLACE_WITH_CLOUDFLARE_API_TOKEN/$escaped_token/g" "$COMPOSE_FILE"

echo "Injected INSTANCE_SECRET, POSTGRES_PASSWORD, and Cloudflare token into docker-compose.yml."
echo

# 10. UFW (optional) - allow 22,80,443
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
fi

# 11. Show next steps
echo "PREP DONE."
echo " - Generated INSTANCE_SECRET: $INSTANCE_SECRET"
echo " - Generated POSTGRES_PASSWORD: (hidden)"
echo
echo "Start stack now with:"
echo "  cd $BASE_DIR"
echo "  docker compose up -d --pull"
echo
echo "After containers are up, either:"
echo " A) generate admin key inside backend:"
echo "    docker compose exec backend ./generate_admin_key.sh"
echo "    (copy printed key and run the set-admin-key.sh script below)"
echo
echo " B) Or run set-admin-key.sh with an existing admin key to inject it and restart dashboard."
echo
echo "You can inspect logs with: docker compose logs -f"
