// APIM Module
targetScope = 'resourceGroup'

// Parameters
param parApimName string
param parLocation string
param parSku string
param parPublisherEmail string
param parPublisherName string
param parFoundryEndpoint string = '' // Optional - empty on first deploy before Foundry exists
param parOpenWebUIAppId string
param parAppInsightsName string
param parAppInsightsResourceId string
param parAppInsightsConnectionString string
param parLogAnalyticsWorkspaceResourceId string
param parApimSubnetResourceId string
param parApimPublicIpResourceId string

// Variables
var varRoleDefinitions = {
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
}

// Transform Foundry endpoint from cognitiveservices.azure.com to services.ai.azure.com
// The Foundry API returns cognitiveservices endpoint but AI Services should use the unified endpoint
var varFoundryAiEndpoint = !empty(parFoundryEndpoint) 
  ? replace(parFoundryEndpoint, '.cognitiveservices.azure.com', '.services.ai.azure.com')
  : ''

// Conditional backend - only create when Foundry endpoint is provided
var varFoundryBackends = !empty(parFoundryEndpoint) ? [
  {
    name: 'foundry-backend'
    protocol: 'http'
    url: '${varFoundryAiEndpoint}openai/v1'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
] : []

// Load policy files
var varOpenAIPolicyXml = loadTextContent('../policies/openai-api.xml')

// API Management Service - Base infrastructure
module modApim 'br/public:avm/res/api-management/service:0.12.0' = {
  params: {
    name: parApimName
    publisherEmail: parPublisherEmail
    publisherName: parPublisherName
    location: parLocation
    sku: parSku
    virtualNetworkType: 'Internal'
    subnetResourceId: parApimSubnetResourceId
    publicIpAddressResourceId: parApimPublicIpResourceId
    backends: varFoundryBackends
    loggers: [
      {
        name: parAppInsightsName
        type: 'applicationInsights'
        description: 'Logger for Application Insights'
        targetResourceId: parAppInsightsResourceId
        credentials: {
          connectionString: parAppInsightsConnectionString
          identityClientId: 'systemAssigned'
        }
      }
    ]
    managedIdentities: {
      systemAssigned: true
    }
    diagnosticSettings: [
      {
        name: 'apim-diagnostics'
        workspaceResourceId: parLogAnalyticsWorkspaceResourceId
        logAnalyticsDestinationType: 'Dedicated'
        logCategoriesAndGroups: [
            {
            category: 'GatewayLogs'
            enabled: true
            }
            {
            category: 'GatewayLlmLogs'
            enabled: true
            }
        ]
      }
    ]
  }
}

// Named Values - Deploy first so APIs can reference them in policies
module modApimNamedValueTenantId 'br/public:avm/res/api-management/service/named-value:0.1.1' = {
  params: {
    apiManagementServiceName: parApimName
    name: 'tenant-id'
    displayName: 'tenant-id'
    secret: false
    value: tenant().tenantId
  }
  dependsOn: [
    modApim
  ]
}

module modApimNamedValueAppId 'br/public:avm/res/api-management/service/named-value:0.1.1' = if (!empty(parOpenWebUIAppId)) {
  params: {
    apiManagementServiceName: parApimName
    name: 'openwebui-app-id'
    displayName: 'openwebui-app-id'
    secret: false
    value: parOpenWebUIAppId
  }
  dependsOn: [
    modApim
  ]
}

// Product - Deploy before API so API can reference it
module modApimProduct 'br/public:avm/res/api-management/service/product:0.1.1' = {
  params: {
    apiManagementServiceName: parApimName
    name: 'platform-services'
    displayName: 'Platform Services'
    description: 'AI and ML services managed by Platform Engineering team'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
  dependsOn: [
    modApim
  ]
}

// API - Deploy after named values and product exist
module modApimApi 'br/public:avm/res/api-management/service/api:0.1.1' = {
  params: {
    apiManagementServiceName: parApimName
    name: 'openai'
    displayName: 'Azure OpenAI v1 API'
    path: 'openai/v1'
    type: 'http'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
    }
    policies: [
      {
        format: 'rawxml'
        value: varOpenAIPolicyXml
      }
    ]
  }
  dependsOn: [
    modApimNamedValueTenantId
    modApimProduct
  ]
}

// API-Product Association - Deploy after both API and Product exist
module modApimProductApi 'br/public:avm/res/api-management/service/product/api:0.1.1' = {
  params: {
    apiManagementServiceName: parApimName
    productName: 'platform-services'
    name: 'openai'
  }
  dependsOn: [
    modApimApi
    modApimProduct
  ]
}

// RBAC for APIM to publish metrics to App Insights
module modApimMetricsPublisherRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  params: {
    principalId: modApim.outputs.systemAssignedMIPrincipalId!
    principalType: 'ServicePrincipal'
    roleDefinitionId: varRoleDefinitions.monitoringMetricsPublisher
    resourceId: parAppInsightsResourceId
  }
}

// Configure LLM logging for the openai API diagnostic
resource resOpenAIDiagnosticLLMLogging 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = {
  name: '${parApimName}/openai/applicationinsights'
  dependsOn: [
    modApimApi
  ]
  properties: {
    alwaysLog: 'allErrors'
    logClientIp: true
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    loggerId: resourceId('Microsoft.ApiManagement/service/loggers', parApimName, parAppInsightsName)
    metrics: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    largeLanguageModel: {
      logs: 'enabled'
      requests: {
        maxSizeInBytes: 1024
        messages: 'all'
      }
      responses: {
        maxSizeInBytes: 1024
        messages: 'all'
      }
    }
  }
}

// Outputs
output resourceId string = modApim.outputs.resourceId
output name string = modApim.outputs.name
output gatewayUrl string = 'https://${modApim.outputs.name}.azure-api.net'
output systemAssignedMIPrincipalId string = modApim.outputs.systemAssignedMIPrincipalId!
