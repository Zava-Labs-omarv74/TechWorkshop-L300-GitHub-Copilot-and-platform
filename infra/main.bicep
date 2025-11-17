@description('The environment name. Used to generate unique resource names.')
param environmentName string

@description('The location to deploy resources.')
param location string = resourceGroup().location

// Generate unique suffix for resource names
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)

// Resource naming
var appServicePlanName = 'asp-${environmentName}-${resourceToken}'
var appServiceName = 'app-${environmentName}-${resourceToken}'
var applicationInsightsName = 'ai-${environmentName}-${resourceToken}'
var logAnalyticsWorkspaceName = 'law-${environmentName}-${resourceToken}'
var managedIdentityName = 'id-${environmentName}-${resourceToken}'

// Create User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: {
    'azd-env-name': environmentName
    SecurityControl: 'Ignore'
  }
}

// Create Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: {
    'azd-env-name': environmentName
    SecurityControl: 'Ignore'
  }
}

// Create Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: {
    'azd-env-name': environmentName
    SecurityControl: 'Ignore'
  }
}

// Create App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
    capacity: 1
  }
  kind: 'app'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
  tags: {
    'azd-env-name': environmentName
    SecurityControl: 'Ignore'
  }
}

// Create App Service (Web App)
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appServiceName
  location: location
  kind: 'app'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: 'dotnet'
        }
      ]
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'recommended'
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
      ]
      connectionStrings: []
      defaultDocuments: [
        'Default.htm'
        'Default.html'
        'Default.asp'
        'index.htm'
        'index.html'
        'iisstart.htm'
        'default.aspx'
        'index.php'
      ]
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: true
      publishingUsername: '$${appServiceName}'
      use32BitWorkerProcess: false
      webSocketsEnabled: false
      alwaysOn: true
      managedPipelineMode: 'Integrated'
      virtualApplications: [
        {
          virtualPath: '/'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: true
        }
      ]
      loadBalancing: 'LeastRequests'
      experiments: {
        rampUpRules: []
      }
      autoHealEnabled: false
      vnetRouteAllEnabled: false
      vnetPrivatePortsCount: 0
      localMySqlEnabled: false
      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictionsUseMain: false
      http20Enabled: false
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      preWarmedInstanceCount: 0
      functionsRuntimeScaleMonitoringEnabled: false
      minimumElasticInstanceCount: 0
      azureStorageAccounts: {}
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: true
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    customDomainVerificationId: subscription().id
    containerSize: 0
    dailyMemoryTimeQuota: 0
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: managedIdentity.id
  }
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'zavastorefront'
    SecurityControl: 'Ignore'
  }
}

// Create required Site Extension for App Service
resource siteExtension 'Microsoft.Web/sites/siteextensions@2023-01-01' = {
  parent: appService
  name: 'Microsoft.ApplicationInsights.AzureWebSites'
}

// Configure logging for App Service
resource appServiceLogs 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: appService
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Warning'
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 35
        enabled: true
      }
    }
    failedRequestsTracing: {
      enabled: true
    }
    detailedErrorMessages: {
      enabled: true
    }
  }
}

// Outputs
@description('The resource group ID')
output RESOURCE_GROUP_ID string = resourceGroup().id

@description('The App Service name')
output APP_SERVICE_NAME string = appService.name

@description('The App Service URL')
output APP_SERVICE_URL string = 'https://${appService.properties.defaultHostName}'

@description('The Application Insights connection string')
output APPLICATIONINSIGHTS_CONNECTION_STRING string = applicationInsights.properties.ConnectionString

@description('The Log Analytics Workspace ID')
output LOG_ANALYTICS_WORKSPACE_ID string = logAnalyticsWorkspace.id

@description('The managed identity ID')
output MANAGED_IDENTITY_ID string = managedIdentity.id

@description('The managed identity client ID')
output MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.properties.clientId
