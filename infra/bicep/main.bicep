targetScope = 'subscription'

param parLocation string
param parResourceGroupName string
param parFrontDoorName string
param parFrontDoorSku string
param parApimName string
param parApimPublisherEmail string
param parApimPublisherName string
param parVirtualNetworkName string
param parVirtualNetworkAddressPrefix string
param parApimSubnetAddressPrefix string
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
    features:{
      disableLocalAuth: false
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
    disableLocalAuth: false
    applicationType: 'web'
    location: parLocation
    kind: 'web'
  }
  dependsOn: [
    modResourceGroup
  ]
}

module modFrontDoor 'br/public:avm/res/cdn/profile:0.16.1' = {
  scope: resourceGroup(parResourceGroupName)
  params: {
    name: parFrontDoorName
    sku: parFrontDoorSku
    location: 'global'
    afdEndpoints:[
      {
        name: 'afd-${varOpenWebUi}-endpoint'
        enabledState: 'Enabled'
        routes: [
          {
            name: 'afd-${varOpenWebUi}-route'
            originGroupName: 'apim-origin-group'
            enabledState: 'Enabled'
            httpsRedirect: 'Enabled'
            supportedProtocols:[
              'Http'
              'Https'
            ]
            forwardingProtocol: 'HttpsOnly'
            originPath: '/'
            patternsToMatch: [
              '/*'
            ]
          }
        ]
      }
    ]
    originGroups: [
      {
        name: 'apim-origin-group'
        loadBalancingSettings: {
          additionalLatencyInMilliseconds: 50
          sampleSize: 4
          successfulSamplesRequired: 3
        }
        origins: [
          {
            name: 'afd-apim-origin'
            hostName: 'https://${parApimName}.azure-api.net'
          }
        ]
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
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
