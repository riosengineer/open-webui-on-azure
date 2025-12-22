// ========== Shared Type Definitions ==========
// Central type definitions for use across Bicep files
// Import using: import { TypeName } from './types.bicep'

@export()
@description('Standard resource tags for demo environment')
type TagsType = {
  @description('Application or workload name')
  Application: string
  @description('Deployment environment')
  Environment: 'Demo' | 'Dev' | 'Prod'
  @description('Resource owner or contact')
  Owner: string
  @description('Additional custom tags')
  *: string
}

@export()
@description('Configuration for Azure AI Foundry model deployments')
type FoundryDeploymentType = {
  @description('Deployment name (e.g., gpt-4o)')
  name: string
  @description('Model configuration')
  model: {
    @description('Model format/provider (e.g., OpenAI, xAI)')
    format: string
    @description('Model name')
    name: string
    @description('Model version')
    version: string
  }
  @description('SKU configuration for capacity')
  sku: {
    @description('SKU name (e.g., GlobalStandard)')
    name: string
    @description('Capacity units')
    capacity: int
  }
}

@export()
@description('Configuration for Public IP address resources')
type PublicIpConfigType = {
  @description('Unique key for referencing this PIP in outputs')
  key: string
  @description('Azure resource name for the public IP')
  name: string
  @description('Optional DNS domain name label')
  dnsLabel: string?
}

@export()
@description('Configuration for RBAC role assignments')
type RbacAssignmentType = {
  @description('Unique key for referencing this assignment')
  key: string
  @description('Principal ID to assign the role to')
  principalId: string
  @description('Type of principal')
  principalType: 'ServicePrincipal' | 'User' | 'Group'
  @description('Role definition ID (GUID)')
  roleDefinitionId: string
  @description('Optional role name for clarity')
  roleName: string?
}
