# Convex Self-Hosted with Docker Compose

Complete setup for self-hosting Convex backend and dashboard with Postgres, Caddy reverse proxy, and Cloudflare TLS.

You get five files:

- `docker-compose.yml` — full stack (Postgres 18.1, Convex backend, dashboard, Caddy). Reads secrets from `.env`.
- `Caddyfile` — Cloudflare DNS challenge for HTTPS.
- `.env.example` — template for secrets.
- `pre-docker.sh` — Ubuntu 24.04 setup: installs Docker, creates data dirs, generates secrets, creates `.env`.
- `set-admin-key.sh` — generates and injects admin key into `.env`, restarts dashboard, runs health checks.

---

## 1) `docker-compose.yml`

```yaml
version: "3.8"

services:
  postgres:
    image: postgres:18.1
    restart: unless-stopped
    volumes:
      - ./pgdata:/var/lib/postgresql
    env_file: .env
    environment:
      - POSTGRES_USER=convex
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=convex_self_hosted
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U convex"]
      interval: 10s
      timeout: 5s
      retries: 5

  backend:
    image: ghcr.io/get-convex/convex-backend:latest
    platform: linux/arm64
    restart: unless-stopped
    ports:
      - "127.0.0.1:3210:3210"
      - "127.0.0.1:3211:3211"
    env_file: .env
    environment:
      - INSTANCE_NAME=convex-self-hosted
      - INSTANCE_SECRET=${INSTANCE_SECRET}
      - POSTGRES_URL=postgres://convex:${POSTGRES_PASSWORD}@postgres:5432
      - DO_NOT_REQUIRE_SSL=1
    volumes:
      - ./convex-data:/convex/data
    depends_on:
      postgres:
        condition: service_healthy

  dashboard:
    image: ghcr.io/get-convex/convex-dashboard:latest
    platform: linux/arm64
    restart: unless-stopped
    ports:
      - "127.0.0.1:6791:6791"
    env_file: .env
    environment:
      - NEXT_PUBLIC_DEPLOYMENT_URL=https://api.doctosaurus.com
      - CONVEX_BACKEND_URL=http://backend:3210
      - CONVEX_SELF_HOSTED_ADMIN_KEY=${CONVEX_SELF_HOSTED_ADMIN_KEY}
    depends_on:
      - backend

  caddy:
    build:
      context: .
      dockerfile: Dockerfile.caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    env_file: .env
    environment:
      - CLOUDFLARE_API_TOKEN=${CLOUDFLARE_API_TOKEN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy_data:/data
      - ./caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
```

**Key changes from old setup:**

- `POSTGRES_URL` no longer includes `/convex_self_hosted` — database selection is via `INSTANCE_NAME`
- All services use `env_file: .env` to load secrets
- `INSTANCE_NAME=convex-self-hosted` explicitly set (creates DB `convex_self_hosted`)
- `DO_NOT_REQUIRE_SSL=1` for local Postgres without SSL
- `CONVEX_BACKEND_URL=http://backend:3210` added to dashboard for internal communication

---

## 2) `Caddyfile`

```
{
  email admin@doctosaurus.com
}

api.doctosaurus.com {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy backend:3210 {
    header_up Host {host}
    header_up X-Real-IP {remote}
    header_up X-Forwarded-For {remote}
    header_up X-Forwarded-Proto {scheme}
  }
}

dashboard.doctosaurus.com {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy dashboard:6791 {
    header_up Host {host}
    header_up X-Real-IP {remote}
    header_up X-Forwarded-For {remote}
    header_up X-Forwarded-Proto {scheme}
  }
}

site.doctosaurus.com {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy backend:3211 {
    header_up Host {host}
    header_up X-Real-IP {remote}
    header_up X-Forwarded-For {remote}
    header_up X-Forwarded-Proto {scheme}
  }
}
```

---

## 3) `.env.example`

```bash
# Postgres Configuration
# Generate a strong password with: openssl rand -base64 32
POSTGRES_PASSWORD=your-secure-postgres-password-here

# Convex Backend Configuration
# Generate INSTANCE_SECRET with: openssl rand -hex 32
INSTANCE_SECRET=your-generated-instance-secret-here

# Database Configuration
# Auto-generated based on POSTGRES_PASSWORD and local Postgres container
# Only modify if using an external PostgreSQL database
DATABASE_URL=postgresql://convex:your-encoded-password@postgres:5432

# Convex Backend Origin URLs
# CONVEX_CLOUD_ORIGIN: where your backend API is accessible (typically port 3210)
# CONVEX_SITE_ORIGIN: where your HTTP action endpoints are accessible (typically port 3211)
CONVEX_CLOUD_ORIGIN=https://api.your-domain.com
CONVEX_SITE_ORIGIN=https://site.your-domain.com

# Convex Dashboard
# URL of your backend for the dashboard to connect to
NEXT_PUBLIC_DEPLOYMENT_URL=https://api.your-domain.com

# Generate ADMIN_KEY by running (after backend is healthy):
# docker compose exec backend ./generate_admin_key.sh
CONVEX_SELF_HOSTED_ADMIN_KEY=your-generated-admin-key-here

# Cloudflare Configuration (for TLS via DNS challenge)
# Get your token from: https://dash.cloudflare.com/profile/api-tokens
CLOUDFLARE_API_TOKEN=your-cloudflare-api-token-here
```

