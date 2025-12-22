// Monitoring Module
targetScope = 'resourceGroup'

// Parameters
param parLocation string
param parNamePrefix string

// Log Analytics Workspace
module modLogAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.13.0' = {
  params: {
    name: '${parNamePrefix}-law'
    location: parLocation
    dailyQuotaGb: 1
    dataRetention: 30
    skuName: 'PerGB2018'
    features: {
      disableLocalAuth: true
    }
  }
}

// Application Insights
module modAppInsights 'br/public:avm/res/insights/component:0.7.0' = {
  params: {
    name: '${parNamePrefix}-appi'
    workspaceResourceId: modLogAnalyticsWorkspace.outputs.resourceId
    disableLocalAuth: true
    applicationType: 'web'
    location: parLocation
    kind: 'web'
  }
}

// Outputs
output logAnalyticsWorkspaceResourceId string = modLogAnalyticsWorkspace.outputs.resourceId
output logAnalyticsWorkspaceName string = modLogAnalyticsWorkspace.outputs.name
output appInsightsResourceId string = modAppInsights.outputs.resourceId
output appInsightsName string = modAppInsights.outputs.name
output appInsightsConnectionString string = modAppInsights.outputs.connectionString
output appInsightsInstrumentationKey string = modAppInsights.outputs.instrumentationKey
