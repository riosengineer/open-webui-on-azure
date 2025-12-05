targetScope = 'subscription'

extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:0.1.8-preview'

param parLocation string = 'uksouth'
param parResourceGroupName string
param parVirtualNetworkAddressPrefix string
param parAcaSubnetAddressPrefix string
param parHubResourceGroupName string
param parHubVirtualNetworkName string
param parCustomDomain string
param parCertificateName string = 'cloudflare-origin-cert'

var varOpenWebUiShare = 'open-webui-share'
var varOpenWebUiApp = 'open-webui-app'
var varAppRegistrationName = 'app-open-webui'

resource entraIdApp 'Microsoft.Graph/applications@v1.0' = {
  displayName: varAppRegistrationName
  uniqueName: varAppRegistrationName
  signInAudience: 'AzureADMyOrg'
  web: {
    redirectUris: [
      'https://${parCustomDomain}/.auth/login/aad/callback'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: true
    }
  }
  requiredResourceAccess: [
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000' // Microsoft Graph
      resourceAccess: [
        {
          id: 'e1fe6dd8-ba31-4d61-89e7-88639da4683d' // User.Read
          type: 'Scope'
        }
      ]
    }
  ]
}

resource entraIdServicePrincipal 'Microsoft.Graph/servicePrincipals@v1.0' = {
  appId: entraIdApp.appId
}

module modResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  params: {
    name: parResourceGroupName
    location: parLocation
  }
}

module nsgContainerApp 'br/public:avm/res/network/network-security-group:0.5.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-aca-nsg'
    location: parLocation
  }
  dependsOn: [modResourceGroup]
}

module modVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-vnet'
    addressPrefixes: [
      parVirtualNetworkAddressPrefix
    ]
    subnets: [
      {
        name: '${varOpenWebUiApp}-aca-subnet'
        addressPrefix: parAcaSubnetAddressPrefix
        networkSecurityGroupResourceId: nsgContainerApp.outputs.resourceId
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

module modLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.13.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-law'
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

module modAppInsights 'br/public:avm/res/insights/component:0.7.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-appi'
    location: parLocation
    workspaceResourceId: modLogAnalyticsWorkspace.outputs.resourceId
    applicationType: 'web'
    disableLocalAuth: true
    kind: 'web'
  }
  dependsOn: [modResourceGroup]
}

module modKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-kv'
    location: parLocation
    sku: 'standard'
    enablePurgeProtection: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
  dependsOn: [modResourceGroup]
}

module modStorageAccount 'br/public:avm/res/storage/storage-account:0.29.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: replace('${varOpenWebUiApp}sa', '-', '')
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

module modEnvIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: 'umi-${varOpenWebUiApp}'
    location: parLocation
  }
  dependsOn: [modResourceGroup]
}

module modEnvKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    principalId: modEnvIdentity.outputs.principalId
    roleName: 'Key Vault Secrets User'
    resourceId: modKeyVault.outputs.resourceId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'
    principalType: 'ServicePrincipal'
  }
}

module modContainerAppEnv 'br/public:avm/res/app/managed-environment:0.11.3' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: replace('${varOpenWebUiApp}-aca-env', '-', '')
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

module modContainerApp 'br/public:avm/res/app/container-app:0.19.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-aca'
    ingressTargetPort: 8080
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
          cpu: 2
          memory: '4Gi'
        }
        volumeMounts: [
          {
            volumeName: 'open-webui-share'
            mountPath: '/app/data'
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
        mountOptions: 'nobrl'
      }
    ]
    scaleSettings: {
      maxReplicas: 1
      minReplicas: 0
      rules: [
        {
          name: 'http-rule'
          http: {
            metadata: {
              concurrentRequests: '10'
            }
          }
        }
      ]
    }
    authConfig: {
      identityProviders: {
        azureActiveDirectory: {
          enabled: true
          registration: {
            clientId: entraIdApp.appId
            openIdIssuer: '${environment().authentication.loginEndpoint}${tenant().tenantId}/v2.0'
          }
          validation: {
            allowedAudiences: [
              'api://${entraIdApp.appId}'
            ]
            defaultAuthorizationPolicy: {
              allowedApplications: [
                entraIdApp.appId
              ]
            }
          }
        }
      }
      httpSettings: {
        requireHttps: true
        forwardProxy: {
          convention: 'Standard'
        }
      }
      globalValidation: {
        unauthenticatedClientAction: 'RedirectToLoginPage'
        redirectToProvider: 'azureActiveDirectory'
      }
      platform: {
        enabled: true
      }
    }
    ingressAllowInsecure: false
    environmentResourceId: modContainerAppEnv.outputs.resourceId
    location: parLocation
    managedIdentities: {
      systemAssigned: true
    }
  }
  dependsOn: [modResourceGroup]
}

module modStorageRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: resourceGroup(parResourceGroupName)
  params:{
    principalId: modContainerApp.outputs.systemAssignedMIPrincipalId!
    roleName: 'Key Vault Secrets User'
    resourceId: modKeyVault.outputs.resourceId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'
    principalType: 'ServicePrincipal'
  }
}

module modFoundry 'br/public:avm/res/cognitive-services/account:0.14.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUiApp}-foundry'
    location: parLocation
    kind: 'AIServices'
    sku: 'S0'
    disableLocalAuth: true
    managedIdentities: {
      systemAssigned: true
    }
    allowProjectManagement: true
    customSubDomainName: replace('${varOpenWebUiApp}-foundry', '-', '')
    networkAcls:{
      defaultAction: 'Deny'
      virtualNetworkRules:[
        {
          id: modVirtualNetwork.outputs.subnetResourceIds[0]
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    deployments: [
        {
          name: 'gpt-4o'
          model: {
            format: 'OpenAI'
            name: 'gpt-4o'
            version: '2024-11-20'
          }
          sku: {
            name: 'Standard'
            capacity: 10
          }
        }
      ]
  }
  dependsOn: [modResourceGroup]
}

module modFoundryRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    principalId: modContainerApp.outputs.systemAssignedMIPrincipalId!
    roleName: 'Cognitive Services OpenAI User'
    resourceId: modFoundry.outputs.resourceId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

output outContainerAppFqdn string = modContainerApp.outputs.fqdn
output outContainerAppResourceId string = modContainerApp.outputs.resourceId
output outContainerAppEnvDefaultDomain string = modContainerAppEnv.outputs.defaultDomain
output outVirtualNetworkName string = modVirtualNetwork.outputs.name
output outVirtualNetworkResourceId string = modVirtualNetwork.outputs.resourceId