---

## 4) `pre-docker.sh` — Ubuntu 24.04 setup

```bash
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
```

Make executable:

```bash
chmod +x pre-docker.sh
```

---

## 5) `set-admin-key.sh` — generate and inject admin key

```bash
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
  echo "Captured admin key: $ADMIN_KEY"
else
  ADMIN_KEY="$KEY_ARG"
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
```

Make executable:

```bash
chmod +x set-admin-key.sh
```

---

## Quick Start

1. **SSH into VPS and create folder:**

```bash
mkdir -p ~/convex-selfhost
cd ~/convex-selfhost
git clone https://github.com/silverwolfdoc/convex-oci.git .
chmod +x pre-docker.sh set-admin-key.sh
```

2. **Run setup script (will prompt for Cloudflare token):**

```bash
./pre-docker.sh
```

3. **Start the stack:**

```bash
docker compose up -d --pull always
```

4. **Auto-generate and inject admin key:**

```bash
./set-admin-key.sh AUTO
```

5. **Verify services are healthy:**

```bash
docker compose ps
```

6. **Access dashboard:**

- Local: `http://127.0.0.1:6791`
- Remote (after DNS): `https://dashboard.doctosaurus.com`

---

## Configuration

### DNS Records

Add A records pointing to your VPS IP:

- `api.doctosaurus.com` → your VPS IP
- `dashboard.doctosaurus.com` → your VPS IP
- `site.doctosaurus.com` → your VPS IP (optional, for HTTP actions)

### Environment Variables (in `.env`)

- **POSTGRES_PASSWORD** — Database password (generated by `pre-docker.sh`)
- **INSTANCE_SECRET** — Backend secret key (generated by `pre-docker.sh`)
- **INSTANCE_NAME** — Determines database name: `convex-self-hosted` → `convex_self_hosted`
- **DATABASE_URL** — PostgreSQL connection string (URL-encoded, no database name included)
- **CONVEX_CLOUD_ORIGIN** — Public URL of your backend API (port 3210), e.g., `https://api.your-domain.com`
- **CONVEX_SITE_ORIGIN** — Public URL of your HTTP action endpoints (port 3211), e.g., `https://site.your-domain.com`
- **NEXT_PUBLIC_DEPLOYMENT_URL** — Backend URL shown in dashboard, e.g., `https://api.your-domain.com`
- **CONVEX_SELF_HOSTED_ADMIN_KEY** — Dashboard auth key (generated by `set-admin-key.sh`)
- **CLOUDFLARE_API_TOKEN** — For Caddy TLS via DNS challenge

### Database

- Default: `convex_self_hosted` (matches instance name `convex-self-hosted` with `-` → `_`)
- User: `convex`
- Postgres 18.1 with health check enabled

---

## Troubleshooting

**Backend fails to connect to Postgres:**

```bash
# Check backend logs
docker compose logs backend

# Verify POSTGRES_URL format (should NOT include database name)
grep POSTGRES_URL .env
# Should look like: postgres://convex:password@postgres:5432
```

**Admin key generation fails:**

```bash
# Try manually
docker compose exec backend ./generate_admin_key.sh

# Check backend logs
docker compose logs backend -f
```

**Dashboard not accessible:**

```bash
# Verify admin key is set
grep CONVEX_SELF_HOSTED_ADMIN_KEY .env

# Restart dashboard
docker compose restart dashboard

# Check logs
docker compose logs dashboard -f
```

**TLS cert not obtained:**

```bash
# Check Caddy logs
docker compose logs caddy -f

# Verify DNS resolves
nslookup api.doctosaurus.com
```

**Postgres 18+ mount error (data in /var/lib/postgresql/data):**

If you see errors about `/var/lib/postgresql/data` being an unused mount, Postgres 18+ requires the mount to be at `/var/lib/postgresql` instead (manages version-specific subdirectories internally).

**To migrate from old mount:**

```bash
# Stop containers
docker compose down

# Back up old data
cp -r pgdata pgdata.backup

# Remove old data directory
rm -rf pgdata

# Recreate empty pgdata directory
mkdir pgdata

# Start fresh (docker compose will initialize new database)
docker compose up -d

# After backend is healthy, re-apply any data/functions you need
```

If you have existing data in the old format and want to upgrade in-place:

```bash
# This requires both Postgres versions to be available
# See: https://github.com/docker-library/postgres/issues/37
```

---

## Security Notes

- **`.env` file** is git-ignored; never commit secrets
- **Cloudflare token** should have DNS:Edit permissions only
- **Backups:** Regularly backup `./pgdata`, `./convex-data`
- **Postgres SSL:** `DO_NOT_REQUIRE_SSL=1` is for local development; remove for remote production databases

---

## Additional Resources

- [Convex Self-Hosted README](https://github.com/get-convex/convex-backend/tree/main/self-hosted)
- [Convex Stack Guide](https://stack.convex.dev/self-hosted-develop-and-deploy)
