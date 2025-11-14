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

# 8. Ask for domain configuration
read -r -p 'Enter your admin email for SSL certificates (e.g., admin@example.com): ' ADMIN_EMAIL
read -r -p 'Enter your API subdomain (e.g., api.example.com): ' API_DOMAIN
read -r -p 'Enter your dashboard subdomain (e.g., dashboard.example.com): ' DASHBOARD_DOMAIN
read -r -p 'Enter your site subdomain (e.g., site.example.com): ' SITE_DOMAIN

# Validate domains are not empty
if [ -z "$ADMIN_EMAIL" ] || [ -z "$API_DOMAIN" ] || [ -z "$DASHBOARD_DOMAIN" ] || [ -z "$SITE_DOMAIN" ]; then
  echo "ERROR: All domain fields are required. Please re-run the script."
  exit 1
fi

# Construct origin URLs
CLOUD_ORIGIN="https://$API_DOMAIN"
SITE_ORIGIN="https://$SITE_DOMAIN"

# 9. Generate POSTGRES_URL from postgres container credentials
# URL-encode the password (replace / with %2F and = with %3D)
ENCODED_PASSWORD=$(echo -n "$POSTGRES_PASSWORD" | sed 's/\//\%2F/g' | sed 's/=/\%3D/g')
POSTGRES_URL="postgres://convex:$ENCODED_PASSWORD@postgres:5432"

# 10. Create .env file with secrets
cat > "$ENV_FILE" <<EOF
# Postgres Configuration
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Convex Backend Configuration
INSTANCE_SECRET=$INSTANCE_SECRET

# Database Configuration
# Auto-generated for the local Postgres container
POSTGRES_URL=$POSTGRES_URL

# Convex Backend Origin URLs
CONVEX_CLOUD_ORIGIN=$CLOUD_ORIGIN
CONVEX_SITE_ORIGIN=$SITE_ORIGIN

# Convex Dashboard
NEXT_PUBLIC_DEPLOYMENT_URL=$CLOUD_ORIGIN

# Convex Dashboard (placeholder - will be filled after admin key generation)
CONVEX_SELF_HOSTED_ADMIN_KEY=placeholder-until-generated

# Cloudflare Configuration
CLOUDFLARE_API_TOKEN=$CF_TOKEN
EOF

echo "Created $ENV_FILE with generated secrets."
echo

# 12. Generate Caddyfile from template
CADDYFILE_TEMPLATE="$BASE_DIR/Caddyfile.template"
CADDYFILE="$BASE_DIR/Caddyfile"

if [ ! -f "$CADDYFILE_TEMPLATE" ]; then
  echo "ERROR: Caddyfile.template not found. Cannot generate Caddyfile."
  exit 1
fi

# Replace placeholders in template
sed -e "s|{{ADMIN_EMAIL}}|$ADMIN_EMAIL|g" \
    -e "s|{{API_DOMAIN}}|$API_DOMAIN|g" \
    -e "s|{{DASHBOARD_DOMAIN}}|$DASHBOARD_DOMAIN|g" \
    -e "s|{{SITE_DOMAIN}}|$SITE_DOMAIN|g" \
    "$CADDYFILE_TEMPLATE" > "$CADDYFILE"

echo "Generated $CADDYFILE with your domain configuration."
echo

# 11. UFW (optional) - allow 22,80,443
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
echo " - Saved POSTGRES_URL: (hidden, saved in .env)"
echo " - Saved CONVEX_CLOUD_ORIGIN: $CLOUD_ORIGIN"
echo " - Saved CONVEX_SITE_ORIGIN: $SITE_ORIGIN"
echo " - Saved CLOUDFLARE_API_TOKEN: (hidden, saved in .env)"
echo " - Generated Caddyfile with domains:"
echo "   - API: $API_DOMAIN"
echo "   - Dashboard: $DASHBOARD_DOMAIN"
echo "   - Site: $SITE_DOMAIN"
echo "   - Email: $ADMIN_EMAIL"
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
