param (
    [Parameter(Mandatory=$true)][string]$processName,
    [Parameter(Mandatory=$true)][string]$uriOrch,
    [Parameter(Mandatory=$true)][string]$tenantlName,
    [Parameter(Mandatory=$true)][string]$accountForApp,
    [Parameter(Mandatory=$true)][string]$applicationId,
    [Parameter(Mandatory=$true)][string]$applicationSecret,
    [Parameter(Mandatory=$true)][string]$applicationScope,
    [Parameter(Mandatory=$true)][string]$folder_organization_unit,
    [Parameter(Mandatory=$true)][string]$machine,
    [Parameter(Mandatory=$true)][string]$robots,
    [Parameter(Mandatory=$true)][string]$uipathCliFilePath,
    [Parameter(Mandatory=$true)][int]$timeout
)

Write-Host "Starting UiPath Job Execution..."

# Authenticate using OAuth External App
& "$uipathCliFilePath" config set accountLogicalName "$accountForApp"
& "$uipathCliFilePath" config set applicationId "$applicationId"
& "$uipathCliFilePath" config set applicationSecret "$applicationSecret"
& "$uipathCliFilePath" config set scopes "$applicationScope"
& "$uipathCliFilePath" config set orchestratorUrl "$uriOrch"
& "$uipathCliFilePath" config set tenantLogicalName "$tenantlName"

# Connect to Orchestrator
& "$uipathCliFilePath" login
# Start the job
& "$uipathCliFilePath" jobs start `
    --process-name "$processName" `
    --folder "$folder_organization_unit" `
    --robot "$robots" `
    --timeout "$timeout"

Write-Host "UiPath Job Triggered Successfully."
