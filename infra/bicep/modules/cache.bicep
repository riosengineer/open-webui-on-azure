

// Redis Cache Module for APIM AI Gateway Semantic Caching
targetScope = 'resourceGroup'

// Parameters
param parCacheName string
param parLocation string
param parSkuName string
param parSubnetResourceId string
param parHubVnetResourceId string
param parSpokeVnetResourceId string
param parTags object = {}

module modPrivateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = {
  params: {
    name: 'privatelink.redis.cache.windows.net'
    location: 'global'
    tags: parTags
    virtualNetworkLinks: [
      {
        name: 'hub-vnet-link'
        virtualNetworkResourceId: parHubVnetResourceId
        registrationEnabled: false
      }
      {
        name: 'spoke-vnet-link'
        virtualNetworkResourceId: parSpokeVnetResourceId
        registrationEnabled: false
      }
    ]
  }
}
// Doesn't support Entra auth yet, really..? https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-cache-external
// Redis Cache for APIM
module modRedisCache 'br/public:avm/res/cache/redis:0.16.4' = {
  params: {
    name: parCacheName
    location: parLocation
    tags: parTags
    skuName: parSkuName
    capacity: 1
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
      'maxmemory-reserved': '50'
    }
    redisVersion: '6'
    privateEndpoints: [
      {
        subnetResourceId: parSubnetResourceId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: modPrivateDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
  }
}

// Outputs
output resourceId string = modRedisCache.outputs.resourceId
output name string = modRedisCache.outputs.name
output hostName string = modRedisCache.outputs.hostName
output sslPort int = modRedisCache.outputs.sslPort
