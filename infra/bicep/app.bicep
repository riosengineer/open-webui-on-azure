targetScope = 'subscription'
// ms graph extensibility
extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:1.0.0'

// ========== Type Imports ==========
import { FoundryDeploymentType, TagsType } from './shared/types.bicep'

// ========== Parameters ==========
param parLocation string
param parResourceGroupName string
param parVirtualNetworkAddressPrefix string
param parAcaSubnetAddressPrefix string
param parHubResourceGroupName string
param parHubVirtualNetworkName string
param parCustomDomain string
param parCertificateName string
param parApimName string = 'apim-open-webui'
@secure()
param parCertificatePfxBase64 string = ''
param parContainerAppAllowedIpAddresses array = []
param parContainerAppScaleSettings object
param parFoundryDeployments FoundryDeploymentType[]
param parTags TagsType
param parNamePrefix string = 'open-webui-app'

// MARK: - Existing Hub Resources
// Reference hub VNet and PE subnet
resource resHubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  scope: resourceGroup(parHubResourceGroupName)
  name: parHubVirtualNetworkName
}

resource resHubPeSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: resHubVnet
  name: 'pe-subnet'
}

// Reference Foundry private DNS zones in hub
resource resCognitiveServicesDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  scope: resourceGroup(parHubResourceGroupName)
  name: 'privatelink.cognitiveservices.azure.com'
}

resource resOpenAIDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  scope: resourceGroup(parHubResourceGroupName)
  name: 'privatelink.openai.azure.com'
}

resource resAIServicesDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  scope: resourceGroup(parHubResourceGroupName)
  name: 'privatelink.services.ai.azure.com'
}

// Variables
var varOpenWebUiShare = 'open-webui-share'
var varAppRegistrationName = 'app-open-webui'
var varIpSecurityRestrictions = [for ip in parContainerAppAllowedIpAddresses: {
  name: 'allow-${replace(ip, '/', '-')}'
  ipAddressRange: ip
  action: 'Allow'
}]
var varFoundryPrivateDnsZoneConfigs = [
  { privateDnsZoneResourceId: resCognitiveServicesDnsZone.id }
  { privateDnsZoneResourceId: resOpenAIDnsZone.id }
  { privateDnsZoneResourceId: resAIServicesDnsZone.id }
]
var varRoleDefinitions = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  cognitiveServicesUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  azureAIUser: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
}

// MARK: - Entra ID App Registration
resource resEntraIdApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: varAppRegistrationName
  uniqueName: varAppRegistrationName
  signInAudience: 'AzureADMyOrg'
  isFallbackPublicClient: true
  groupMembershipClaims: 'SecurityGroup'
  identifierUris: ['api://${varAppRegistrationName}']
  owners: {
    relationships: [
      deployer().objectId
    ]
  }
  appRoles: [
    {
      allowedMemberTypes: ['User']
      description: 'Administrator role with full access to Open WebUI'
      displayName: 'Administrator'
      id: guid(varAppRegistrationName, 'admin')
      isEnabled: true
      value: 'admin'
    }
    {
      allowedMemberTypes: ['User']
      description: 'Standard user role with default permissions'
      displayName: 'User'
      id: guid(varAppRegistrationName, 'user')
      isEnabled: true
      value: 'user'
    }
  ]
  optionalClaims: {
    idToken: [
      {
        name: 'groups'
        essential: false
        additionalProperties: []
      }
    ]
    accessToken: [
      {
        name: 'groups'
        essential: false
        additionalProperties: []
      }
    ]
  }
  api: {
    requestedAccessTokenVersion: 2
    oauth2PermissionScopes: [
      {
        adminConsentDescription: 'Allow the application to access Open WebUI on behalf of the signed-in user'
        adminConsentDisplayName: 'Access Open WebUI'
        id: guid(varAppRegistrationName, 'user_impersonation')
        isEnabled: true
        type: 'User'
        userConsentDescription: 'Allow the application to access Open WebUI on your behalf'
        userConsentDisplayName: 'Access Open WebUI'
        value: 'user_impersonation'
      }
    ]
  }
  web: {
    redirectUris: [
      'https://${parCustomDomain}/oauth/oidc/callback'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: true
      enableAccessTokenIssuance: true
    }
  }
  publicClient: {
    redirectUris: [
      'https://${parCustomDomain}/oauth/oidc/callback'
    ]
  }
  requiredResourceAccess: [
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
      resourceAccess: [
        {
          id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d' // User.Read (Delegated)
          type: 'Scope'
        }
        {
          id: 'bc024368-1153-4739-b217-4326f2e966d0' // GroupMember.Read.All (Delegated)
          type: 'Scope'
        }
        {
          id: 'c72d93c1-a342-4d87-90ff-27b3e0e79e0c' // ProfilePhoto.Read.All (Delegated)
          type: 'Scope'
        }
      ]
    }
  ]
}

