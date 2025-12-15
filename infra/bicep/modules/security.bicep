// Security Module - Key Vaults and Identities
targetScope = 'resourceGroup'

// Parameters
param parLocation string
param parAppGatewayName string
param parTrustedRootCertificateSecretName string
param parTrustedRootCertificateBase64 string
param parCustomDomain string

// Variables
var varRoleDefinitions = {
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
}

// Managed Identity for Application Gateway
module modAppGatewayIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.1' = if (!empty(parCustomDomain)) {
  params: {
    name: '${parAppGatewayName}-identity'
    location: parLocation
  }
}

// Key Vault for Hub certificates
module modHubKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = if (!empty(parCustomDomain)) {
  params: {
    name: 'kv-${parAppGatewayName}'
    location: parLocation
    sku: 'standard'
    enableRbacAuthorization: true
    enablePurgeProtection: false
    softDeleteRetentionInDays: 7
    secrets: [
      {
        name: parTrustedRootCertificateSecretName
        value: parTrustedRootCertificateBase64
      }
    ]
  }
}

// RBAC for App Gateway to access Hub Key Vault
resource resHubKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = if (!empty(parCustomDomain)) {
  name: 'kv-${parAppGatewayName}'
}

module modAppGatewayKeyVaultRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = if (!empty(parCustomDomain)) {
  params: {
    principalId: modAppGatewayIdentity.outputs.principalId
    resourceId: resHubKeyVault.id
    roleDefinitionId: varRoleDefinitions.keyVaultSecretsUser
  }
}

// Outputs
output userAssignedIdentityResourceId string = !empty(parCustomDomain) ? modAppGatewayIdentity!.outputs.resourceId : ''
output userAssignedIdentityPrincipalId string = !empty(parCustomDomain) ? modAppGatewayIdentity!.outputs.principalId : ''
output hubKeyVaultResourceId string = !empty(parCustomDomain) ? modHubKeyVault!.outputs.resourceId : ''
output hubKeyVaultUri string = !empty(parCustomDomain) ? modHubKeyVault!.outputs.uri : ''
output hubKeyVaultName string = !empty(parCustomDomain) ? modHubKeyVault!.outputs.name : ''
