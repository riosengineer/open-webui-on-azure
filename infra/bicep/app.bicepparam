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
	'145.133.116.11' // APIM VIP - New Foundry doesn't support end to end private networking yet.
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
		name: 'llama-4-maverick-17b-128e-instruct-fp8'
		model: {
			format: 'meta'
			name: 'llama-4-maverick-17b-128e-instruct-fp8'
			version: '1'
		}
		sku: {
			name: 'GlobalStandard'
			capacity: 100
		}
	}
	{
		name: 'Mistral-Large-3'
		model: {
			format: 'mistral'
			name: 'Mistral-Large-3'
			version: '1'
		}
		sku: {
			name: 'GlobalStandard'
			capacity: 100
		}
	}
	{
		name: 'mistral-document-ai-2505'
		model: {
			format: 'mistral'
			name: 'mistral-document-ai-2505'
			version: '1'
		}
		sku: {
			name: 'GlobalStandard'
			capacity: 100
		}
	}
	{
		name: 'FLUX-1.1-pro'
		model: {
			format: 'flux'
			name: 'FLUX-1.1-pro'
			version: '1'
		}
		sku: {
			name: 'GlobalStandard'
			capacity: 100
		}
	}
]
