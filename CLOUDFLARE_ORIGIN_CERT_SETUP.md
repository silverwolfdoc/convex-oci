# Cloudflare Origin Certificate Setup

This guide shows how to use Cloudflare Origin Certificates instead of Let's Encrypt to avoid rate limits and eliminate certificate renewal concerns.

## Why Use Cloudflare Origin Certificates?

- ✅ **No rate limits** - Unlike Let's Encrypt (5 certificates per 7 days)
- ✅ **Works immediately** - No waiting for rate limits to reset
- ✅ **Long validity** - Valid for 15 years (no renewal needed)
- ✅ **Free** - Included with Cloudflare
- ✅ **Secure** - Trusted by Cloudflare when properly configured

## Prerequisites

- Domain managed by Cloudflare
- Cloudflare API token with DNS:Edit permissions
- Docker and Docker Compose installed

## Step 1: Create Origin Certificate in Cloudflare

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Select your domain (e.g., `example.com`)
3. Navigate to **SSL/TLS** → **Origin Server**
4. Click **Create Certificate**
5. Configure:
   - **Private key type**: RSA (2048)
   - **Hostnames**: 
     - `*.example.com` (wildcard - covers all subdomains)
     - `example.com` (root domain)
   - **Validity**: 15 years
6. Click **Create**
7. Copy both:
   - **Origin Certificate** (the certificate content)
   - **Private Key** (the private key content)

## Step 2: Save Certificates

Save the certificate and key to files in your project directory:

```bash
# Create directory for certificates
mkdir -p certs

# Save the certificate (paste the Origin Certificate content)
nano certs/cloudflare-origin.crt

# Save the private key (paste the Private Key content)
nano certs/cloudflare-origin.key

# Set proper permissions
chmod 600 certs/cloudflare-origin.key
chmod 644 certs/cloudflare-origin.crt
```

## Step 3: Update Caddyfile

Update your Caddyfile to use the Cloudflare Origin Certificate instead of Let's Encrypt:

```caddyfile
{
  email admin@example.com
}

api.example.com {
  tls /etc/caddy/certs/cloudflare-origin.crt /etc/caddy/certs/cloudflare-origin.key
  reverse_proxy backend:3210 {
    header_up Host {host}
    header_up X-Real-IP {remote}
  }
}

dashboard.example.com {
  tls /etc/caddy/certs/cloudflare-origin.crt /etc/caddy/certs/cloudflare-origin.key
  reverse_proxy dashboard:6791 {
    header_up Host {host}
    header_up X-Real-IP {remote}
  }
}

site.example.com {
  tls /etc/caddy/certs/cloudflare-origin.crt /etc/caddy/certs/cloudflare-origin.key
  reverse_proxy backend:3211 {
    header_up Host {host}
    header_up X-Real-IP {remote}
  }
}
```

Replace `example.com` with your actual domain.

## Step 4: Update docker-compose.yml

Add a volume mount for the certificates directory:

```yaml
caddy:
  # ... existing config ...
  volumes:
    - ./Caddyfile:/etc/caddy/Caddyfile:ro
    - ./caddy_data:/data
    - ./caddy_config:/config
    - ./certs:/etc/caddy/certs:ro  # Add this line
```

## Step 5: Restart Services

```bash
docker compose restart caddy
```

Verify it's working:

```bash
docker compose logs caddy --tail 20
```

You should see the certificate loaded successfully without errors.

## Step 6: Configure Cloudflare SSL/TLS Settings

**CRITICAL**: Cloudflare Origin Certificates only work when properly configured in Cloudflare.

### Set SSL/TLS Mode

1. Go to **SSL/TLS** → **Overview** in Cloudflare dashboard
2. Set encryption mode to **"Full"** or **"Full (strict)"**
   - **"Full"**: Cloudflare accepts any certificate (including self-signed)
   - **"Full (strict)"**: Cloudflare validates your origin certificate (recommended)
   - **DO NOT use "Flexible"** - this won't work with origin certificates

### Verify DNS Records are Proxied

1. Go to **DNS** → **Records** in Cloudflare dashboard
2. Check your DNS records for all subdomains:
   - `api.example.com`
   - `dashboard.example.com`
   - `site.example.com`
3. **IMPORTANT**: Each record should have an **orange cloud icon** (Proxied)
   - If you see a **gray cloud**, click it to enable proxying
   - **Proxied** = Traffic goes through Cloudflare (required)
   - **DNS only** = Direct connection (will show certificate error)

## Troubleshooting

### "Your connection is not private" Error

This error occurs when browsers can't verify the certificate. Cloudflare Origin Certificates are only trusted when traffic goes through Cloudflare's proxy.

**Fix:**

1. **Verify SSL/TLS mode is "Full" or "Full (strict)"**
   - Dashboard → SSL/TLS → Overview
   - Must NOT be "Flexible" or "Off"

2. **Verify DNS records are proxied (orange cloud)**
   - Dashboard → DNS → Records
   - All subdomains must show orange cloud icon

3. **Wait for DNS propagation**
   - Changes can take 1-5 minutes
   - Clear browser cache or use incognito mode

4. **Test if accessing through Cloudflare:**
   ```bash
   curl -I https://dashboard.example.com | grep -i cf-ray
   ```
   If you see `cf-ray` header, you're going through Cloudflare.

5. **Check certificate validity:**
   ```bash
   openssl s_client -connect dashboard.example.com:443 -servername dashboard.example.com
   ```

### Certificate Not Found Error

If Caddy can't find the certificate files:

1. **Verify files exist:**
   ```bash
   ls -la certs/
   ```

2. **Check file permissions:**
   ```bash
   chmod 600 certs/cloudflare-origin.key
   chmod 644 certs/cloudflare-origin.crt
   ```

3. **Verify volume mount in docker-compose.yml:**
   ```yaml
   volumes:
     - ./certs:/etc/caddy/certs:ro
   ```

4. **Restart Caddy:**
   ```bash
   docker compose restart caddy
   ```

### Certificate Includes Wrong Domains

If your certificate doesn't cover all subdomains:

1. Create a new certificate in Cloudflare with:
   - `*.example.com` (wildcard for all subdomains)
   - `example.com` (root domain)

2. Replace the certificate files and restart Caddy

## Important Notes

### How Cloudflare Origin Certificates Work

- ✅ **Trusted by Cloudflare** when SSL/TLS mode is Full/Full strict
- ✅ **Trusted by browsers** ONLY when traffic goes through Cloudflare
- ❌ **NOT trusted by browsers** when accessing directly (bypassing Cloudflare)

This is by design - the certificate secures the connection between Cloudflare and your origin server, not for direct browser access.

### When to Use Origin Certificates

**Use Origin Certificates when:**
- You're hitting Let's Encrypt rate limits
- You want long-term certificates (15 years)
- All traffic goes through Cloudflare

**Use Let's Encrypt when:**
- You need direct browser access (bypassing Cloudflare)
- You want automatic renewal
- You're not using Cloudflare proxy

### Security Considerations

- Keep certificate private keys secure (chmod 600)
- Don't commit certificates to git (add `certs/` to `.gitignore`)
- Use "Full (strict)" mode for maximum security
- Consider enabling "Authenticated Origin Pulls" for additional security

## Benefits Summary

- ✅ No rate limits
- ✅ Works immediately
- ✅ Valid for 15 years (no renewal needed)
- ✅ Free
- ✅ Trusted by Cloudflare (browsers trust it when behind Cloudflare)
