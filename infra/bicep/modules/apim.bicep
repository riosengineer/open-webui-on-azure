// APIM Module
targetScope = 'resourceGroup'

// Parameters
param parApimName string
param parLocation string
param parSku string
param parPublisherEmail string
param parPublisherName string
param parFoundryEndpoint string
param parOpenWebUIAppId string
param parAppInsightsName string
param parAppInsightsResourceId string
param parAppInsightsInstrumentationKey string
param parLogAnalyticsWorkspaceResourceId string
param parApimSubnetResourceId string
param parApimPublicIpResourceId string
param parRedisCacheConnectionString string = ''

// Load policy files
var varOpenAIPolicyXml = loadTextContent('../policies/openai-api.xml')

// API Management Service
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
    backends: [
      {
        name: 'foundry-backend'
        protocol: 'http'
        url: '${parFoundryEndpoint}openai/v1'
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
        policies: [
          {
            format: 'rawxml'
            value: varOpenAIPolicyXml
          }
        ]
      }
    ]
    products: [
      {
        name: 'platform-services'
        displayName: 'Platform Services'
        description: 'AI and ML services managed by Platform Engineering team'
        subscriptionRequired: true
        approvalRequired: false
        state: 'published'
        apis: [
          'openai'
        ]
      }
    ]
    loggers: [
      {
        name: parAppInsightsName
        type: 'applicationInsights'
        description: 'Logger for Application Insights'
        targetResourceId: parAppInsightsResourceId
        credentials: {
          instrumentationKey: parAppInsightsInstrumentationKey
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
    namedValues: !empty(parOpenWebUIAppId) ? [
      {
        name: 'tenant-id'
        displayName: 'tenant-id'
        value: tenant().tenantId
        secret: false
      }
      {
        name: 'openwebui-app-id'
        displayName: 'openwebui-app-id'
        value: parOpenWebUIAppId
        secret: false
      }
    ] : []
    caches: !empty(parRedisCacheConnectionString) ? [
      {
        name: 'default'
        description: 'External Redis cache for AI Gateway semantic caching'
        connectionString: parRedisCacheConnectionString
        useFromLocation: 'uksouth'
      }
    ] : []
  }
}

// RBAC for APIM to publish metrics to App Insights
module modApimMetricsPublisherRbac 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  params: {
    principalId: modApim.outputs.systemAssignedMIPrincipalId!
    principalType: 'ServicePrincipal'
    roleDefinitionId: '3913510d-42f4-4e42-8a64-420c390055eb' // Monitoring Metrics Publisher
    resourceId: parAppInsightsResourceId
  }
}

// Configure LLM logging for the openai API diagnostic
resource resOpenAIDiagnosticLLMLogging 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = {
  name: '${parApimName}/openai/applicationinsights'
  dependsOn: [
    modApim
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
        maxSizeInBytes: 32768
        messages: 'all'
      }
      responses: {
        maxSizeInBytes: 262144
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
