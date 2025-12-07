targetScope = 'subscription'
// Parameters
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
param parFoundryEndpoint string
@validate(
  x => !contains(x, 'https://'), 'The Container App param FQDN must not contain the "https://" prefix.'
)
param parContainerAppFqdn string
param parContainerAppStaticIp string
param parSpokeResourceGroupName string
param parSpokeVirtualNetworkName string
param parCustomDomain string
param parSpokeKeyVaultName string

// Variables
var varOpenWebUi = 'open-webui'
var varNsgRules = loadJsonContent('nsg-rules.json')
var varContainerAppEnvDefaultDomain = !empty(parContainerAppFqdn) ? join(skip(split(parContainerAppFqdn, '.'), 1), '.') : '' // if FQDN is myapp.uksouth.azurecontainerapps.io, this trims string to uksouth.azurecontainerapps.io
var varContainerAppName = !empty(parContainerAppFqdn) ? split(parContainerAppFqdn, '.')[0] : '' // if FQDN is myapp.uksouth.azurecontainerapps.io, trims string to 'myapp'
var varCloudflareOriginCaBase64 = loadTextContent('cloudflare-origin-ca.cer')

module modResourceGroup 'br/public:avm/res/resources/resource-group:0.4.2' = {
  params: {
    name: parResourceGroupName
    location: parLocation
  }
}

module modVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: parVirtualNetworkName
    addressPrefixes: [
      parVirtualNetworkAddressPrefix
    ]
    subnets: [
      {
        name: 'apim-subnet'
        addressPrefix: parApimSubnetAddressPrefix
        networkSecurityGroupResourceId: nsgApim.outputs.resourceId
      }
      {
        name: 'appgw-subnet'
        addressPrefix: parAppGatewaySubnetAddressPrefix
      }
    ]
    peerings: !empty(parSpokeVirtualNetworkName) ? [
      {
        remoteVirtualNetworkResourceId: resourceId(subscription().subscriptionId, parSpokeResourceGroupName, 'Microsoft.Network/virtualNetworks', parSpokeVirtualNetworkName)
        allowForwardedTraffic: true
        allowGatewayTransit: false
        allowVirtualNetworkAccess: true
        useRemoteGateways: false
      }
    ] : []
  }
  dependsOn: [
    modResourceGroup
  ]
}

module modPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = if (!empty(varContainerAppEnvDefaultDomain)) {
  scope: resourceGroup(parResourceGroupName)
  name: 'privateDnsZone'
  params: {
    name: varContainerAppEnvDefaultDomain
    a: [
      {
        name: varContainerAppName
        ttl: 3600
        aRecords: [
          { ipv4Address: parContainerAppStaticIp }
        ]
      }
    ]
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: modVirtualNetwork.outputs.resourceId
        registrationEnabled: false
      }
    ]
  }
  dependsOn: [
    modResourceGroup
  ]
}

module nsgApim 'br/public:avm/res/network/network-security-group:0.5.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: 'apim-nsg'
    location: parLocation
    // See: https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet?tabs=stv2#configure-nsg-rules
    securityRules: varNsgRules
  }
  dependsOn: [
    modResourceGroup
  ]
}
  
module modLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.13.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUi}-law'
    location: parLocation
    dailyQuotaGb:1
    dataRetention: 30
    skuName: 'PerGB2018'
    features:{
      disableLocalAuth: true
    }
  }
  dependsOn: [
    modResourceGroup
  ]
}

module modAppInsights 'br/public:avm/res/insights/component:0.7.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${varOpenWebUi}-appi'
    workspaceResourceId: modLogAnalyticsWorkspace.outputs.resourceId
    disableLocalAuth: true
    applicationType: 'web'
    location: parLocation
    kind: 'web'
  }
  dependsOn: [
    modResourceGroup
  ]
}

module modAppGatewayPublicIp 'br/public:avm/res/network/public-ip-address:0.8.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parAppGatewayName}-pip'
    location: parLocation
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    zones: []
  }
  dependsOn: [
    modResourceGroup
  ]
}

module modAppGatewayIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = if (!empty(parCustomDomain)) {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: '${parAppGatewayName}-identity'
    location: parLocation
  }
  dependsOn: [modResourceGroup]
}

module modHubKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = if (!empty(parCustomDomain)) {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: 'kv-${parAppGatewayName}'
    location: parLocation
    sku: 'standard'
    enableRbacAuthorization: true
    enablePurgeProtection: false
    softDeleteRetentionInDays: 7
    secrets: [
      {
        name: 'cloudflare-origin-ca'
        value: varCloudflareOriginCaBase64
      }
    ]
  }
  dependsOn: [modResourceGroup]
}

module modAppGatewayKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (!empty(parCustomDomain)) {
  scope: resourceGroup(parResourceGroupName)
  params: {
    principalId: modAppGatewayIdentity.outputs.principalId
    resourceId: modHubKeyVault.outputs.resourceId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
  }
}

module modAppGatewaySpokeKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (!empty(parCustomDomain) && !empty(parSpokeKeyVaultName)) {
  scope: resourceGroup(parSpokeResourceGroupName)
  params: {
    principalId: modAppGatewayIdentity.outputs.principalId
    resourceId: resourceId(subscription().subscriptionId, parSpokeResourceGroupName, 'Microsoft.KeyVault/vaults', parSpokeKeyVaultName)
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
  }
}

module modAppGateway 'br/public:avm/res/network/application-gateway:0.6.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: parAppGatewayName
    location: parLocation
    sku: 'Standard_v2'
    capacity: 1
    zones: []
    managedIdentities: !empty(parCustomDomain) ? {
      userAssignedResourceIds: [
        modAppGatewayIdentity.outputs.resourceId
      ]
    } : null
    trustedRootCertificates: !empty(parCustomDomain) ? [
      {
        name: 'cloudflare-origin-ca'
        properties: {
          keyVaultSecretId: '${modHubKeyVault.outputs.uri}secrets/cloudflare-origin-ca'
        }
      }
    ] : []
    sslCertificates: (!empty(parCustomDomain) && !empty(parSpokeKeyVaultName)) ? [
      {
        name: 'cloudflare-origin-cert'
        properties: {
          keyVaultSecretId: 'https://${parSpokeKeyVaultName}${environment().suffixes.keyvaultDns}/secrets/cloudflare-origin-cert'
        }
      }
    ] : []
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: {
          subnet: {
            id: modVirtualNetwork.outputs.subnetResourceIds[1] // appgw-subnet
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: {
          publicIPAddress: {
            id: modAppGatewayPublicIp.outputs.resourceId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port-443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'apim-backend-pool'
        properties: {
          backendAddresses: [
            {
              fqdn: '${parApimName}.azure-api.net'
            }
          ]
        }
      }
      {
        name: 'containerapp-backend-pool'
        properties: {
          backendAddresses: !empty(parContainerAppFqdn) ? [
            {
              fqdn: parContainerAppFqdn
            }
          ] : []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'apim-backend-settings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/probes', parAppGatewayName, 'apim-health-probe')
          }
        }
      }
      {
        name: 'containerapp-backend-settings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: !empty(parCustomDomain) ? false : true
          hostName: !empty(parCustomDomain) ? parCustomDomain : null
          requestTimeout: 30
          trustedRootCertificates: !empty(parCustomDomain) ? [
            {
              id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/trustedRootCertificates', parAppGatewayName, 'cloudflare-origin-ca')
            }
          ] : null
          probe: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/probes', parAppGatewayName, 'containerapp-health-probe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'apim-health-probe'
        properties: {
          protocol: 'Https'
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: ['200-399']
          }
        }
      }
      {
        name: 'containerapp-health-probe'
        properties: {
          protocol: 'Https'
          path: '/health'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: !empty(parCustomDomain) ? false : true
          host: !empty(parCustomDomain) ? parCustomDomain : null
          minServers: 0
          match: {
            statusCodes: ['200-399', '401']
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'apim-http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/frontendIPConfigurations', parAppGatewayName, 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/frontendPorts', parAppGatewayName, 'port-80')
          }
          protocol: 'Http'
          hostName: 'api.${parAppGatewayName}.example.com'
        }
      }
      {
        name: 'containerapp-http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/frontendIPConfigurations', parAppGatewayName, 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/frontendPorts', parAppGatewayName, 'port-80')
          }
          protocol: 'Http'
          hostName: parCustomDomain
        }
      }
      {
        name: 'containerapp-https-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/frontendIPConfigurations', parAppGatewayName, 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/frontendPorts', parAppGatewayName, 'port-443')
          }
          protocol: 'Https'
          hostName: parCustomDomain
          sslCertificate: (!empty(parCustomDomain) && !empty(parSpokeKeyVaultName)) ? {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/sslCertificates', parAppGatewayName, 'cloudflare-origin-cert')
          } : null
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'apim-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/httpListeners', parAppGatewayName, 'apim-http-listener')
          }
          backendAddressPool: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendAddressPools', parAppGatewayName, 'apim-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendHttpSettingsCollection', parAppGatewayName, 'apim-backend-settings')
          }
        }
      }
      {
        name: 'containerapp-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 200
          httpListener: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/httpListeners', parAppGatewayName, 'containerapp-http-listener')
          }
          backendAddressPool: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendAddressPools', parAppGatewayName, 'containerapp-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendHttpSettingsCollection', parAppGatewayName, 'containerapp-backend-settings')
          }
          rewriteRuleSet: !empty(parCustomDomain) ? {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/rewriteRuleSets', parAppGatewayName, 'containerapp-rewrite-rules')
          } : null
        }
      }
      {
        name: 'containerapp-https-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 201
          httpListener: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/httpListeners', parAppGatewayName, 'containerapp-https-listener')
          }
          backendAddressPool: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendAddressPools', parAppGatewayName, 'containerapp-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendHttpSettingsCollection', parAppGatewayName, 'containerapp-backend-settings')
          }
          rewriteRuleSet: !empty(parCustomDomain) ? {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/rewriteRuleSets', parAppGatewayName, 'containerapp-rewrite-rules')
          } : null
        }
      }
    ]
    rewriteRuleSets: !empty(parCustomDomain) ? [
      {
        name: 'containerapp-rewrite-rules'
        properties: {
          rewriteRules: [
            {
              name: 'set-forwarded-headers'
              ruleSequence: 100
              conditions: []
              actionSet: {
                requestHeaderConfigurations: [
                  {
                    headerName: 'X-Forwarded-Host'
                    headerValue: parCustomDomain
                  }
                  {
                    headerName: 'X-Forwarded-Proto'
                    headerValue: 'https'
                  }
                ]
                responseHeaderConfigurations: []
              }
            }
          ]
        }
      }
    ] : []
  }
  dependsOn: [
    modResourceGroup
    modAppGatewayKeyVaultRbac
  ]
}

