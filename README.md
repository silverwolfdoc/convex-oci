# 🚀 Convex Self-Hosted with Docker Compose

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Required-blue.svg)](https://www.docker.com/)

A complete, production-ready setup for self-hosting [Convex](https://www.convex.dev/) backend and dashboard with PostgreSQL, Caddy reverse proxy, and automated SSL via Cloudflare.

## ✨ Features

- 🔒 **Automatic HTTPS** with Cloudflare DNS challenge or Origin Certificates
- 🐘 **PostgreSQL 18.1** with health checks and persistent storage
- 🔐 **Secure by default** - all sensitive data auto-generated and git-ignored
- 🎯 **One-command setup** - automated installation script for Ubuntu 24.04
- 🔄 **Zero-downtime updates** via Docker Compose
- 📦 **Easy backups** with persistent volumes
- 🌐 **Production-ready** - includes reverse proxy, SSL, and monitoring

## 📋 Prerequisites

- Ubuntu 24.04 VPS (or compatible Linux distribution)
- Domain name with Cloudflare DNS management
- Cloudflare API token with DNS:Edit permissions
- Root or sudo access
- Basic familiarity with Docker and command line

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

This repository provides a complete self-hosting solution with the following components:

| Component | Purpose |
|-----------|---------|
| **PostgreSQL** | Persistent database storage for Convex data |
| **Convex Backend** | Core Convex backend service (API + HTTP actions) |
| **Convex Dashboard** | Web-based management interface |
| **Caddy** | Reverse proxy with automatic SSL/TLS |
| **Setup Scripts** | Automated configuration and key generation |

### Key Files

- `docker-compose.yml` - Orchestrates all services with health checks and dependencies
- `Caddyfile.template` - Template for reverse proxy configuration (auto-generated during setup)
- `pre-docker.sh` - Automated setup script that installs Docker and generates configuration
- `set-admin-key.sh` - Admin key generation and injection tool
- `Dockerfile.caddy` - Custom Caddy build with Cloudflare DNS plugin

---

## 🔧 Setup Process

### Initial Configuration

During `pre-docker.sh` execution, you'll be prompted for:

1. **Admin Email** - For SSL certificate notifications (e.g., `admin@example.com`)
2. **API Subdomain** - For backend API (e.g., `api.example.com`)
3. **Dashboard Subdomain** - For web dashboard (e.g., `dashboard.example.com`)
4. **Site Subdomain** - For HTTP actions (e.g., `site.example.com`)
5. **Cloudflare API Token** - For automated DNS challenges

### What the Setup Script Does

The `pre-docker.sh` script automates the entire setup process:

- ✅ Installs Docker and Docker Compose from official repositories
- ✅ Generates cryptographically secure passwords and secrets
- ✅ Creates required directories with proper permissions
- ✅ Generates `.env` file with all configuration
- ✅ Generates `Caddyfile` from template with your domains
- ✅ Configures firewall rules (UFW) for ports 22, 80, and 443
- ✅ Adds your user to the docker group

### DNS Configuration

Before running the setup, ensure your DNS records are configured in Cloudflare:

- Create A records pointing to your VPS IP for all three subdomains
- Ensure records are **proxied** (orange cloud icon) for SSL to work properly
- DNS records should be: `api.example.com`, `dashboard.example.com`, `site.example.com`

---

## 📚 Architecture

### Service Overview

**PostgreSQL (Port: 5432)**
- Stores all Convex data persistently
- Configured with health checks to ensure availability
- Uses Docker volume for data persistence
- Database name: `convex_self_hosted`

**Convex Backend (Ports: 3210, 3211)**
- Port 3210: Main API endpoint for Convex operations
- Port 3211: HTTP actions endpoint for serverless functions
- Waits for PostgreSQL to be healthy before starting
- Stores application data in persistent volume

**Convex Dashboard (Port: 6791)**
- Web-based UI for managing your Convex instance
- Requires admin key for authentication
- Connects to backend service internally
- Accessible via reverse proxy at your dashboard subdomain

**Caddy Reverse Proxy (Ports: 80, 443)**
- Handles all incoming HTTP/HTTPS traffic
- Automatically provisions SSL certificates via Cloudflare
- Routes traffic to appropriate backend services
- Supports HTTP/2 and HTTP/3
- Custom build includes Cloudflare DNS plugin for DNS-01 challenges

### Network Architecture

All services communicate via Docker's internal network. Only Caddy exposes ports to the host, ensuring backend services are not directly accessible from the internet. This provides an additional layer of security.

---

## 🔒 SSL/TLS Configuration

This setup supports two SSL/TLS certificate options:

### Option 1: Let's Encrypt (Default)

The default configuration uses Let's Encrypt certificates obtained via Cloudflare DNS challenge. This is automatic and requires no manual certificate management.

**Limitations:**
- Let's Encrypt has rate limits (5 certificates per domain per 7 days)
- Certificates expire every 90 days (auto-renewed by Caddy)

### Option 2: Cloudflare Origin Certificates (Recommended for Production)

For production deployments or to avoid rate limits, you can use Cloudflare Origin Certificates:

- ✅ No rate limits
- ✅ Valid for 15 years
- ✅ Works immediately
- ✅ Free with Cloudflare

**See [CLOUDFLARE_ORIGIN_CERT_SETUP.md](CLOUDFLARE_ORIGIN_CERT_SETUP.md) for complete setup instructions.**

**Important:** When using Cloudflare Origin Certificates, ensure:
- SSL/TLS mode in Cloudflare is set to **"Full"** or **"Full (strict)"**
- All DNS records are proxied (orange cloud icon)
- Traffic goes through Cloudflare (not direct access)

---

## ⚙️ Configuration Reference

### Environment Variables

The `.env` file (auto-generated, git-ignored) contains all sensitive configuration:

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

Monitor service logs in real-time:
- `docker compose logs -f` - All services
- `docker compose logs -f backend` - Backend only
- `docker compose logs -f dashboard` - Dashboard only
- `docker compose logs -f caddy` - Caddy reverse proxy

### Service Management

- **Restart all services**: `docker compose restart`
- **Restart specific service**: `docker compose restart dashboard`
- **Stop all services**: `docker compose down`
- **Start services**: `docker compose up -d`

### Updates

Update to the latest versions:
```bash
docker compose pull
docker compose up -d
```

### Backups

Backup your data regularly:
- PostgreSQL data: `./pgdata/` directory
- Convex application data: `./convex-data/` directory
- Configuration: `.env` and `Caddyfile` files

Create backups with:
```bash
mkdir -p ~/backups/convex-$(date +%Y%m%d)
cp -r ./pgdata ./convex-data .env Caddyfile ~/backups/convex-$(date +%Y%m%d)/
```

### Complete Cleanup

⚠️ **Warning**: This deletes all data!

```bash
docker compose down -v
rm -rf ./pgdata ./convex-data ./caddy_data ./caddy_config
```

---

## 🐛 Troubleshooting

### Backend Fails to Connect to Postgres

**Symptoms:** Backend container exits with database connection errors.

**Solutions:**
- Check backend logs: `docker compose logs backend`
- Verify Postgres is healthy: `docker compose ps postgres`
- Ensure `POSTGRES_URL` in `.env` doesn't include database name (should be `postgres://convex:password@postgres:5432`)
- If Postgres volume was initialized with different password, remove volume: `docker volume rm convex-selfhost_pgdata`

### Admin Key Generation Fails

**Symptoms:** Cannot generate or set admin key for dashboard access.

**Solutions:**
- Ensure backend is running and healthy: `docker compose ps backend`
- Try manual generation: `docker compose exec backend ./generate_admin_key.sh`
- Check backend logs for errors: `docker compose logs backend -f`
- Verify backend is fully initialized before generating key

### Dashboard Not Accessible

**Symptoms:** Dashboard returns errors or doesn't load.

**Solutions:**
- Verify admin key is set: `grep CONVEX_SELF_HOSTED_ADMIN_KEY .env`
- Restart dashboard: `docker compose restart dashboard`
- Check dashboard logs: `docker compose logs dashboard -f`
- Test local access: `curl http://127.0.0.1:6791`
- Ensure backend is healthy and accessible

### TLS Certificates Not Obtained

**Symptoms:** Caddy fails to obtain SSL certificates, "rate limit" errors.

**Solutions:**
- Check Caddy logs: `docker compose logs caddy -f`
- Verify DNS records resolve correctly and are proxied
- Check Cloudflare API token permissions (needs Zone:DNS:Edit)
- Test Caddy configuration: `docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile`
- **For rate limit issues**: Use Cloudflare Origin Certificates (see [CLOUDFLARE_ORIGIN_CERT_SETUP.md](CLOUDFLARE_ORIGIN_CERT_SETUP.md))

### "Your Connection is Not Private" Error

**Symptoms:** Browser shows SSL certificate error when accessing dashboard.

**Solutions:**
- If using Cloudflare Origin Certificates, ensure SSL/TLS mode is "Full" or "Full (strict)" in Cloudflare dashboard
- Verify all DNS records are proxied (orange cloud icon)
- Clear browser cache or use incognito mode
- See [CLOUDFLARE_ORIGIN_CERT_SETUP.md](CLOUDFLARE_ORIGIN_CERT_SETUP.md) for detailed troubleshooting

### Services Won't Start After Reboot

**Symptoms:** Containers don't start automatically after server reboot.

**Solutions:**
- Check if Docker is running: `sudo systemctl status docker`
- Start Docker if needed: `sudo systemctl start docker`
- Enable Docker on boot: `sudo systemctl enable docker`
- Restart all services: `docker compose up -d`

### Postgres Permission Errors

**Symptoms:** Postgres container fails with permission denied errors.

**Solutions:**
- Stop containers: `docker compose down`
- Fix permissions: `sudo chown -R $USER:$USER ./pgdata && chmod 700 ./pgdata`
- Restart: `docker compose up -d`

---

## 🔒 Security Best Practices

### Built-in Security Features

- ✅ All secrets auto-generated with cryptographically secure random values
- ✅ `.env` and `Caddyfile` are git-ignored (never committed)
- ✅ Cloudflare API token scoped to DNS:Edit only (not full zone access)
- ✅ Firewall configured automatically (ports 22, 80, 443 only)
- ✅ Services communicate internally via Docker network
- ✅ Backend and Dashboard only expose ports on `127.0.0.1` (not publicly accessible)

### Recommended Security Practices

1. **Regular Backups**: Schedule automated backups of `./pgdata` and `./convex-data`
2. **Update Regularly**: Run `docker compose pull && docker compose up -d` monthly
3. **Monitor Logs**: Check `docker compose logs` regularly for suspicious activity
4. **Rotate Secrets**: Periodically regenerate `INSTANCE_SECRET` and `POSTGRES_PASSWORD`
5. **Restrict SSH Access**: Use SSH key authentication, disable password login
6. **Use Cloudflare Origin Certificates**: For production, avoids rate limits and provides long-term certificates
7. **Enable Cloudflare Security Features**: Use WAF, rate limiting, and DDoS protection in Cloudflare dashboard

---

## 📖 Additional Documentation

- **[CLOUDFLARE_ORIGIN_CERT_SETUP.md](CLOUDFLARE_ORIGIN_CERT_SETUP.md)** - Complete guide for using Cloudflare Origin Certificates to avoid Let's Encrypt rate limits

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
