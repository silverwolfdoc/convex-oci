You get four paste-ready files:

- `docker-compose.yml` — full stack (Postgres 18, Convex backend, dashboard, Caddy). Placeholders are minimized; the pre-docker script will inject secrets and your Cloudflare token.
- `Caddyfile` — same as before (Cloudflare DNS challenge).
- `pre-docker.sh` — for Ubuntu 24.04: installs Docker, creates data dirs, generates `INSTANCE_SECRET` & `POSTGRES_PASSWORD`, prompts you to paste the Cloudflare API token and injects it into `docker-compose.yml`.
- `set-admin-key.sh` — a small developer utility: given an admin key (or empty to auto-generate), it will inject the key into `docker-compose.yml`, restart the dashboard, and run simple health checks for Postgres, backend and dashboard so you get immediate feedback.

Drop the four files into one folder (e.g. `~/convex-selfhost`), `chmod +x` the scripts, run the pre script, then `docker compose up -d --pull`. After startup you can either generate the admin key and run the setter script, or pass the admin key straight to the setter script.

---

## 1) `docker-compose.yml`

```yaml
version: "3.8"

services:
  postgres:
    image: postgres:18
    restart: unless-stopped
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=convex
      - POSTGRES_PASSWORD=REPLACE_WITH_POSTGRES_PASSWORD
      - POSTGRES_DB=convex
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
    environment:
      - INSTANCE_SECRET=REPLACE_WITH_INSTANCE_SECRET
      - DATABASE_URL=postgres://convex:REPLACE_WITH_POSTGRES_PASSWORD@postgres:5432/convex
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
    environment:
      - NEXT_PUBLIC_DEPLOYMENT_URL=https://api.doctosaurus.com
      - CONVEX_SELF_HOSTED_ADMIN_KEY=REPLACE_WITH_ADMIN_KEY
    depends_on:
      - backend

  caddy:
    image: caddy:latest
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      # will be replaced by pre-docker.sh when you paste the token
      - CLOUDFLARE_API_TOKEN=REPLACE_WITH_CLOUDFLARE_API_TOKEN
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy_data:/data
      - ./caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
```

---

## 2) `Caddyfile`

```text
{
  email admin@doctosaurus.com
  servers {
    protocol {
      allow_h2c
    }
  }
}

api.doctosaurus.com {
  tls {
    dns cloudflare {env.CLOUDFLARE_API_TOKEN}
  }
  reverse_proxy 127.0.0.1:3210 {
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
  reverse_proxy 127.0.0.1:6791 {
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
  reverse_proxy 127.0.0.1:3211 {
    header_up Host {host}
    header_up X-Real-IP {remote}
    header_up X-Forwarded-For {remote}
    header_up X-Forwarded-Proto {scheme}
  }
}
```

---

## 3) `pre-docker.sh` (Ubuntu 24.04 ready)

```bash
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
```

Make `pre-docker.sh` executable:

```bash
chmod +x pre-docker.sh
```

---

## 4) `set-admin-key.sh` — inject admin key, restart dashboard, and run health checks

```bash
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
```

Make it executable:

```bash
chmod +x set-admin-key.sh
```

---

## Quick copy-paste workflow (what I recommend)

1. SSH into VPS and create folder:

```bash
mkdir -p ~/convex-selfhost
cd ~/convex-selfhost
sudo apt install git
git clone https://github.com/silverwolfdoc/convex-oci.git .
# paste the four files here
chmod +x pre-docker.sh set-admin-key.sh
```

2. Logout and then login . Run pre-docker script (it will prompt you to paste the Cloudflare API token quietly):

```bash
./pre-docker.sh
```

3. Start the stack:

```bash
cd ~/convex-selfhost
docker compose up -d --pull always
```

4. (Option A) Auto-generate and inject the admin key:

```bash
# This runs generate_admin_key.sh inside the backend and injects the found key
./set-admin-key.sh AUTO
```

5. (Option B) Manually generate then inject:

```bash
# generate and copy printed key
docker compose exec backend ./generate_admin_key.sh

# then inject and restart dashboard (paste the key in place of <KEY>)
./set-admin-key.sh "<KEY>"
```

6. Verify:

- Check `docker compose logs -f caddy` to see Caddy obtaining certs (it will use the CF token).
- Ensure DNS A records point to your VPS IP for `api`, `dashboard`, `site` (you can toggle Cloudflare proxy later).
- `./set-admin-key.sh` already runs local health checks for Postgres, backend, and dashboard.

7. Add Cloudflare DNS A records:

api.doctosaurus.com → your VPS IP

dashboard.doctosaurus.com → your VPS IP

site.doctosaurus.com → your VPS IP (optional)

---

## Notes & small tips

- `pre-docker.sh` injects your Cloudflare token directly in the compose file (no `.env`). If you prefer it not to be in the file, let me know and I’ll make the compose reference an external `.env` instead.
- The `AUTO` mode of `set-admin-key.sh` attempts to capture the admin key printed by `generate_admin_key.sh`. If the script output format changes, fallback is to run generate manually and pass the key to the setter.
- Backups: `./pgdata` and `./convex-data` are host folders — tar them for backups as needed.
- If you prefer the admin key to be stored outside `docker-compose.yml` (safer), we can change the compose to read the key from a file (mounted secret) or from an `.env` so you don’t rewrite the compose each time.
