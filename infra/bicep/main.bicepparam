using 'main.bicep'
// Change values as required for your setup/demo/poc
param parApimName = 'apim-open-webui'
param parLocation = 'uksouth'
param parApimPublisherEmail = 'dan@riosengineer.com'
param parApimPublisherName = 'Dan Rios'
param parAppGatewayName = 'appgw-open-webui'
param parResourceGroupName = 'rg-lb-core'
param parVirtualNetworkName = 'vnet-lb-core'
param parVirtualNetworkAddressPrefix = '10.0.0.0/24'
param parApimSubnetAddressPrefix = '10.0.0.0/28'
param parAppGatewaySubnetAddressPrefix = '10.0.0.64/26'
param parPeSubnetAddressPrefix = '10.0.0.128/28'
param parApimSku = 'Developer' // Cheap for demo purposes
param parAppGatewaySku = 'Standard_v2'
param parContainerAppFqdn = 'open-webui-app-aca.jollyfield-adf491b7.uksouth.azurecontainerapps.io'
param parContainerAppStaticIp = '10.0.4.91'
param parSpokeResourceGroupName = 'rg-open-webui-app'
param parSpokeVirtualNetworkName = 'open-webui-app-vnet'
param parCustomDomain = 'openwebui.rios.engineer'
param parSpokeKeyVaultName = 'open-webui-app-kv'
param parTrustedRootCertificateSecretName = 'cloudflare-origin-ca'
param parSslCertificateSecretName = 'cloudflare-origin-cert'
// Foundry resource name in spoke - must match name created by app.bicep ('${parNamePrefix}-foundry')
param parFoundryName = 'open-webui-app-foundry'
// Entra ID App Registration ID from app.bicep output (outOpenWebUIAppId)
// Used for APIM token validation policy
param parOpenWebUIAppId = '7eb52126-ee47-4700-8561-77f433fdd2eb'
// Set to true on SECOND hub deployment after Foundry exists (Step 3)
// First deployment: false (creates hub networking + APIM without Foundry backend)
// Second deployment: true (configures APIM with Foundry endpoint + RBAC)
param parConfigureFoundry = false
param parTags = {
  Application: 'Open WebUI'
  Environment: 'Demo'
  Owner: 'Dan Rios'
}