module modApim 'br/public:avm/res/api-management/service:0.12.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: parApimName
    publisherEmail: parApimPublisherEmail
    publisherName: parApimPublisherName
    location: parLocation
    sku: 'Developer'
    virtualNetworkType: 'Internal'
    backends: [
      {
        name: 'foundry-backend'
        protocol: 'http'
        url: parFoundryEndpoint
        tls: {
          validateCertificateChain: true
          validateCertificateName: true
        }
      }
    ]
    apis: [
      {
        name: 'openai'
        displayName: 'Azure OpenAI v1 API'
        path: 'openai/v1'
        apiType: 'http'
        protocols: [
          'https'
        ]
        subscriptionRequired: true
        subscriptionKeyParameterNames: {
          header: 'api-key'
        }
        serviceUrl: parFoundryEndpoint
        diagnostics: []
        policies: [
          {
            format: 'rawxml'
            value: loadTextContent('policies/openai-api.xml')
          }
        ]
        // az apim api import --resource-group rg-lb-core --service-name apim-open-webui --api-id openai --path openai/v1 --specification-format OpenApi --specification-path infra/bicep/openapi/openai.openapi.json
      }
      {
        name: 'grok'
        displayName: 'Grok API'
        path: 'grok'
        apiType: 'http'
        protocols: [
          'https'
        ]
        subscriptionRequired: true
        subscriptionKeyParameterNames: {
          header: 'api-key'
        }
        serviceUrl: ''
        diagnostics: []
        policies: [
          {
            format: 'rawxml'
            value: loadTextContent('policies/openai-api.xml')
          }
        ]
      }
    ]
    loggers: [
      {
        name: modAppInsights.outputs.name
        type: 'applicationInsights'
        description: 'Logger for Application Insights'
        targetResourceId: modAppInsights.outputs.resourceId
        credentials: {
          connectionString: modAppInsights.outputs.connectionString
          identity: 'SystemAssigned'
        }
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
  }
  dependsOn: [modResourceGroup]
}

module modApimMetricsPublisherRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    principalId: modApim.outputs.systemAssignedMIPrincipalId!
    principalType: 'ServicePrincipal'
    roleDefinitionId: '749f88d5-cbae-40b8-bcfc-e573ddc772fa' // Monitoring Metrics Publisher
    resourceId: modAppInsights.outputs.resourceId
  }
  dependsOn: [modResourceGroup]
}

output outApimName string = modApim.outputs.name
output outApimResourceId string = modApim.outputs.resourceId
output outApimSystemAssignedPrincipalId string = modApim.outputs.systemAssignedMIPrincipalId!
output outAppInsightsConnectionString string = modAppInsights.outputs.connectionString
output outAppInsightsResourceId string = modAppInsights.outputs.resourceId
output outAppGatewayPublicIp string = modAppGatewayPublicIp.outputs.resourceId
output outVirtualNetworkResourceId string = modVirtualNetwork.outputs.resourceId
output outVirtualNetworkName string = modVirtualNetwork.outputs.name
output outContainerAppFqdn string = parContainerAppFqdn
