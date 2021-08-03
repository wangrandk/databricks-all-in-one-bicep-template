targetScope = 'subscription'

@minLength(2)
@maxLength(4)
@description('2-4 chars to prefix the Azure resources, NOTE: no number or symbols')
param prefix string = 'ss'

@description('Client PC username, NOTE: do not use admin')
param adminUsername string

@description('Client PC password, with atleast 8 char length containing uppercase, digits and special characters ')
@minLength(8)
@secure()
param adminPassword string

var uniqueSubString = '${uniqueString(guid(subscription().subscriptionId))}'
var uString = '${prefix}${uniqueSubString}'

// @description('Default storage suffix core - core.windows.net')
// var storageSuffix = environment().suffixes.storage

var storageAccountName = '${substring(uString, 0, 10)}stg01'
var keyVaultName = '${substring(uString, 0, 6)}kv01'
var resourceGroupName = '${substring(uString, 0, 6)}-rg'
var adbWorkspaceName = '${substring(uString, 0, 6)}AdbWksp'
var nsgName = '${substring(uString, 0, 6)}nsg'
var firewallName = '${substring(uString, 0, 6)}HubFW'
var firewallPublicIpName = '${substring(uString, 0, 6)}FWPIp'
var fwRoutingTable = '${substring(uString, 0, 6)}AdbRoutingTbl'
var clientPcName = '${substring(uString, 0, 6)}ClientPc'
var eHNameSpace = '${substring(uString, 0, 6)}eh'
var adbAkvLinkName = '${substring(uString, 0, 6)}SecretScope'
// creating the event hub same as namespace
var eventHubName = eHNameSpace
var managedIdentityName = '${substring(uString, 0, 6)}Identity'

@description('Default location of the resources')
param location string = 'southeastasia'
@description('')
param hubVnetName string = 'hubVnetName'
@description('')
param spokeVnetName string = 'spokevnet'
@description('')
param SpokeVnetCidr string = '10.179.0.0/16'
@description('')
param HubVnetCidr string = '10.0.0.0/16'
@description('')
param PrivateSubnetCidr string = '10.179.0.0/18'
@description('')
param PublicSubnetCidr string = '10.179.64.0/18'
@description('')
param FirewallSubnetCidr string = '10.0.1.0/26'
@description('')
param PrivateLinkSubnetCidr string = '10.179.128.0/26'

@description('Southeastasia ADB webapp address')
param webappDestinationAddresses array = [
  '52.187.145.107/32'
  '52.187.0.85/32'
]
@description('Southeastasia ADB log blob')
param logBlobstorageDomains array = [
  'dblogprodseasia.blob.core.windows.net'
]
@description('Southeastasia ADB extended ip')
param extendedInfraIp array = [
  '20.195.104.64/28'
]
@description('Southeastasia SCC relay Domain')
param sccReplayDomain array = [
  'tunnel.southeastasia.azuredatabricks.net'
]
@description('Southeastasia SDB metastore')
param metastoreDomains array = [
  'consolidated-southeastasia-prod-metastore.mysql.database.azure.com'
]
@description('Southeastasia EventHub endpoint')
param eventHubEndpointDomain array = [
  'prod-southeastasia-observabilityeventhubs.servicebus.windows.net'
]
@description('Southeastasia Artifacts Blob')
param artifactBlobStoragePrimaryDomains array = [
  'dbartifactsprodseap.blob.core.windows.net'
  'arprodseapa1.blob.core.windows.net'
  'arprodseapa2.blob.core.windows.net'
  'arprodseapa3.blob.core.windows.net'
  'dbartifactsprodeap.blob.core.windows.net'
]

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
}

module myIdentity './other/managedIdentity.template.bicep' = {
  scope: rg
  name: 'myIdentity'
  params: {
    managedIdentityName: managedIdentityName
    location: location
  }
}

module routeTable './network/routetable.template.bicep' = {
  scope: rg
  name: 'RouteTable'
  params: {
    routeTableName: fwRoutingTable
  }
}

module nsg './network/securitygroup.template.bicep' = {
  scope: rg
  name: 'NetworkSecurityGroup'
  params: {
    securityGroupName: nsgName
  }
}

module vnets './network/vnet.template.bicep' = {
  scope: rg
  name: 'HubandSpokeVNET'
  params: {
    hubVnetName: hubVnetName
    spokeVnetName: spokeVnetName
    routeTableName: routeTable.outputs.routeTblName
    securityGroupName: nsg.outputs.nsgName
    firewallSubnetCidr: FirewallSubnetCidr
    hubVnetCidr: HubVnetCidr
    spokeVnetCidr: SpokeVnetCidr
    publicSubnetCidr: PublicSubnetCidr
    privateSubnetCidr: PrivateSubnetCidr
    privatelinkSubnetCidr: PrivateLinkSubnetCidr
  }
}

