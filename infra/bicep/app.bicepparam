using './app.bicep'

param parResourceGroupName = 'rg-open-webui-app'
param parVirtualNetworkAddressPrefix = '10.0.4.0/22'
param parAcaSubnetAddressPrefix = '10.0.4.0/23'
param parHubResourceGroupName = 'rg-lb-core'
param parHubVirtualNetworkName = 'vnet-lb-core'
param parCustomDomain = 'openwebui.rios.engineer'
param parCertificateName = 'cloudflare-origin-cert'
param parApimPrincipalId = 'd5d3423b-9834-4714-be94-c7530d92fd40'
param parApimGatewayUrl = 'https://apim-open-webui.azure-api.net'
param parApimAllowedIpAddresses = [
	'145.133.116.11'
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
			name: 'Standard'
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
]
