# Custom Domain with EasyAuth on Azure Container Apps behind Application Gateway

This guide covers configuring a custom domain with Entra ID (EasyAuth) authentication on Azure Container Apps behind Application Gateway, using Cloudflare as the DNS/CDN provider.

## Architecture Overview

```
Browser → Cloudflare (SSL termination) → App Gateway (HTTPS) → Container App (HTTPS) → EasyAuth
```

## Prerequisites

- Azure Container Apps deployed in a VNet (internal ingress)
- Application Gateway v2 in a hub VNet peered with the Container Apps VNet
- Custom domain (e.g., `openwebui.example.com`)
- Cloudflare account (or alternative DNS/certificate provider)

## Deployment Steps

### 1. Generate Cloudflare Origin Certificate

1. In Cloudflare Dashboard → SSL/TLS → Origin Server → Create Certificate
2. Select RSA (2048) and add your custom domain (e.g., `openwebui.example.com`)
3. Download as PFX format (or PEM and convert to PFX)
4. Upload to Azure Key Vault as a certificate

### 2. Download Cloudflare Origin CA Root Certificate

```bash
# Download the Cloudflare Origin CA root certificate (RSA)
curl -o cloudflare-origin-ca.cer https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem

# Convert to base64 (remove PEM headers)
grep -v "CERTIFICATE" cloudflare-origin-ca.cer | tr -d '\n' > cloudflare-origin-ca-base64.cer
```

Place `cloudflare-origin-ca.cer` (base64 only, no PEM headers) in `infra/bicep/`.

### 3. Configure Parameters

Update `main.bicepparam`:

```bicep
param parCustomDomain = 'openwebui.example.com'
param parSpokeKeyVaultName = 'your-keyvault-name'  // Key Vault with Origin Certificate
```

Update `app.bicepparam`:

```bicep
param parCustomDomain = 'openwebui.example.com'
param parCertificateName = 'cloudflare-origin-cert'  // Certificate name in Key Vault
```

### 4. Deploy Infrastructure

```bash
# Deploy spoke resources (Container App, Key Vault, etc.)
az deployment sub create --location <region> --template-file app.bicep --parameters app.bicepparam

# Deploy hub resources (App Gateway, VNet peering, etc.)
az deployment sub create --location <region> --template-file main.bicep --parameters main.bicepparam
```

### 5. Configure Cloudflare DNS

1. Add an A record pointing your custom domain to the App Gateway public IP
2. **Enable Proxy (orange cloud)** - Required for SSL termination
3. Set SSL/TLS mode to **Full (strict)**

### 6. Verify App Registration

Ensure your Entra ID App Registration has the correct redirect URI:

```
https://openwebui.example.com/.auth/login/aad/callback
```

## Key Configuration Points

### Application Gateway

| Component | Configuration |
|-----------|---------------|
| **Trusted Root Cert** | Cloudflare Origin CA (from Key Vault) |
| **SSL Certificate** | Cloudflare Origin Certificate (from spoke Key Vault) |
| **HTTPS Listener** | Port 443, custom domain hostname |
| **Backend Settings** | `hostName: customDomain`, trusted root cert reference |
| **Rewrite Rules** | `X-Forwarded-Host` and `X-Forwarded-Proto: https` |

### Container App EasyAuth

```bicep
httpSettings: {
  requireHttps: true
  forwardProxy: {
    convention: 'Standard'  // Uses X-Forwarded-Host/Proto headers
  }
}
```

## Alternative Certificate Options

### Using Let's Encrypt / Public CA

If not using Cloudflare proxy (grey cloud DNS only):

1. Obtain a publicly trusted certificate (Let's Encrypt, DigiCert, etc.)
2. Upload to Key Vault
3. Reference in App Gateway SSL certificate
4. Remove trusted root certificate config (not needed for public CAs)

### Using Azure-managed Certificates

App Gateway supports Azure-managed certificates for custom domains with public DNS validation.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **502 Bad Gateway** | Check trusted root cert matches the origin cert CA |
| **Redirect URI mismatch** | Verify `X-Forwarded-Host` rewrite rule is applied |
| **Connection timeout after login** | Ensure HTTPS listener exists on port 443 |
| **Certificate validation failed** | For Cloudflare, enable proxy mode or use public CA |

## Traffic Flow

1. **Cloudflare** terminates public SSL, forwards to App Gateway
2. **App Gateway** receives on HTTPS (port 443) with Origin Certificate
3. **App Gateway** forwards to Container App with `Host: customDomain` and `X-Forwarded-*` headers
4. **EasyAuth** reads `X-Forwarded-Host` to construct redirect URI
5. **Entra ID** authenticates and redirects back through Cloudflare

## Scale to Zero Behaviour

The Container App is configured with `minReplicas: 0` to minimize costs during periods of inactivity.

### How It Works

| Setting | Value | Description |
|---------|-------|-------------|
| `minReplicas` | 0 | Allows scaling to zero replicas |
| `maxReplicas` | 1 | Maximum one replica (adjustable) |
| Scale rule | HTTP concurrent requests | Scales based on incoming traffic |

### User Experience

**Scale Down:**
- After ~5 minutes of no HTTP requests, the Container App scales to zero
- While at zero replicas, you pay nothing for compute (Consumption tier)

**Cold Start (Scale Up):**
- When the first request arrives after idle, the container must start from scratch
- **Expected cold start time: 10-30+ seconds** depending on:
  - Container image size (Open WebUI is ~1GB+)
  - Azure Files mount initialization
  - Application startup time (loading models, database, etc.)

### What Users See

1. First request after idle period → longer loading time (browser may appear to hang)
2. App Gateway health probes will show "Unhealthy" while scaled to zero
3. Once started, subsequent requests are fast until the next idle period

### Recommendations

| Scenario | Recommendation |
|----------|----------------|
| **PoC/Demo** | Keep `minReplicas: 0` for cost savings |
| **Development** | Keep `minReplicas: 0`, accept cold starts |
| **Production** | Set `minReplicas: 1` to avoid cold start latency |

To disable scale to zero, update `app.bicep`:

```bicep
scaleSettings: {
  maxReplicas: 1
  minReplicas: 1  // Always keep one replica running
  rules: [...]
}
```
