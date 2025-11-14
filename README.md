# 🚀 Convex Self-Hosted with Docker Compose

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)

A complete, production-ready setup for self-hosting [Convex](https://www.convex.dev/) backend and dashboard with PostgreSQL, Caddy reverse proxy, and automated SSL via Cloudflare.

## ✨ Features

- 🔒 **Automatic HTTPS** with Cloudflare DNS challenge
- 🐘 **PostgreSQL 18.1** with health checks
- 🔐 **Secure by default** - all sensitive data auto-generated and git-ignored
- 🎯 **One-command setup** - automated installation script for Ubuntu 24.04
- 🔄 **Zero-downtime updates** via Docker Compose
- 📦 **Easy backups** with persistent volumes

## 📋 Prerequisites

- Ubuntu 24.04 VPS (or compatible Linux distribution)
- Domain name with Cloudflare DNS
- Cloudflare API token with DNS:Edit permissions
- Root or sudo access

## 🚀 Quick Start

Get up and running in 5 minutes:

```bash
# 1. Clone the repository
mkdir -p ~/convex-selfhost && cd ~/convex-selfhost
git clone https://github.com/silverwolfdoc/convex-oci.git .

# 2. Make scripts executable
chmod +x pre-docker.sh set-admin-key.sh

# 3. Run automated setup (prompts for configuration)
./pre-docker.sh

# 4. Start the stack
docker compose up -d --pull always

# 5. Generate and set admin key
./set-admin-key.sh AUTO

# 6. Verify everything is running
docker compose ps
```

**That's it!** Your Convex instance is now running. Access the dashboard at `https://your-dashboard-domain.com`

---

## 📦 What's Included

This repository contains everything you need to self-host Convex:

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Full stack orchestration (Postgres, Backend, Dashboard, Caddy) |
| `Caddyfile.template` | Template for reverse proxy configuration (auto-generated during setup) |
| `.env.example` | Example environment variables (your `.env` is auto-generated) |
| `pre-docker.sh` | Automated setup script for Ubuntu 24.04 |
| `set-admin-key.sh` | Admin key generation and injection tool |
| `Dockerfile.caddy` | Custom Caddy build with Cloudflare DNS plugin |

## 🔧 Setup Details

### During `pre-docker.sh` execution, you'll be prompted for:

1. **Admin Email** - For SSL certificate notifications (e.g., `admin@example.com`)
2. **API Subdomain** - For backend API (e.g., `api.example.com`)
3. **Dashboard Subdomain** - For web dashboard (e.g., `dashboard.example.com`)
4. **Site Subdomain** - For HTTP actions (e.g., `site.example.com`)
5. **Cloudflare API Token** - For automated DNS challenges

The script will automatically:
- ✅ Install Docker and Docker Compose
- ✅ Generate secure passwords and secrets
- ✅ Create required directories
- ✅ Generate `.env` and `Caddyfile` with your configuration
- ✅ Configure firewall rules (UFW)

### DNS Configuration

Before running the setup, create A records pointing to your VPS IP:

```
api.example.com        → 203.0.113.1
dashboard.example.com  → 203.0.113.1
site.example.com       → 203.0.113.1
```

*Replace `example.com` with your actual domain and `203.0.113.1` with your VPS IP*

---

## 📚 Architecture

### Services Overview

<details>
<summary><b>🐘 PostgreSQL (Port: 5432)</b></summary>

- **Image:** `postgres:18.1`
- **Database:** `convex_self_hosted`
- **User:** `convex`
- **Health checks:** Enabled
- **Persistence:** `./pgdata` volume

</details>

<details>
<summary><b>⚙️ Convex Backend (Ports: 3210, 3211)</b></summary>

- **Image:** `ghcr.io/get-convex/convex-backend:latest`
- **Port 3210:** API endpoint
- **Port 3211:** HTTP actions endpoint
- **Dependencies:** Postgres (waits for healthy state)
- **Persistence:** `./convex-data` volume

</details>

<details>
<summary><b>📊 Convex Dashboard (Port: 6791)</b></summary>

- **Image:** `ghcr.io/get-convex/convex-dashboard:latest`
- **Access:** Web UI for managing your Convex instance
- **Authentication:** Admin key (auto-generated)
- **Dependencies:** Backend service

</details>

<details>
<summary><b>🌐 Caddy Reverse Proxy (Ports: 80, 443)</b></summary>

- **Custom build** with Cloudflare DNS plugin
- **TLS:** Automatic HTTPS via Cloudflare DNS challenge
- **Routes:** Proxies all subdomains to appropriate services
- **Persistence:** `./caddy_data` and `./caddy_config` volumes

</details>

---

## 📖 Detailed Configuration

### 1) `docker-compose.yml`

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
      - NEXT_PUBLIC_DEPLOYMENT_URL=${CONVEX_CLOUD_ORIGIN}
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

**Key configuration notes:**

- All services use `env_file: .env` to load secrets securely
- `INSTANCE_NAME=convex-self-hosted` determines database name (becomes `convex_self_hosted`)
- Health checks ensure services start in correct order
- Internal networking for service-to-service communication

---

### 2) `Caddyfile.template`

The actual `Caddyfile` is auto-generated by `pre-docker.sh` based on your domain inputs. The template uses placeholders:

```
{
  email {{ADMIN_EMAIL}}
}

{{API_DOMAIN}} {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy backend:3210 {
    header_up Host {host}
    header_up X-Real-IP {remote}
  }
}

{{DASHBOARD_DOMAIN}} {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy dashboard:6791 {
    header_up Host {host}
    header_up X-Real-IP {remote}
  }
}

{{SITE_DOMAIN}} {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy backend:3211 {
    header_up Host {host}
    header_up X-Real-IP {remote}
  }
}
```

**Note:** The generated `Caddyfile` is excluded from git to keep your domain private.

---

### 3) `.env.example`

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
POSTGRES_URL=postgres://convex:your-encoded-password@postgres:5432

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

**All secrets are auto-generated during setup. Never commit your `.env` file!**

---

### 4) `pre-docker.sh`

Automated setup script for Ubuntu 24.04:

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
read -r -p $'Paste your Cloudflare API token (DNS:Edit for your domain). It will not be displayed:\n' -s CF_TOKEN
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

### 5) `set-admin-key.sh`

Generates and injects the admin key for dashboard access:

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
echo "Or via reverse proxy (if DNS configured): https://your-dashboard-domain.com"
echo
echo "If you want to revert, restore the backup:"
echo "  cp $ENV_FILE.bak $ENV_FILE && docker compose restart dashboard"
```

Make executable:

```bash
chmod +x set-admin-key.sh
```

---

## ⚙️ Configuration Reference

### Environment Variables

The `.env` file contains all configuration. Here are the key variables:

| Variable | Description | Generated By |
|----------|-------------|--------------|
| `POSTGRES_PASSWORD` | Database password | `pre-docker.sh` (auto) |
| `INSTANCE_SECRET` | Backend secret key | `pre-docker.sh` (auto) |
| `POSTGRES_URL` | PostgreSQL connection string | `pre-docker.sh` (auto) |
| `CONVEX_CLOUD_ORIGIN` | Public API URL | `pre-docker.sh` (from your input) |
| `CONVEX_SITE_ORIGIN` | Public HTTP actions URL | `pre-docker.sh` (from your input) |
| `NEXT_PUBLIC_DEPLOYMENT_URL` | Dashboard backend URL | `pre-docker.sh` (from your input) |
| `CONVEX_SELF_HOSTED_ADMIN_KEY` | Dashboard authentication | `set-admin-key.sh` |
| `CLOUDFLARE_API_TOKEN` | DNS challenge token | `pre-docker.sh` (from your input) |

### Access URLs

After setup completes, access your services:

| Service | Local Access | Public Access |
|---------|-------------|---------------|
| Dashboard | `http://127.0.0.1:6791` | `https://dashboard.example.com` |
| Backend API | `http://127.0.0.1:3210` | `https://api.example.com` |
| HTTP Actions | `http://127.0.0.1:3211` | `https://site.example.com` |

---

## 🔧 Management Commands

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f backend
docker compose logs -f dashboard
docker compose logs -f caddy
```

### Restart Services

```bash
# All services
docker compose restart

# Specific service
docker compose restart dashboard
```

### Update to Latest Version

```bash
docker compose pull
docker compose up -d
```

### Backup Data

```bash
# Create backup directory
mkdir -p ~/backups/convex-$(date +%Y%m%d)

# Backup Postgres data
sudo cp -r ./pgdata ~/backups/convex-$(date +%Y%m%d)/

# Backup Convex data
sudo cp -r ./convex-data ~/backups/convex-$(date +%Y%m%d)/

# Backup configuration
cp .env ~/backups/convex-$(date +%Y%m%d)/
cp Caddyfile ~/backups/convex-$(date +%Y%m%d)/
```

### Stop All Services

```bash
docker compose down
```

### Complete Cleanup (⚠️ Deletes all data)

```bash
docker compose down -v
rm -rf ./pgdata ./convex-data ./caddy_data ./caddy_config
```

---

## 🐛 Troubleshooting

<details>
<summary><b>Backend fails to connect to Postgres</b></summary>

```bash
# Check backend logs
docker compose logs backend

# Verify Postgres is healthy
docker compose ps postgres

# Check connection string format
grep POSTGRES_URL .env
# Should NOT include database name: postgres://convex:password@postgres:5432
```

</details>

<details>
<summary><b>Admin key generation fails</b></summary>

```bash
# Ensure backend is running and healthy
docker compose ps backend

# Try manual generation
docker compose exec backend ./generate_admin_key.sh

# Check backend logs for errors
docker compose logs backend -f
```

</details>

<details>
<summary><b>Dashboard not accessible</b></summary>

```bash
# Verify admin key is set in .env
grep CONVEX_SELF_HOSTED_ADMIN_KEY .env

# Restart dashboard
docker compose restart dashboard

# Check dashboard logs
docker compose logs dashboard -f

# Test local access
curl http://127.0.0.1:6791
```

</details>

<details>
<summary><b>TLS certificates not obtained</b></summary>

```bash
# Check Caddy logs for errors
docker compose logs caddy -f

# Verify DNS records resolve correctly
nslookup api.your-domain.com
nslookup dashboard.your-domain.com
nslookup site.your-domain.com

# Check Cloudflare API token permissions
# Token needs: Zone:DNS:Edit for your domain

# Test Caddy configuration
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile
```

</details>

<details>
<summary><b>Services won't start after reboot</b></summary>

```bash
# Check if Docker is running
sudo systemctl status docker

# Start Docker if needed
sudo systemctl start docker

# Restart all services
docker compose up -d
```

</details>

<details>
<summary><b>Postgres permission errors</b></summary>

If you see errors like:
```
mkdir: cannot create directory '/var/lib/postgresql': Permission denied
```

This typically happens with directory permissions. Fix with:

```bash
# Stop containers
docker compose down

# Fix permissions
sudo chown -R $USER:$USER ./pgdata
chmod 700 ./pgdata

# Restart
docker compose up -d
```

</details>

---

## 🔒 Security Best Practices

- ✅ All secrets are auto-generated with cryptographically secure random values
- ✅ `.env` and `Caddyfile` are git-ignored (never commit these files)
- ✅ Cloudflare API token should have **DNS:Edit** permission only (not full zone access)
- ✅ Firewall configured automatically (ports 22, 80, 443 only)
- ✅ Services communicate internally via Docker network
- ✅ Backend and Dashboard only expose ports on `127.0.0.1` (not public)

### Recommended Security Practices

1. **Regular Backups**: Schedule automated backups of `./pgdata` and `./convex-data`
2. **Update Regularly**: Run `docker compose pull && docker compose up -d` monthly
3. **Monitor Logs**: Check `docker compose logs` regularly for suspicious activity
4. **Rotate Secrets**: Periodically regenerate `INSTANCE_SECRET` and `POSTGRES_PASSWORD`
5. **Restrict Access**: Use SSH key authentication, disable password login

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

---

## 📄 License

This project is licensed under the MIT License.

---

## 🔗 Additional Resources

- [Convex Documentation](https://docs.convex.dev/)
- [Convex Self-Hosted Guide](https://github.com/get-convex/convex-backend/tree/main/self-hosted)
- [Convex Stack](https://stack.convex.dev/self-hosted-develop-and-deploy)
- [Caddy Documentation](https://caddyserver.com/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

---

## 💬 Support

- **Issues**: Open an issue on GitHub
- **Convex Discord**: Join the [Convex community](https://convex.dev/community)
- **Documentation**: Check the [official docs](https://docs.convex.dev/)

---

**Made with ❤️ for the Convex community**
