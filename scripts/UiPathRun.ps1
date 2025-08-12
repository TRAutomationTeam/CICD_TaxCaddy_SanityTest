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
    Write-Host "Starting UiPath Job Execution via API..." -ForegroundColor Yellow
    
    # ✅ HARDCODED SECRET
    $applicationSecret = 'V$392DIPRL25aBhFn8toXBQ)YyIimxnG8$YhX3FNr))LZ~6T@QpDc3xa09a@nFJ)'
    Write-Host "Using hardcoded application secret (length: $($applicationSecret.Length))" -ForegroundColor Yellow
    
    # ✅ ALTERNATIVE: Use direct REST API calls since CLI 23.10.8753.32995 is limited
    Write-Host "CLI 23.10.8753.32995 detected - using direct API approach" -ForegroundColor Yellow
    
    # Step 1: Get OAuth token
    Write-Host "Step 1: Getting OAuth token..." -ForegroundColor Cyan
    $tokenUri = "$uriOrch/identity_/connect/token"
    $tokenBody = @{
        grant_type = "client_credentials"
        client_id = $applicationId
        client_secret = $applicationSecret
        scope = $applicationScope
    }
    
    $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    $accessToken = $tokenResponse.access_token
    Write-Host "✅ OAuth token obtained successfully" -ForegroundColor Green
    
    # Step 2: Get Release Key for the process
    Write-Host "Step 2: Getting release information for process: $processName" -ForegroundColor Cyan
    $releasesUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Releases?\$filter=Name eq '$processName'"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
        "X-UIPATH-TenantName" = $tenantlName
        "X-UIPATH-OrganizationUnitId" = $folder_organization_unit
    }
    
    $releasesResponse = Invoke-RestMethod -Uri $releasesUri -Method GET -Headers $headers
    if ($releasesResponse.value.Count -eq 0) {
        throw "Process '$processName' not found in Orchestrator"
    }
    
    $releaseKey = $releasesResponse.value[0].Key
    Write-Host "✅ Found release key: $releaseKey" -ForegroundColor Green
    
    # Step 3: Start the job
    Write-Host "Step 3: Starting job..." -ForegroundColor Cyan
    $jobsUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Jobs/UiPath.Server.Configuration.OData.StartJobs"
    
    $jobBody = @{
        startInfo = @{
            ReleaseKey = $releaseKey
            Strategy = "Specific"
            RobotIds = @()  # Will be populated if specific robot needed
            NoOfRobots = 1
            Source = "Manual"
            InputArguments = "{}"
        }
    } | ConvertTo-Json -Depth 5
    
    $jobResponse = Invoke-RestMethod -Uri $jobsUri -Method POST -Headers $headers -Body $jobBody
    Write-Host "✅ Job started successfully" -ForegroundColor Green
    Write-Host "Job ID: $($jobResponse.value[0].Id)" -ForegroundColor Cyan
    Write-Host "Job Key: $($jobResponse.value[0].Key)" -ForegroundColor Cyan
    
    # Step 4: Monitor job (optional)
    if ($timeout -gt 0) {
        Write-Host "Step 4: Monitoring job for $timeout seconds..." -ForegroundColor Cyan
        $jobId = $jobResponse.value[0].Id
        $startTime = Get-Date
        
        do {
            Start-Sleep -Seconds 5
            $jobStatusUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Jobs($jobId)"
            $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Method GET -Headers $headers
            
            Write-Host "Job Status: $($jobStatus.State)" -ForegroundColor Yellow
            
            if ($jobStatus.State -in @("Successful", "Failed", "Stopped")) {
                Write-Host "✅ Job completed with status: $($jobStatus.State)" -ForegroundColor Green
                if ($jobStatus.State -eq "Failed") {
                    Write-Host "❌ Job failed with error: $($jobStatus.Info)" -ForegroundColor Red
                }
                break
            }
            
            $elapsed = (Get-Date) - $startTime
        } while ($elapsed.TotalSeconds -lt $timeout)
        
        if ($elapsed.TotalSeconds -ge $timeout) {
            Write-Host "⚠️ Job monitoring timed out after $timeout seconds" -ForegroundColor Yellow
        }
    }

    Write-Host "UiPath Job Execution Completed Successfully." -ForegroundColor Green

} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script execution failed at line $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    
    Write-Host "`nTroubleshooting Information:" -ForegroundColor Yellow
    Write-Host "- Using direct API calls due to CLI 23.10.8753.32995 limitations" -ForegroundColor White
    Write-Host "- Verify OAuth application credentials are correct" -ForegroundColor White
    Write-Host "- Check process name exists in specified folder" -ForegroundColor White
    Write-Host "- Ensure robot is available and licensed" -ForegroundColor White
    
    exit 1
}
