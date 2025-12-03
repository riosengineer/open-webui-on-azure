targetScope = 'subscription'

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
@validate(
  x => !contains(x, 'https://'), 'The Container App param FQDN must not contain the "https://" prefix.'
)
param parContainerAppFqdn string = ''

var varOpenWebUi = 'open-webui'
var varNsgRules = loadJsonContent('nsg-rules.json')

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

module modAppGateway 'br/public:avm/res/network/application-gateway:0.6.0' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: parAppGatewayName
    location: parLocation
    sku: 'Standard_v2'
    capacity: 1
    zones: []
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
        }
      }
      {
        name: 'containerapp-backend-settings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
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
          hostName: 'app.${parAppGatewayName}.example.com'
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
        }
      }
    ]
  }
  dependsOn: [
    modResourceGroup
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
    managedIdentities: {
      systemAssigned: true
    }
  }
  dependsOn: [
    modResourceGroup
  ]
}
