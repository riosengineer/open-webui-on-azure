# Azure Open WebUI Quickstart

Deploy [Open WebUI](https://github.com/open-webui/open-webui) on Azure Container Apps with Entra ID authentication, Microsoft (Azure) Foundry integration, and Application Gateway.

## Architecture

```markdown
![Azure Open WebUI architecture](docs/architecture.svg)
```

## Features

- **Open WebUI** on Azure Container Apps with native OAuth/OIDC Entra ID integration
- **Microsoft Foundry** with multiple models (GPT, Grok, Mistral, Llama, DeepSeek) using Managed Identity
- **Application Gateway** with custom domain and SSL termination
- **API Management** Delegate API keys per team/user(s) with token tracking, usages, Entra policy validation
- **No secrets!** Managed Identity + OIDC throughout*
- **Infrastructure as Code** using Bicep with Azure Verified Modules
- **Secure by default** using internal ingresses and private endpoints**

> [!NOTE]
> *Azure Container Apps still [requires Storage Account Access Keys for Azure File SMB mount?](https://learn.microsoft.com/en-us/azure/container-apps/storage-mounts-azure-files?tabs=bash#set-up-a-storage-account) :(
> **At the time of writing the 'New' Foundry account does not support BYOD/Fully private networking yet. It has been secured via ACL in this demo.

## Prerequisites

- Azure subscription(s) access with Azure CLI and Bicep installed
- Custom domain with DNS provider (Cloudflare used in examples)
- SSL certificate (Cloudflare Origin Certificate for Full strict SSL mode and custom domain on ACA env)
- Application Administrator (Entra role)

## Deployment

### 1. Deploy 'Hub' Infrastructure (APIM, Application Gateway)

Once deployed, make a note of the outputs as you will need some of these to populate parameters in `app.bicepparam`
```bash
az deployment sub create \
  --location uksouth \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.bicepparam
```

**Configure DNS:**
- Add A record pointing to Application Gateway public IP
 
**If Cloudflare**
- Enable proxy (orange cloud)
- Set SSL/TLS mode to **Full (strict)**

### 2. Deploy App Infrastructure (Container App, Microsoft Foundry)

```bash
az deployment sub create \
  --location uksouth \
  --template-file infra/bicep/app.bicep \
  --parameters infra/bicep/app.bicepparam
```

**Grant Admin Consent (one-time):**
1. Azure Portal → **Entra ID** → **App registrations** → **app-open-webui**
2. **API permissions** → **Grant admin consent**

### 3. Import OpenAPI Spec to APIM

> [!NOTE] 
> This step is required due to Bicep's character limit on inline content. The OpenAPI spec must be imported manually via Azure CLI.

```bash
az apim api import \
  --resource-group rg-lb-core \
  --service-name <apim-name> \
  --api-id openai \
  --path "openai/v1" \
  --specification-format OpenApiJson \
  --specification-path infra/bicep/openapi/openai.openapi.json \
  --display-name "Azure OpenAI v1 API" \
  --protocols https \
  --subscription-required true
```

## Configuration

### Connect Open WebUI to Microsoft Foundry

1. Navigate to Open WebUI and log in with Entra ID
2. Go to **Admin Settings** → **Connections**
3. Add OpenAI-compatible connection:
   - **API Base URL**: `https://<apim-name>.azure-api.net/openai/v1`
   - **API Key**: Get from APIM subscription (see below)
   - **API Type**: `OpenAI`
   - **Auth**: `OAuth`
   - **Model Ids**: Input all models deployed to Foundry,e.g. `gpt-5-mini`