module adb './databricks/workspace.template.bicep' = {
  scope: rg
  name: 'DatabricksWorkspace'
  params: {
    vnetName: spokeVnetName
    adbWorkspaceSkuTier: 'premium'
    adbWorkspaceName: adbWorkspaceName
  }
  dependsOn:[
    vnets
  ]
}

module hubFirewall './network/firewall.template.bicep' = {
  scope: rg
  name: 'HubFirewall'
  params: {
    firewallName: firewallName
    publicIpAddressName: firewallPublicIpName
    vnetName: hubVnetName
    webappDestinationAddresses: webappDestinationAddresses
    logBlobstorageDomains: logBlobstorageDomains
    infrastructureDestinationAddresses: extendedInfraIp
    sccRelayDomains: sccReplayDomain
    metastoreDomains: metastoreDomains
    eventHubEndpointDomains: eventHubEndpointDomain
    artifactBlobStoragePrimaryDomains: artifactBlobStoragePrimaryDomains
    dbfsBlobStrageDomain: array('${adb.outputs.databricks_dbfs_storage_accountName}.blob.core.windows.net')
    // clientPrivateIpAddr: clientpc.outputs.clientPrivateIpaddr
    clientPrivateIpAddr: '10.0.200.4'
  }
}

module adlsGen2 './storage/storageaccount.template.bicep' = {
  scope: rg
  name: 'StorageAccount'
  params: {
    storageAccountName: storageAccountName
  }
}

module keyVault './keyvault/keyvault.template.bicep' = {
  scope: rg
  name: 'KeyVault'
  params: {
    keyVaultName: keyVaultName
    objectId: myIdentity.outputs.mIdentityClientId
  }
}

module clientpc './other/clientdevice.template.bicep' = {
  name: 'ClientPC'
  scope: rg
  params: {
    adminUsername: adminUsername
    adminPassword: adminPassword
    vnetName: hubVnetName
    clientPcName: clientPcName
  }
}

module loganalytics './monitor/loganalytics.template.bicep' = {
  scope: rg
  name: 'loganalytics'
}

module eventHubLogging './monitor/eventhub.template.bicep' = {
  scope: rg
  name: 'EventHub'
  params: {
    namespaceName: eHNameSpace
  }
}

module privateEndPoints './network/privateendpoint.template.bicep' = {
  scope: rg
  name: 'PrivateEndPoints'
  params: {
    keyvaultName: keyVault.name
    keyvaultPrivateLinkResource: keyVault.outputs.keyvault_id
    privateLinkSubnetId: vnets.outputs.privatelinksubnet_id
    storageAccountName: adlsGen2.name
    storageAccountPrivateLinkResource: adlsGen2.outputs.storageaccount_id
    eventHubName: eventHubName
    eventHubPrivateLinkResource: eventHubLogging.outputs.eHNamespaceId
    targetSubResourceDfs: 'dfs'
    targetSubResourceVault: 'vault'
    targetSubResourceEventHub: 'namespace'
    vnetName: spokeVnetName
  }
}

module createDatabricksCluster './databricks/deployment.template.bicep' = {
  scope: rg
  name: 'createDatabricksCluster'
  params: {
    location: location
    identity: myIdentity.outputs.mIdentityId
    adb_workspace_url: adb.outputs.databricks_workspaceUrl
    adb_workspace_id: adb.outputs.databricks_workspace_id
    adb_secret_scope_name: adbAkvLinkName
    akv_id: keyVault.outputs.keyvault_id
    akv_uri: keyVault.outputs.keyvault_uri
    LogAWkspId: loganalytics.outputs.logAnalyticsWkspId
    LogAWkspKey: loganalytics.outputs.primarySharedKey
    storageKey: adlsGen2.outputs.key1
    evenHubKey: eventHubLogging.outputs.eHPConnString
  }
}

// output resourceGroupName string = rg.name
// output keyVaultName string = keyVaultName
// output adbWorkspaceName string = adbWorkspaceName
// output storageAccountName string = storageAccountName
// output storageKey1 string = adlsGen2.outputs.key1
// output storageKey2 string = adlsGen2.outputs.key2
// output databricksWksp string = adb.outputs.databricks_workspace_id
// output databricks_workspaceUrl string = adb.outputs.databricks_workspaceUrl
// output keyvault_id string = keyVault.outputs.keyvault_id
// output keyvault_uri string = keyVault.outputs.keyvault_uri
// output logAnalyticsWkspId string = loganalytics.outputs.logAnalyticsWkspId
// output logAnalyticsprimarySharedKey string = loganalytics.outputs.primarySharedKey
// output logAnalyticssecondarySharedKey string = loganalytics.outputs.secondarySharedKey
// output eHNamespaceId string = eventHubLogging.outputs.eHNamespaceId
// output eHubNameId string = eventHubLogging.outputs.eHubNameId
// output eHAuthRulesId string = eventHubLogging.outputs.eHAuthRulesId
// output eHPConnString string = eventHubLogging.outputs.eHPConnString
// output dsOutputs object = createDatabricksCluster.outputs.patOutput
