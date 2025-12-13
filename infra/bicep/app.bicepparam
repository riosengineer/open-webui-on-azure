using './app.bicep'

param parLocation = 'uksouth'
param parResourceGroupName = 'rg-open-webui-app'
param parVirtualNetworkAddressPrefix = '10.0.4.0/22'
param parAcaSubnetAddressPrefix = '10.0.4.0/23'
param parHubResourceGroupName = 'rg-lb-core'
param parHubVirtualNetworkName = 'vnet-lb-core'
param parCustomDomain = 'openwebui.rios.engineer'
param parCertificateName = 'cloudflare-origin-cert'
param parApimName = 'apim-open-webui'
param parApimAllowedIpAddresses = [
  '172.167.219.126' // APIM VIP - New Foundry doesn't support end to end private networking yet.
]

param parContainerAppAllowedIpAddresses = [
  '188.74.98.58/32' // My IP for testing
  '10.0.0.64/26' // App Gateway subnet
]

param parFoundryDeployments = [
  {
    name: 'gpt-4o'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'gpt-4o-mini'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'gpt-5-mini'
    model: {
      format: 'OpenAI'
      name: 'gpt-5-mini'
      version: '2025-08-07'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'Mistral-Large-3'
    model: {
      format: 'Mistral AI'
      name: 'Mistral-Large-3'
      version: '1'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'Llama-4-Maverick-17B-128E-Instruct-FP8'
    model: {
      format: 'Meta'
      name: 'Llama-4-Maverick-17B-128E-Instruct-FP8'
      version: '1'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'DeepSeek-V3.1'
    model: {
      format: 'DeepSeek'
      name: 'DeepSeek-V3.1'
      version: '1'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'grok-4-fast-reasoning'
    model: {
      format: 'xAI'
      name: 'grok-4-fast-reasoning'
      version: '1'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
  {
    name: 'text-embedding-3-large'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 100
    }
  }
]
