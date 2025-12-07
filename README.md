# Azure Open WebUI Quickstart

Deploy [Open WebUI](https://github.com/open-webui/open-webui) on Azure Container Apps with Entra ID authentication, Azure AI Foundry integration, and Application Gateway.

## Architecture

```
User → Cloudflare (DNS/SSL) → Application Gateway → Container App (EasyAuth) → Open WebUI
                                                                                    ↓
                                                                            Azure AI Foundry (GPT-4o)
```

## Features

- **Open WebUI** running on Azure Container Apps (Consumption tier)
- **Entra ID authentication** via EasyAuth (built-in authentication)
- **Azure AI Foundry** with GPT-4o deployment using Managed Identity
- **Application Gateway** with custom domain and Cloudflare Origin Certificate
- **Scale to zero** for cost optimisation (cold start ~10-30s)
- **Infrastructure as Code** using Bicep with Azure Verified Modules (AVM)

## Prerequisites

- Azure subscription
- Azure CLI with Bicep
- Custom domain with Cloudflare (or alternative DNS provider)
- Cloudflare Origin Certificate (for Full strict SSL mode)

## Deployment

### 1. Deploy Spoke Resources (Container App, AI Foundry)

```bash
az deployment sub create \
  --location uksouth \
  --template-file infra/bicep/app.bicep \
  --parameters infra/bicep/app.bicepparam
```

### 2. Deploy Hub Resources (Application Gateway, API Management)

```bash
az deployment sub create \
  --location uksouth \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.bicepparam
```

### 3. Import Azure OpenAI Operations from OpenAPI Specification

The Bicep deployment creates the `openai` API with the policy, but the OpenAPI spec is too large to embed in Bicep. Import the operations after deployment:

```bash
# Set your values
RESOURCE_GROUP="rg-lb-core"
APIM_NAME="apim-open-webui"

# Import the OpenAPI specification operations into the existing API
az apim api import \
  --resource-group $RESOURCE_GROUP \
  --service-name $APIM_NAME \
  --api-id openai \
  --path openai \
  --specification-format OpenApi \
  --specification-path infra/bicep/openapi/openai.openapi.json
```

> **Note**: The Bicep creates the API shell with the policy (`openai-api-openwebui.xml`). This CLI command adds the 45+ operations from the OpenAPI spec. The policy uses Azure Foundry's v1 API for OpenAI compatibility.

### 4. Configure Cloudflare DNS

1. Add an A record pointing your custom domain to the Application Gateway public IP
2. Enable **Proxy (orange cloud)**
3. Set SSL/TLS mode to **Full (strict)**

## Post-Deployment: Connect Open WebUI to Azure OpenAI via APIM

After deployment, configure Open WebUI to call Azure OpenAI through your APIM gateway:

### Option 1: Direct Connection to APIM (Recommended)

1. Navigate to your Open WebUI instance
2. Log in with your Entra ID account
3. Go to **Admin Settings** → **Connections**
4. Click **+ Add Connection** (OpenAI type)
5. Configure the connection:

| Field | Value |
|-------|-------|
| **Name** | `Azure OpenAI via APIM` |
| **API Base URL** | `https://apim-open-webui.azure-api.net/openai/v1` |
| **API Key** | Get from APIM → Subscriptions → Copy primary key |
| **API Type** | `OpenAI` |

1. Click **Save** and **Verify Connection**

### Getting Your APIM Subscription Key

```bash
# Get the built-in subscription key
az rest --method post \
  --url "/subscriptions/<subscription-id>/resourceGroups/rg-lb-core/providers/Microsoft.ApiManagement/service/apim-open-webui/subscriptions/master/listSecrets?api-version=2024-05-01" \
  --query "primaryKey" -o tsv
```

Or get it from the Azure Portal:
1. Go to API Management → `apim-open-webui`
2. Navigate to **Subscriptions**
3. Find **Built-in all-access subscription**
4. Click **Show/hide keys** and copy the **Primary key**

### Testing from Open WebUI

Once configured, you can:
- Select models from the dropdown (they'll appear after connection is verified)
- Start a new chat
- Send a message to test the connection

The request flow will be:
```
Open WebUI → APIM Gateway → Managed Identity Auth → Azure AI Foundry → GPT-4o
```

> **Note**: The APIM subscription key authenticates requests to APIM, then APIM uses its managed identity to authenticate to Azure AI Foundry. No Foundry API keys are exposed.

### Allow APIM egress on Foundry firewall (if using network ACLs)

If your Foundry instance denies public traffic by default, allowlist the APIM gateway IPs:

```bash
APIM_IPS=$(az apim show \
  --resource-group rg-lb-core \
  --name apim-open-webui \
  --query publicIpAddresses \
  -o tsv)
echo "$APIM_IPS"  # add these to Foundry firewall/IP rules
```

Then add the printed IPs to the Foundry firewall IP rules (or use a private endpoint for long-term private access).

## Scale to Zero Behaviour

The Container App is configured with `minReplicas: 0` to minimise costs:

- Scales to zero after ~5 minutes of inactivity
- Cold start time: 10-30+ seconds (container image is ~1GB)
- Set `minReplicas: 1` in `app.bicep` for always-on behaviour

## Documentation

- [Custom Domain with EasyAuth](docs/custom-domain-easyauth.md) - Detailed guide for configuring custom domains with Entra ID authentication behind Application Gateway

## Resources

- [Open WebUI Documentation](https://docs.openwebui.com/)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [Azure AI Foundry](https://learn.microsoft.com/azure/ai-services/)
- [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/)