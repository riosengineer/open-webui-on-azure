# Open WebUI on Azure - Production Grade Quickstart

Deploy [Open WebUI](https://github.com/open-webui/open-webui) on Azure Container Apps with Entra ID authentication, Azure API Management (AI API Gateway), Microsoft (Azure) Foundry integration, and Application Gateway.

## Architecture

![Azure Open WebUI architecture](docs/architecture.drawio.png)

## Features

- **Open WebUI** on Azure Container Apps with native OAuth/OIDC Entra ID integration
- **Microsoft Foundry** with multiple models (GPT, Grok, Mistral, Llama, DeepSeek) using Managed Identity
- **Application Gateway** with custom domain and SSL termination
- **API Management with AI in Azure** Delegate API keys per team/user(s) with token tracking, limits, usage metrics, Entra OAuth policy validation
- **No secrets!** Managed Identity + OIDC throughout*
- **Infrastructure as Code** using Bicep with Azure Verified Modules
- **Secure by default** using internal ingresses and private endpoints**

> [!NOTE]
>
> - *Azure Container Apps still [requires Storage Account Access Keys for Azure File SMB mount?](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files?tabs=bash#set-up-a-storage-account) :(
>
> - **At the time of writing the 'New' Foundry account does not support BYOD/Fully private networking yet. It has been secured via ACL for inbound networking.

## Prerequisites

- Azure subscription(s) Owner access with Azure CLI and Bicep installed
- Custom domain with DNS provider (Cloudflare used in examples)
- SSL certificate (Cloudflare Origin Certificate for Full strict SSL mode and custom domain on ACA env)
- Application Developer Role (Entra)

## Deployment

> [!IMPORTANT]
> Before deploying, update the `.bicepparam` files with your values:
>
> **`infra/bicep/main.bicepparam`:**
> - `parApimPublisherEmail` - Your email address
> - `parApimPublisherName` - Your name
> - `parCustomDomain` - Your custom domain (e.g., `openwebui.example.com`)
> - `parLocation` - Your Azure region
>
> **Naming Convention:** If you change `parNamePrefix` in `app.bicepparam`, update `parFoundryName` in `main.bicepparam` to match (`${parNamePrefix}-foundry`).

### 1. Deploy Hub Infrastructure (VNet, DNS Zones, APIM shell)

Deploy the hub first to create networking, private DNS zones, and PE subnet:

```bash
# First deploy - creates VNet, DNS zones, PE subnet
# APIM will be created but Foundry backend won't be configured yet
az deployment sub create --location uksouth --template-file infra/bicep/main.bicep --parameters infra/bicep/main.bicepparam
```

> [!NOTE]
> This first deploy uses `parConfigureFoundry=false` (default) - Foundry backend and RBAC are skipped. We'll redeploy with `parConfigureFoundry=true` after the spoke is created.

**Note the output:**

- `outAppGatewayPublicIp` - Application Gateway public IP (for DNS)

### 2. Deploy App Infrastructure (Foundry, Container Apps)

Create the PFX certificate and deploy spoke:

```bash
# Create passwordless PFX and base64 encode it
openssl pkcs12 -export -out cloudflare-origin.pfx -inkey origin.key -in origin.pem -password pass:
cat cloudflare-origin.pfx | base64 -w0 > pfx.b64

# Deploy spoke infrastructure (Foundry PE will use hub's DNS zones)
az deployment sub create --location uksouth --template-file infra/bicep/app.bicep --parameters infra/bicep/app.bicepparam --parameters parCertificatePfxBase64="$(cat pfx.b64)"
```

**Note these outputs:**

- `outContainerAppFqdn` - Container App FQDN
- `outVirtualNetworkName` - Spoke VNet name  
- `outOpenWebUIAppId` - Entra ID app ID

**Also note the Container App Environment static IP:**

- Azure Portal → Container Apps Environment → Overview → Static IP

**Update `main.bicepparam` with spoke values:**

- `parContainerAppFqdn` - Use `outContainerAppFqdn`
- `parContainerAppStaticIp` - Container App Environment static IP
- `parSpokeVirtualNetworkName` - Use `outVirtualNetworkName`
- `parOpenWebUIAppId` - Use `outOpenWebUIAppId`

**Grant Admin Consent:**

1. Azure Portal → **Entra ID** → **App registrations** → **app-open-webui**
2. **API permissions** → **Grant admin consent**

### 3. Redeploy Hub (APIM Foundry Backend + RBAC)

Redeploy hub with `parConfigureFoundry=true` to configure APIM with Foundry backend and grant RBAC:

```bash
# Redeploy hub - now APIM gets Foundry endpoint and RBAC is assigned
az deployment sub create --location uksouth --template-file infra/bicep/main.bicep --parameters infra/bicep/main.bicepparam --parameters parConfigureFoundry=true
```

**Configure DNS:**

- Add A record pointing to Application Gateway public IP (`outAppGatewayPublicIp`)

**If using Cloudflare:**

- Enable proxy
- Set SSL/TLS mode to **Full (strict)**

### 4. Import OpenAPI Spec to APIM

> [!NOTE]
> This step is required due to Bicep's character limit on inline content. The OpenAPI spec must be imported manually via Azure CLI.

```bash
az apim api import --resource-group rg-lb-core --service-name <apim-name> --api-id openai --path "openai/v1" --specification-format OpenApiJson --specification-path infra/bicep/openapi/openai.openapi.json --display-name "Azure OpenAI v1 API" --protocols https --subscription-required true
```

## Configuration

### Connect Open WebUI to Microsoft Foundry (via APIM)

1. Navigate to Open WebUI and log in with Entra ID
2. Go to **Admin Settings** → **Connections**
3. Add OpenAI-compatible connection:
   - **API Base URL**: `https://<apim-name>.azure-api.net/openai/v1`
   - **Headers**: Get from APIM subscription

   ```json
   {
    "api-key": "<sub-key>"
   }
   ```

   - **API Type**: `OpenAI`
   - **Auth**: `OAuth`
   - **Model Ids**: Input all models deployed to Foundry,e.g. `gpt-5-mini`
