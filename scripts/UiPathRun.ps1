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

try {
    Write-Host "Starting UiPath Job Execution..." -ForegroundColor Yellow

    # Validate UiPath CLI exists
    if (-not (Test-Path "$uipathCliFilePath")) {
        throw "UiPath CLI not found at: $uipathCliFilePath"
    }
    Write-Host "UiPath CLI found at: $uipathCliFilePath" -ForegroundColor Green

    Write-Host "Configuring UiPath CLI..." -ForegroundColor Yellow

    # Configure UiPath CLI with error checking
    $configResult = & "$uipathCliFilePath" config set accountLogicalName "$accountForApp" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set accountLogicalName: $configResult" }

    $configResult = & "$uipathCliFilePath" config set applicationId "$applicationId" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set applicationId: $configResult" }

    $configResult = & "$uipathCliFilePath" config set applicationSecret "$applicationSecret" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set applicationSecret: $configResult" }

    $configResult = & "$uipathCliFilePath" config set scopes "$applicationScope" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set scopes: $configResult" }

    $configResult = & "$uipathCliFilePath" config set orchestratorUrl "$uriOrch" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set orchestratorUrl: $configResult" }

    $configResult = & "$uipathCliFilePath" config set tenantLogicalName "$tenantlName" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set tenantLogicalName: $configResult" }

    Write-Host "Configuration completed successfully." -ForegroundColor Green

    # Connect to Orchestrator
    Write-Host "Authenticating to UiPath Orchestrator..." -ForegroundColor Yellow
    $loginResult = & "$uipathCliFilePath" login 2>&1
    if ($LASTEXITCODE -ne 0) { 
        throw "Authentication failed: $loginResult" 
    }
    Write-Host "Authentication successful." -ForegroundColor Green

    # Start the job
    Write-Host "Starting UiPath job: $processName" -ForegroundColor Yellow
    $jobResult = & "$uipathCliFilePath" jobs start `
        --process-name "$processName" `
        --folder "$folder_organization_unit" `
        --robot "$robots" `
        --timeout "$timeout" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Job start failed: $jobResult"
    }

    Write-Host "UiPath Job Triggered Successfully." -ForegroundColor Green
    Write-Host "Job Details: Process=$processName, Folder=$folder_organization_unit, Robot=$robots, Timeout=$timeout" -ForegroundColor Cyan

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script execution failed at line $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    exit 1
} finally {
    # Optional: Clear sensitive configuration (uncomment if needed)
    # Write-Host "Clearing sensitive configuration..." -ForegroundColor Yellow
    # & "$uipathCliFilePath" config clear 2>&1 | Out-Null
}
