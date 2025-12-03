using 'main.bicep'

param parApimName = 'apim-open-webui'
param parLocation = 'uksouth'
param parApimPublisherEmail = 'dan@rios.engineer'
param parApimPublisherName = 'Dan Rios'
param parAppGatewayName = 'appgw-open-webui'
param parResourceGroupName = 'rg-lb-core'
param parVirtualNetworkName = 'vnet-lb-core'
param parVirtualNetworkAddressPrefix = '10.0.0.0/24'
param parApimSubnetAddressPrefix = '10.0.0.0/28'
param parAppGatewaySubnetAddressPrefix = '10.0.0.64/26'  // App Gateway requires at least /26

// Container App FQDN (populate after deploying app.bicep)
param parContainerAppFqdn = '' 