// MARK: - Entra ID Service Principal
resource resEntraIdServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: resEntraIdApp.appId

}

// MARK: - Resource Group
module modResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  params: {
    name: parResourceGroupName
    location: parLocation
    tags: parTags
  }
}

// MARK: - Network Security Group
module modNsgContainerApp 'br/public:avm/res/network/network-security-group:0.5.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-aca-nsg'
    location: parLocation
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Virtual Network
module modVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-vnet'
    addressPrefixes: [
      parVirtualNetworkAddressPrefix
    ]
    subnets: [
      {
        name: '${parNamePrefix}-aca-subnet'
        addressPrefix: parAcaSubnetAddressPrefix
        networkSecurityGroupResourceId: modNsgContainerApp.outputs.resourceId
        serviceEndpoints: [
          'Microsoft.Storage'
          'Microsoft.CognitiveServices'
        ]
      }
    ]
    // Spoke to Hub VNet peering
    peerings: !empty(parHubVirtualNetworkName) ? [
      {
        remoteVirtualNetworkResourceId: resourceId(subscription().subscriptionId, parHubResourceGroupName, 'Microsoft.Network/virtualNetworks', parHubVirtualNetworkName)
        allowForwardedTraffic: true
        allowGatewayTransit: false
        allowVirtualNetworkAccess: true
        useRemoteGateways: false
      }
    ] : []
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Log Analytics Workspace
module modLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.13.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-law'
    location: parLocation
    skuName: 'PerGB2018'
    dailyQuotaGb: 1
    dataRetention: 30
    features: {
      disableLocalAuth: true
    }
  }
  dependsOn: [
    modResourceGroup
  ]
}

// MARK: - Application Insights
module modAppInsights 'br/public:avm/res/insights/component:0.7.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-appi'
    location: parLocation
    workspaceResourceId: modLogAnalyticsWorkspace.outputs.resourceId
    applicationType: 'web'
    disableLocalAuth: true
    kind: 'web'
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Key Vault
module modKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-kv'
    location: parLocation
    sku: 'standard'
    enablePurgeProtection: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    secrets: !empty(parCertificatePfxBase64) ? [
      {
        name: parCertificateName
        value: parCertificatePfxBase64
        contentType: 'application/x-pkcs12'
      }
    ] : []
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Storage Account
module modStorageAccount 'br/public:avm/res/storage/storage-account:0.29.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: replace('${parNamePrefix}sa', '-', '')
    location: parLocation
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true
    allowBlobPublicAccess: false
    managedIdentities: {
      systemAssigned: true
    }
    fileServices: {
      shareDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
      shares: [
        {
          name: varOpenWebUiShare
          shareQuota: 100
          enabledProtocols: 'SMB'
          accessTier: 'TransactionOptimized'
        }
      ]
    }
    networkAcls: {
       virtualNetworkRules:[
          {
            id: modVirtualNetwork.outputs.subnetResourceIds[0]
            ignoreMissingVnetServiceEndpoint: false
          }
       ]
    }
    secretsExportConfiguration: {
      keyVaultResourceId: modKeyVault.outputs.resourceId
      accessKey1Name: 'accessKey1'
      accessKey2Name: 'accessKey2'
      connectionString1Name: 'connectionString1'
      connectionString2Name: 'connectionString2'
    }
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Container App Environment Managed Identity
module modEnvIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: 'umi-${parNamePrefix}'
    location: parLocation
  }
  dependsOn: [modResourceGroup]
}

// MARK: - RBAC for Environment Identity
module modEnvKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    principalId: modEnvIdentity.outputs.principalId
    roleName: 'Key Vault Secrets User'
    resourceId: modKeyVault.outputs.resourceId
    roleDefinitionId: varRoleDefinitions.keyVaultSecretsUser
    principalType: 'ServicePrincipal'
  }
}

