targetScope = 'subscription'
// ms graph extensibility
extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:1.0.0'

// ========== Type Imports ==========
import { TagsType } from './shared/types.bicep'

// ========== MARK: Parameters ==========
param parLocation string
param parResourceGroupName string
param parAppGatewayName string
param parApimName string
param parApimPublisherEmail string
param parApimPublisherName string
param parVirtualNetworkName string
param parVirtualNetworkAddressPrefix string
param parApimSubnetAddressPrefix string
param parAppGatewaySubnetAddressPrefix string
param parPeSubnetAddressPrefix string
param parApimSku string
param parAppGatewaySku string
param parSpokeResourceGroupName string
param parSpokeVirtualNetworkName string
@validate(
  x => !contains(x, 'https://'), 'The Container App param FQDN must not contain the "https://" prefix.'
)
param parContainerAppFqdn string
param parContainerAppStaticIp string
param parCustomDomain string
param parSpokeKeyVaultName string
param parTrustedRootCertificateSecretName string
param parSslCertificateSecretName string
param parTags TagsType
@description('Optional: OpenWebUI App ID from app.bicep deployment. Leave empty for initial deployment.')
param parOpenWebUIAppId string = ''
@description('Foundry resource name in spoke - used to reference existing Foundry and get its endpoint')
param parFoundryName string = 'open-webui-app-foundry'
@description('Set to true after spoke (app.bicep) has been deployed to configure APIM Foundry backend and RBAC')
param parConfigureFoundry bool = false


// ========== MARK: Variables ==========
var varOpenWebUi = 'open-webui'
var varNsgRules = loadJsonContent('./shared/nsg-rules.json')
var varContainerAppEnvDefaultDomain = !empty(parContainerAppFqdn) ? join(skip(split(parContainerAppFqdn, '.'), 1), '.') : ''
var varContainerAppName = !empty(parContainerAppFqdn) ? split(parContainerAppFqdn, '.')[0] : ''
var varTrustedRootCertificateBase64 = loadTextContent('./cert/cloudflare-origin-ca.cer')
var varRoleDefinitions = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

// Reference existing Foundry in spoke to get its endpoint dynamically
// Only reference when parConfigureFoundry is true (second hub deployment)
resource resFoundryExisting 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (parConfigureFoundry) {
  scope: resourceGroup(parSpokeResourceGroupName)
  name: parFoundryName
}

// Public IP configurations for loop deployment
var varPublicIpConfigs = [
  {
    key: 'appgw'
    name: '${parAppGatewayName}-pip'
    dnsLabel: null
  }
  {
    key: 'apim'
    name: '${parApimName}-pip'
    dnsLabel: '${parApimName}-${uniqueString(subscription().subscriptionId, parResourceGroupName)}'
  }
]

// MARK: - Resource Group
module modResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  params: {
    name: parResourceGroupName
    location: parLocation
    tags: parTags
  }
}

// MARK: - Networking
module modNetworking 'modules/networking.bicep' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    parNamePrefix: varOpenWebUi
    parLocation: parLocation
    parVirtualNetworkName: parVirtualNetworkName
    parVirtualNetworkAddressPrefix: parVirtualNetworkAddressPrefix
    parApimSubnetAddressPrefix: parApimSubnetAddressPrefix
    parAppGatewaySubnetAddressPrefix: parAppGatewaySubnetAddressPrefix
    parPeSubnetAddressPrefix: parPeSubnetAddressPrefix
    parSpokeResourceGroupName: parSpokeResourceGroupName
    parSpokeVirtualNetworkName: parSpokeVirtualNetworkName
    parContainerAppEnvDefaultDomain: varContainerAppEnvDefaultDomain
    parContainerAppName: varContainerAppName
    parContainerAppStaticIp: parContainerAppStaticIp
    parNsgRules: varNsgRules
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Monitoring
module modMonitoring 'modules/monitoring.bicep' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    parLocation: parLocation
    parNamePrefix: varOpenWebUi
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Security (Identities & Key Vaults)
module modSecurity 'modules/security.bicep' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    parLocation: parLocation
    parAppGatewayName: parAppGatewayName
    parTrustedRootCertificateSecretName: parTrustedRootCertificateSecretName
    parTrustedRootCertificateBase64: varTrustedRootCertificateBase64
    parCustomDomain: parCustomDomain
  }
  dependsOn: [modResourceGroup]
}

// MARK: - RBAC for Spoke Key Vault
module modAppGatewaySpokeKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (!empty(parCustomDomain) && !empty(parSpokeKeyVaultName)) {
  scope: resourceGroup(parSpokeResourceGroupName)
  params: {
    principalId: modSecurity.outputs.userAssignedIdentityPrincipalId
    resourceId: resourceId(subscription().subscriptionId, parSpokeResourceGroupName, 'Microsoft.KeyVault/vaults', parSpokeKeyVaultName)
    roleDefinitionId: varRoleDefinitions.keyVaultSecretsUser
  }
}

