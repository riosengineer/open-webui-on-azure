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

### 2. Deploy Hub Resources (Application Gateway)

```bash
az deployment sub create \
  --location uksouth \
  --template-file infra/bicep/main.bicep \
  --parameters infra/bicep/main.bicepparam
```

### 3. Configure Cloudflare DNS

1. Add an A record pointing your custom domain to the Application Gateway public IP
2. Enable **Proxy (orange cloud)**
3. Set SSL/TLS mode to **Full (strict)**

## Post-Deployment: Connect Open WebUI to Azure AI Foundry

After deployment, you need to configure the Azure OpenAI connection in Open WebUI:

1. Navigate to your Open WebUI instance (e.g., `https://openwebui.yourdomain.com`)
2. Log in with your Entra ID account
3. Go to **Admin Settings** → **Connections**
4. Click **+ Add Connection** (OpenAI type)
5. Configure the connection:

| Field | Value |
|-------|-------|
| **URL** | `https://<your-foundry-name>.openai.azure.com/` |
| **Auth Type** | `Entra ID` |
| **API Version** | `2024-10-21` |
| **Deployment Names** | `gpt-4o` |

6. Click **Save**

The GPT-4o model will now appear in the model dropdown when starting a new chat.

> **Note**: The connection uses Managed Identity authentication - no API keys required. The Container App's system-assigned identity has the `Cognitive Services OpenAI User` role on the AI Foundry resource.

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