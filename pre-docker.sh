#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$BASE_DIR/.env"

echo "PRE-Docker setup (Ubuntu 24.04). Creating .env file..."
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

# 6. Generate secrets
POSTGRES_PASSWORD=$(openssl rand -base64 32)
INSTANCE_SECRET=$(openssl rand -hex 32)

# 7. Ask for Cloudflare token (will not be displayed)
read -r -p $'Paste your Cloudflare API token (DNS:Edit for doctosaurus.com). It will not be displayed:\n' -s CF_TOKEN
echo
if [ -z "$CF_TOKEN" ]; then
  echo "ERROR: Cloudflare token is empty. Re-run and paste token."
  exit 1
fi

# 8. Create .env file with secrets
cat > "$ENV_FILE" <<EOF
# Postgres Configuration
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Convex Backend Configuration
INSTANCE_SECRET=$INSTANCE_SECRET

# Convex Dashboard (placeholder - will be filled after admin key generation)
CONVEX_SELF_HOSTED_ADMIN_KEY=placeholder-until-generated

# Cloudflare Configuration
CLOUDFLARE_API_TOKEN=$CF_TOKEN
EOF

echo "Created $ENV_FILE with generated secrets."
echo

# 9. UFW (optional) - allow 22,80,443
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 22/tcp
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw --force enable
fi

# 10. Show next steps
echo "PREP DONE."
echo " - Generated POSTGRES_PASSWORD: (hidden, saved in .env)"
echo " - Generated INSTANCE_SECRET: (hidden, saved in .env)"
echo " - Saved CLOUDFLARE_API_TOKEN: (hidden, saved in .env)"
echo
echo "Start stack now with:"
echo "  cd $BASE_DIR"
echo "  docker compose up -d --pull always"
echo
echo "After containers are healthy, generate and inject admin key:"
echo "  ./set-admin-key.sh AUTO"
echo
echo "Or manually:"
echo "  docker compose exec backend ./generate_admin_key.sh"
echo "  ./set-admin-key.sh '<generated-key>'"
echo
echo "You can inspect logs with: docker compose logs -f"