// MARK: - Public IP Addresses
module modPublicIps 'br/public:avm/res/network/public-ip-address:0.8.0' = [for config in varPublicIpConfigs: {
  scope: resourceGroup(parResourceGroupName)
  name: 'pip-${config.key}'
  params: {
    name: config.name
    location: parLocation
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    zones: []
    dnsSettings: config.dnsLabel != null ? {
      domainNameLabel: config.dnsLabel!
    } : null
  }
  dependsOn: [modResourceGroup]
}]

// MARK: - Application Gateway
module modAppGateway 'modules/app-gateway.bicep' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    parAppGatewayName: parAppGatewayName
    parLocation: parLocation
    parSku: parAppGatewaySku
    parContainerAppFqdn: parContainerAppFqdn
    parCustomDomain: parCustomDomain
    parSpokeKeyVaultName: parSpokeKeyVaultName
    parTrustedRootCertificateSecretName: parTrustedRootCertificateSecretName
    parSslCertificateSecretName: parSslCertificateSecretName
    parAppGatewaySubnetId: modNetworking.outputs.appGatewaySubnetResourceId
    parPublicIpResourceId: modPublicIps[0].outputs.resourceId
    parUserAssignedIdentityResourceId: modSecurity.outputs.userAssignedIdentityResourceId
    parHubKeyVaultUri: modSecurity.outputs.hubKeyVaultUri
    parResourceGroupName: parResourceGroupName
  }
  dependsOn: [
    modResourceGroup
  ]
}

// MARK: - API Management
module modApim 'modules/apim.bicep' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    parApimName: parApimName
    parLocation: parLocation
    parSku: parApimSku
    parPublisherEmail: parApimPublisherEmail
    parPublisherName: parApimPublisherName
    parFoundryEndpoint: parConfigureFoundry ? resFoundryExisting!.properties.endpoint : ''
    parOpenWebUIAppId: !empty(parOpenWebUIAppId) ? parOpenWebUIAppId : ''
    parAppInsightsName: modMonitoring.outputs.appInsightsName
    parAppInsightsResourceId: modMonitoring.outputs.appInsightsResourceId
    parAppInsightsConnectionString: modMonitoring.outputs.appInsightsConnectionString
    parLogAnalyticsWorkspaceResourceId: modMonitoring.outputs.logAnalyticsWorkspaceResourceId
    parApimSubnetResourceId: modNetworking.outputs.apimSubnetResourceId
    parApimPublicIpResourceId: modPublicIps[1].outputs.resourceId
  }
  dependsOn: [
    modResourceGroup
  ]
}

// MARK: - APIM → Foundry RBAC
// Grant APIM managed identity access to Foundry (Cognitive Services User + Azure AI User)
// Only configure when parConfigureFoundry is true (second hub deployment)
module modApimFoundryCognitiveServicesUserRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (parConfigureFoundry) {
  scope: resourceGroup(parSpokeResourceGroupName)
  params: {
    principalId: modApim.outputs.systemAssignedMIPrincipalId
    resourceId: resFoundryExisting!.id
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
    principalType: 'ServicePrincipal'
  }
}

module modApimFoundryAzureAIUserRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (parConfigureFoundry) {
  scope: resourceGroup(parSpokeResourceGroupName)
  params: {
    principalId: modApim.outputs.systemAssignedMIPrincipalId
    resourceId: resFoundryExisting!.id
    roleDefinitionId: '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Azure AI User
    principalType: 'ServicePrincipal'
  }
}

// MARK: - APIM Private DNS A Record
// Get existing APIM resource to read its private IP
resource resApimExisting 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  scope: resourceGroup(parResourceGroupName)
  name: parApimName
}

module modApimDnsRecord 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: modNetworking.outputs.apimPrivateDnsZoneName
    location: 'global'
    a: [
      {
        name: parApimName
        ttl: 3600
        aRecords: [
          { ipv4Address: resApimExisting.properties.privateIPAddresses[0] }
        ]
      }
    ]
  }
}

// MARK: - Outputs
output outApimName string = modApim.outputs.name
output outApimResourceId string = modApim.outputs.resourceId
output outApimGatewayUrl string = modApim.outputs.gatewayUrl
output outApimSystemAssignedPrincipalId string = modApim.outputs.systemAssignedMIPrincipalId
output outAppInsightsConnectionString string = modMonitoring.outputs.appInsightsConnectionString
output outAppInsightsResourceId string = modMonitoring.outputs.appInsightsResourceId
output outAppGatewayPublicIp string = modPublicIps[0].outputs.resourceId
output outApimPublicIp string = modPublicIps[1].outputs.ipAddress
output outVirtualNetworkResourceId string = modNetworking.outputs.virtualNetworkResourceId
output outVirtualNetworkName string = modNetworking.outputs.virtualNetworkName
output outContainerAppFqdn string = parContainerAppFqdn
