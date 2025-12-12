// Application Gateway Module (wrapper around AVM module)
targetScope = 'resourceGroup'

// Parameters
param parAppGatewayName string
param parLocation string
param parSku string
param parContainerAppFqdn string
param parCustomDomain string
param parSpokeKeyVaultName string
param parTrustedRootCertificateSecretName string
param parSslCertificateSecretName string
param parAppGatewaySubnetId string
param parPublicIpResourceId string
param parUserAssignedIdentityResourceId string
param parHubKeyVaultUri string
param parResourceGroupName string

// Application Gateway using AVM module
module modAppGateway 'br/public:avm/res/network/application-gateway:0.6.0' = {
  params: {
    name: parAppGatewayName
    location: parLocation
    sku: parSku
    capacity: 1
    zones: []
    managedIdentities: !empty(parCustomDomain) ? {
      userAssignedResourceIds: [
        parUserAssignedIdentityResourceId
      ]
    } : null
    trustedRootCertificates: !empty(parCustomDomain) ? [
      {
        name: parTrustedRootCertificateSecretName
        properties: {
          keyVaultSecretId: '${parHubKeyVaultUri}secrets/${parTrustedRootCertificateSecretName}'
        }
      }
    ] : []
    sslCertificates: (!empty(parCustomDomain) && !empty(parSpokeKeyVaultName)) ? [
      {
        name: parSslCertificateSecretName
        properties: {
          keyVaultSecretId: 'https://${parSpokeKeyVaultName}${environment().suffixes.keyvaultDns}/secrets/${parSslCertificateSecretName}'
        }
      }
    ] : []
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: {
          subnet: {
            id: parAppGatewaySubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: {
          publicIPAddress: {
            id: parPublicIpResourceId
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
              id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/trustedRootCertificates', parAppGatewayName, parTrustedRootCertificateSecretName)
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
        name: 'containerapp-health-probe'
        properties: {
          protocol: 'Https'
          path: '/'
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
    ]
    httpListeners: [
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
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/sslCertificates', parAppGatewayName, parSslCertificateSecretName)
          } : null
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'containerapp-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/httpListeners', parAppGatewayName, 'containerapp-http-listener')
          }
          backendAddressPool: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendAddressPools', parAppGatewayName, 'containerapp-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendHttpSettingsCollection', parAppGatewayName, 'containerapp-backend-settings')
          }
        }
      }
      {
        name: 'containerapp-https-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 101
          httpListener: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/httpListeners', parAppGatewayName, 'containerapp-https-listener')
          }
          backendAddressPool: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendAddressPools', parAppGatewayName, 'containerapp-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId(subscription().subscriptionId, parResourceGroupName, 'Microsoft.Network/applicationGateways/backendHttpSettingsCollection', parAppGatewayName, 'containerapp-backend-settings')
          }
        }
      }
    ]
  }
}

// Outputs
output resourceId string = modAppGateway.outputs.resourceId
output name string = modAppGateway.outputs.name
