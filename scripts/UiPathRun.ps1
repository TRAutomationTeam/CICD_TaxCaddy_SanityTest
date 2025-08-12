param (
    [Parameter(Mandatory=$true)][string]$processName,
    [Parameter(Mandatory=$true)][string]$uriOrch,
    [Parameter(Mandatory=$true)][string]$tenantlName,
    [Parameter(Mandatory=$true)][string]$accountForApp,
    [Parameter(Mandatory=$true)][string]$applicationId,
    [Parameter(Mandatory=$false)][AllowEmptyString()][string]$applicationSecret = "",  # ✅ FIXED: Made optional and allow empty string
    [Parameter(Mandatory=$true)][string]$applicationScope,
    [Parameter(Mandatory=$true)][string]$folder_organization_unit,
    [Parameter(Mandatory=$true)][string]$machine,
    [Parameter(Mandatory=$true)][string]$robots,
    [Parameter(Mandatory=$true)][string]$uipathCliFilePath,
    [Parameter(Mandatory=$true)][int]$timeout
)

try {
    Write-Host "Starting UiPath Job Execution..." -ForegroundColor Yellow
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
    
    # ✅ ADDED: Use hardcoded secret if not provided or empty
    if ([string]::IsNullOrWhiteSpace($applicationSecret)) {
        Write-Host "Using fallback hardcoded application secret..." -ForegroundColor Yellow
        $applicationSecret = 'V$392DIPRL25aBhFn8toXBQ)YyIimxnG8$YhX3FNr))LZ~6T@QpDc3xa09a@nFJ)'
    }
    
    # ✅ ADDED: Print parameter values for debugging
    Write-Host "Script Parameters:" -ForegroundColor Cyan
    Write-Host "  processName: $processName" -ForegroundColor White
    Write-Host "  uriOrch: $uriOrch" -ForegroundColor White
    Write-Host "  tenantlName: $tenantlName" -ForegroundColor White
    Write-Host "  accountForApp: $accountForApp" -ForegroundColor White
    Write-Host "  applicationId: $applicationId" -ForegroundColor White
    Write-Host "  applicationSecret: [HIDDEN] (length: $($applicationSecret.Length))" -ForegroundColor White
    Write-Host "  applicationScope: $applicationScope" -ForegroundColor White
    Write-Host "  folder_organization_unit: $folder_organization_unit" -ForegroundColor White
    Write-Host "  machine: $machine" -ForegroundColor White
    Write-Host "  robots: $robots" -ForegroundColor White
    Write-Host "  uipathCliFilePath: $uipathCliFilePath" -ForegroundColor White
    Write-Host "  timeout: $timeout" -ForegroundColor White
    
    # Validate critical parameters
    if ([string]::IsNullOrWhiteSpace($applicationSecret)) {
        throw "Application secret is still empty after hardcoded fallback."
    }
    
    if ([string]::IsNullOrWhiteSpace($processName)) {
        throw "Process name is empty or null."
    }
    
    if ([string]::IsNullOrWhiteSpace($uipathCliFilePath)) {
        throw "UiPath CLI path is empty or null."
    }

    # Validate UiPath CLI exists
    if (-not (Test-Path "$uipathCliFilePath")) {
        throw "UiPath CLI not found at: $uipathCliFilePath"
    }
    Write-Host "UiPath CLI found at: $uipathCliFilePath" -ForegroundColor Green

    Write-Host "Configuring UiPath CLI..." -ForegroundColor Yellow

    # Configure UiPath CLI with error checking
    Write-Host "Setting account logical name..." -ForegroundColor Cyan
    $configResult = & "$uipathCliFilePath" config set accountLogicalName "$accountForApp" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set accountLogicalName: $configResult" }

    Write-Host "Setting application ID..." -ForegroundColor Cyan
    $configResult = & "$uipathCliFilePath" config set applicationId "$applicationId" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set applicationId: $configResult" }

    Write-Host "Setting application secret..." -ForegroundColor Cyan
    $configResult = & "$uipathCliFilePath" config set applicationSecret "$applicationSecret" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set applicationSecret: $configResult" }

    Write-Host "Setting scopes..." -ForegroundColor Cyan
    $configResult = & "$uipathCliFilePath" config set scopes "$applicationScope" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set scopes: $configResult" }

    Write-Host "Setting orchestrator URL..." -ForegroundColor Cyan
    $configResult = & "$uipathCliFilePath" config set orchestratorUrl "$uriOrch" 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed to set orchestratorUrl: $configResult" }

    Write-Host "Setting tenant logical name..." -ForegroundColor Cyan
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
    Write-Host "Job parameters:" -ForegroundColor Cyan
    Write-Host "  Process: $processName" -ForegroundColor White
    Write-Host "  Folder: $folder_organization_unit" -ForegroundColor White
    Write-Host "  Robot: $robots" -ForegroundColor White
    Write-Host "  Timeout: $timeout seconds" -ForegroundColor White
    
    $jobResult = & "$uipathCliFilePath" jobs start `
        --process-name "$processName" `
        --folder "$folder_organization_unit" `
        --robot "$robots" `
        --timeout "$timeout" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        throw "Job start failed: $jobResult"
    }

    Write-Host "UiPath Job Triggered Successfully." -ForegroundColor Green
    Write-Host "Job output: $jobResult" -ForegroundColor Cyan

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script execution failed at line $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    
    # Additional troubleshooting info
    Write-Host "`nTroubleshooting Information:" -ForegroundColor Yellow
    Write-Host "- Check if hardcoded application secret is correct" -ForegroundColor White
    Write-Host "- Verify UiPath CLI path is correct" -ForegroundColor White
    Write-Host "- Ensure all required parameters are provided" -ForegroundColor White
    
    exit 1
} finally {
    # Optional: Clear sensitive configuration (uncomment if needed)
    # Write-Host "Clearing sensitive configuration..." -ForegroundColor Yellow
    # & "$uipathCliFilePath" config clear 2>&1 | Out-Null
}