// MARK: - Container App Environment
module modContainerAppEnv 'br/public:avm/res/app/managed-environment:0.11.3' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: replace('${parNamePrefix}-aca-env', '-', '')
    location: parLocation
    appInsightsConnectionString: modAppInsights.outputs.connectionString
    publicNetworkAccess: 'Disabled'
    storages: [
      {
        kind: 'SMB'
        accessMode: 'ReadWrite'
        shareName: varOpenWebUiShare
        storageAccountName: modStorageAccount.outputs.name
      }
    ]
    internal: true
    infrastructureSubnetResourceId: modVirtualNetwork.outputs.subnetResourceIds[0]
    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        modEnvIdentity.outputs.resourceId
      ]
    }
    // az keyvault certificate import --vault-name <kv-name> --name <cert-name> --file file.pfx
    certificate: {
      name: parCertificateName
      certificateKeyVaultProperties: {
        identityResourceId: modEnvIdentity.outputs.resourceId
        keyVaultUrl: '${modKeyVault.outputs.uri}secrets/${parCertificateName}'
      }
    }
  }
  dependsOn: [modResourceGroup, modEnvKeyVaultRbac]
}

// MARK: - Container App
module modContainerApp 'br/public:avm/res/app/container-app:0.19.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-aca'
    ingressTargetPort: 8080
    stickySessionsAffinity: 'sticky'
    ipSecurityRestrictions: !empty(parContainerAppAllowedIpAddresses) ? varIpSecurityRestrictions : []
    customDomains: [
      {
        name: parCustomDomain
        certificateId: '${modContainerAppEnv.outputs.resourceId}/certificates/${parCertificateName}'
        bindingType: 'SniEnabled'
      }
    ]
    containers: [
      {
        name: 'open-webui-container'
        image: 'ghcr.io/open-webui/open-webui:main'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
          // see https://docs.openwebui.com/getting-started/env-configuration/
          {
            name: 'WEBUI_URL'
            value: 'https://${parCustomDomain}'
          }
          {
            name: 'ENABLE_OAUTH_SIGNUP'
            value: 'true'
          }
          {
            name: 'ENABLE_LOGIN_FORM'
            value: 'false'
          }
          {
            name: 'ENABLE_OAUTH_PERSISTENT_CONFIG'
            value: 'false'
          }
          {
            name: 'OAUTH_CLIENT_ID'
            value: resEntraIdApp.appId
          }
          {
            name: 'OAUTH_CODE_CHALLENGE_METHOD'
            value: 'S256'
          }
          {
            name: 'OAUTH_PROVIDER_NAME'
            value: 'Microsoft Entra ID'
          }
          {
            name: 'OAUTH_SCOPES'
            value: 'openid email profile api://${varAppRegistrationName}/user_impersonation User.Read GroupMember.Read.All ProfilePhoto.Read.All'
          }
          {
            name: 'OPENID_PROVIDER_URL'
            value: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0/.well-known/openid-configuration'
          }
          {
            name: 'OAUTH_EMAIL_CLAIM'
            value: 'email'
          }
          {
            name: 'OAUTH_USERNAME_CLAIM'
            value: 'name'
          }
          {
            name: 'OPENAI_API_BASE_URL'
            value: 'https://${parApimName}.azure-api.net/openai/v1'
          }
          {
            name: 'ENV'
            value: 'prod'
          }
          {
            name: 'DATA_DIR'
            value: '/app/data'
          }
          {
            name: 'WEBUI_NAME'
            value: 'Open WebUI'
          }
          {
            name: 'ENABLE_SIGNUP'
            value: 'false' 
          }
          {
            name: 'DEFAULT_USER_ROLE'
            value: 'user'
          }
          {
            name: 'ENABLE_ADMIN_CHAT_ACCESS'
            value: 'true'
          }
          {
            name: 'ENABLE_ADMIN_EXPORT'
            value: 'true'
          }
          {
            name: 'WEBUI_SESSION_COOKIE_SAME_SITE'
            value: 'lax' 
          }
          {
            name: 'WEBUI_SESSION_COOKIE_SECURE'
            value: 'true'
          }
          {
            name: 'ENABLE_COMMUNITY_SHARING'
            value: 'false'
          }
          {
            name: 'ENABLE_MESSAGE_RATING'
            value: 'true'
          }
          {
            name: 'GLOBAL_LOG_LEVEL'
            value: 'INFO'
          }
          {
            name: 'ENABLE_OAUTH_ROLE_MANAGEMENT'
            value: 'true'
          }
          {
            name: 'OAUTH_ROLES_CLAIM'
            value: 'roles'
          }
          {
            name: 'OAUTH_ALLOWED_ROLES'
            value: 'user,admin'
          }
          {
            name: 'OAUTH_ADMIN_ROLES'
            value: 'admin'
          }
          {
            name: 'ENABLE_OAUTH_GROUP_MANAGEMENT'
            value: 'true'
          }
          {
            name: 'ENABLE_OAUTH_GROUP_CREATION'
            value: 'true'
          }
          {
            name: 'OAUTH_GROUPS_CLAIM'
            value: 'groups'
          }
          {
            name: 'AIOHTTP_CLIENT_TIMEOUT'
            value: '300'
          }
        ]
        volumeMounts: [
          {
            volumeName: 'open-webui-share'
            mountPath: '/app/data'
          }
        ]
        probes: [
          {
            type: 'startup'
            httpGet: {
              path: '/health'
              port: 8080
            }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 30 // 30 × 5s = 150s max startup time
          }
          {
            type: 'liveness'
            httpGet: {
              path: '/health'
              port: 8080
            }
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3
          }
          {
            type: 'readiness'
            httpGet: {
              path: '/health'
              port: 8080
            }
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
          }
        ]
      }
    ]
    secrets: [
      {
        name: 'storage-account-access-key'
        keyVaultUrl: '${modKeyVault.outputs.uri}secrets/accessKey1'
        identity: 'System'
      }
    ]
    volumes: [
      {
        name: 'open-webui-share'
        storageName: varOpenWebUiShare
        storageType: 'AzureFile'
        mountOptions: 'nobrl,noperm,mfsymlinks,cache=strict'
      }
    ]
    scaleSettings: parContainerAppScaleSettings
    ingressAllowInsecure: false
    environmentResourceId: modContainerAppEnv.outputs.resourceId
    location: parLocation
    managedIdentities: {
      systemAssigned: true
    }
  }
  dependsOn: [modResourceGroup]
}

