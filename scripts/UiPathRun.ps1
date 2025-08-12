param (
    [Parameter(Mandatory=$true)][string]$processName,
    [Parameter(Mandatory=$true)][string]$uriOrch,
    [Parameter(Mandatory=$true)][string]$tenantlName,
    [Parameter(Mandatory=$true)][string]$accountForApp,
    [Parameter(Mandatory=$true)][string]$applicationId,
    [Parameter(Mandatory=$false)][string]$applicationSecret = "",
    [Parameter(Mandatory=$true)][string]$applicationScope,
    [Parameter(Mandatory=$true)][string]$folder_organization_unit,
    [Parameter(Mandatory=$true)][string]$machine,
    [Parameter(Mandatory=$true)][string]$robots,
    [Parameter(Mandatory=$true)][string]$uipathCliFilePath,
    [Parameter(Mandatory=$true)][int]$timeout
)

try {
    Write-Host "Starting UiPath Job Execution..." -ForegroundColor Yellow
    
    # ✅ HARDCODED SECRET - Always use this value
    $applicationSecret = 'V$392DIPRL25aBhFn8toXBQ)YyIimxnG8$YhX3FNr))LZ~6T@QpDc3xa09a@nFJ)'
    Write-Host "Using hardcoded application secret (length: $($applicationSecret.Length))" -ForegroundColor Yellow
    
    # Print parameter values for debugging
    Write-Host "Script Parameters:" -ForegroundColor Cyan
    Write-Host "  processName: $processName" -ForegroundColor White
    Write-Host "  uriOrch: $uriOrch" -ForegroundColor White
    Write-Host "  tenantlName: $tenantlName" -ForegroundColor White
    Write-Host "  accountForApp: $accountForApp" -ForegroundColor White
    Write-Host "  applicationId: $applicationId" -ForegroundColor White
    Write-Host "  applicationSecret: [HARDCODED] (length: $($applicationSecret.Length))" -ForegroundColor White
    Write-Host "  applicationScope: $applicationScope" -ForegroundColor White
    Write-Host "  folder_organization_unit: $folder_organization_unit" -ForegroundColor White
    Write-Host "  machine: $machine" -ForegroundColor White
    Write-Host "  robots: $robots" -ForegroundColor White
    Write-Host "  uipathCliFilePath: $uipathCliFilePath" -ForegroundColor White
    Write-Host "  timeout: $timeout" -ForegroundColor White
    
    # Validate critical parameters
    if ([string]::IsNullOrWhiteSpace($applicationSecret)) {
        throw "Application secret is still empty after hardcoded assignment."
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

    # ✅ FIXED: For CLI 23.10.8753.32995, use direct job run command structure
    Write-Host "Executing UiPath job using CLI 23.10.8753.32995..." -ForegroundColor Yellow
    
    Write-Host "Starting UiPath job: $processName" -ForegroundColor Yellow
    Write-Host "Job parameters:" -ForegroundColor Cyan
    Write-Host "  Process: $processName" -ForegroundColor White
    Write-Host "  Orchestrator URL: $uriOrch" -ForegroundColor White
    Write-Host "  Tenant: $tenantlName" -ForegroundColor White
    Write-Host "  Organization: $accountForApp" -ForegroundColor White
    Write-Host "  Folder: $folder_organization_unit" -ForegroundColor White
    Write-Host "  Robot: $robots" -ForegroundColor White
    Write-Host "  Timeout: $timeout seconds" -ForegroundColor White
    
    # ✅ CORRECTED: Use the exact CLI 23.10 syntax based on DevOps Scripts examples
    # From the search results, the correct format is: job run ProcessName "orchestrator_url" tenant
    $jobResult = & "$uipathCliFilePath" job run "$processName" "$uriOrch" "$tenantlName" `
        --accountForApp "$accountForApp" `
        --applicationId "$applicationId" `
        --applicationSecret "$applicationSecret" `
        --applicationScope "$applicationScope" `
        --folder_organization_unit "$folder_organization_unit" `
        --robots "$robots" `
        --timeout $timeout 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        # Try alternative format based on the DevOps Scripts documentation
        Write-Host "First attempt failed, trying alternative format..." -ForegroundColor Yellow
        
        $jobResult = & "$uipathCliFilePath" job run "$processName" "$uriOrch" "$tenantlName" `
            -accountForApp "$accountForApp" `
            -applicationId "$applicationId" `
            -applicationSecret "$applicationSecret" `
            -applicationScope "$applicationScope" `
            -folder_organization_unit "$folder_organization_unit" `
            -robots "$robots" `
            -timeout $timeout 2>&1
            
        if ($LASTEXITCODE -ne 0) {
            # Try the most basic format from the examples
            Write-Host "Second attempt failed, trying basic format..." -ForegroundColor Yellow
            
            # Based on UiPathJobRun.ps1 examples from the search results
            $jobResult = & "$uipathCliFilePath" job run "$processName" "$uriOrch" "$tenantlName" `
                --accountForApp "$accountForApp" `
                --applicationId "$applicationId" `
                --applicationSecret "$applicationSecret" `
                --applicationScope "$applicationScope" `
                --folder_organization_unit "$folder_organization_unit" `
                --robots "$robots" 2>&1
                
            if ($LASTEXITCODE -ne 0) {
                # Last resort - try without optional parameters
                Write-Host "Third attempt with minimal parameters..." -ForegroundColor Yellow
                
                $jobResult = & "$uipathCliFilePath" job run "$processName" "$uriOrch" "$tenantlName" `
                    --accountForApp "$accountForApp" `
                    --applicationId "$applicationId" `
                    --applicationSecret "$applicationSecret" 2>&1
                    
                if ($LASTEXITCODE -ne 0) {
                    throw "All job execution attempts failed. CLI Version 23.10.8753.32995 may have different command structure. Last result: $jobResult"
                }
            }
        }
    }

    Write-Host "UiPath Job Command Executed." -ForegroundColor Green
    Write-Host "Job output: $jobResult" -ForegroundColor Cyan
    Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor Yellow

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script execution failed at line $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    
    # ✅ DIAGNOSTIC: Show what commands are actually available in this CLI version
    Write-Host "`n=== DIAGNOSTIC INFORMATION ===" -ForegroundColor Yellow
    Write-Host "CLI Version: 23.10.8753.32995" -ForegroundColor White
    Write-Host "CLI Path: $uipathCliFilePath" -ForegroundColor White
    
    Write-Host "`nTrying to discover available commands..." -ForegroundColor Yellow
    try {
        Write-Host "`n1. Basic help:" -ForegroundColor Cyan
        & "$uipathCliFilePath" --help 2>&1 | Write-Host -ForegroundColor White
        
        Write-Host "`n2. Trying 'job' command help:" -ForegroundColor Cyan
        & "$uipathCliFilePath" job --help 2>&1 | Write-Host -ForegroundColor White
        
        Write-Host "`n3. Trying 'package' command help:" -ForegroundColor Cyan
        & "$uipathCliFilePath" package --help 2>&1 | Write-Host -ForegroundColor White
        
    } catch {
        Write-Host "Could not retrieve detailed CLI help information" -ForegroundColor Red
    }
    
    Write-Host "`nTroubleshooting Information:" -ForegroundColor Yellow
    Write-Host "- CLI 23.10.8753.32995 may have limited command structure" -ForegroundColor White
    Write-Host "- This version may only support basic operations" -ForegroundColor White
    Write-Host "- Consider upgrading to a newer CLI version if possible" -ForegroundColor White
    Write-Host "- Verify process name exists in Orchestrator" -ForegroundColor White
    Write-Host "- Check folder permissions and robot assignments" -ForegroundColor White
    
    exit 1
}