// MARK: - RBAC for Container App
module modContainerAppKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    principalId: modContainerApp.outputs.systemAssignedMIPrincipalId!
    roleName: 'Key Vault Secrets User'
    resourceId: modKeyVault.outputs.resourceId
    roleDefinitionId: varRoleDefinitions.keyVaultSecretsUser
    principalType: 'ServicePrincipal'
  }
}

// MARK: - Microsoft Foundry (AI Services)
module modFoundry 'br/public:avm/res/cognitive-services/account:0.14.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parNamePrefix}-foundry'
    location: parLocation
    kind: 'AIServices'
    sku: 'S0'
    disableLocalAuth: true
    managedIdentities: {
      systemAssigned: true
    }
    allowProjectManagement: true
    privateEndpoints: [
      {
        name: '${parNamePrefix}-foundry-pe'
        subnetResourceId: resHubPeSubnet.id
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: varFoundryPrivateDnsZoneConfigs
        }
      }
    ]
    customSubDomainName: replace('${parNamePrefix}-foundry', '-', '')
    networkAcls:{
      defaultAction: 'Deny'
      virtualNetworkRules:[
        {
          id: modVirtualNetwork.outputs.subnetResourceIds[0]
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    deployments: parFoundryDeployments
    // Container App RBAC - APIM RBAC is assigned in main.bicep after APIM is created
    roleAssignments: [
      {
        principalId: modContainerApp.outputs.systemAssignedMIPrincipalId!
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: varRoleDefinitions.cognitiveServicesUser
      }
      {
        principalId: modContainerApp.outputs.systemAssignedMIPrincipalId!
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: varRoleDefinitions.azureAIUser
      }
    ]
  }
  dependsOn: [modResourceGroup]
}

// MARK: - Outputs
output outContainerAppFqdn string = modContainerApp.outputs.fqdn
output outContainerAppResourceId string = modContainerApp.outputs.resourceId
output outContainerAppEnvDefaultDomain string = modContainerAppEnv.outputs.defaultDomain
output outVirtualNetworkName string = modVirtualNetwork.outputs.name
output outVirtualNetworkResourceId string = modVirtualNetwork.outputs.resourceId
output outFoundryEndpoint string = modFoundry.outputs.endpoint
output outOpenWebUIAppId string = resEntraIdApp.appId
