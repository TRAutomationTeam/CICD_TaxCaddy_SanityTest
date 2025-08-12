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
    Write-Host "=== UiPath Job Execution Script ===" -ForegroundColor Yellow
    Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    
    # ✅ HARDCODED SECRET (Consider using secure parameter or environment variable)
    $applicationSecret = 'V$392DIPRL25aBhFn8toXBQ)YyIimxnG8$YhX3FNr))LZ~6T@QpDc3xa09a@nFJ)'
    Write-Host "Using hardcoded application secret (length: $($applicationSecret.Length))" -ForegroundColor Yellow
    
    # Print parameter values for debugging (excluding sensitive data)
    Write-Host "`n=== SCRIPT PARAMETERS ===" -ForegroundColor Cyan
    Write-Host "  processName: $processName" -ForegroundColor White
    Write-Host "  uriOrch: $uriOrch" -ForegroundColor White
    Write-Host "  tenantlName: $tenantlName" -ForegroundColor White
    Write-Host "  accountForApp: $accountForApp" -ForegroundColor White
    Write-Host "  applicationId: $applicationId" -ForegroundColor White
    Write-Host "  applicationSecret: [SECURED] (length: $($applicationSecret.Length))" -ForegroundColor White
    Write-Host "  applicationScope: $applicationScope" -ForegroundColor White
    Write-Host "  folder_organization_unit: $folder_organization_unit" -ForegroundColor White
    Write-Host "  machine: $machine" -ForegroundColor White
    Write-Host "  robots: $robots" -ForegroundColor White
    Write-Host "  uipathCliFilePath: $uipathCliFilePath" -ForegroundColor White
    Write-Host "  timeout: $timeout seconds" -ForegroundColor White
    
    # Validate critical parameters
    Write-Host "`n=== PARAMETER VALIDATION ===" -ForegroundColor Cyan
    
    if ([string]::IsNullOrWhiteSpace($applicationSecret)) {
        throw "Application secret is empty after assignment."
    }
    Write-Host "✅ Application secret validated" -ForegroundColor Green
    
    if ([string]::IsNullOrWhiteSpace($processName)) {
        throw "Process name is empty or null."
    }
    Write-Host "✅ Process name validated: $processName" -ForegroundColor Green
    
    if ([string]::IsNullOrWhiteSpace($uipathCliFilePath)) {
        throw "UiPath CLI path is empty or null."
    }
    Write-Host "✅ CLI path parameter validated" -ForegroundColor Green

    # Validate UiPath CLI exists and is accessible
    if (-not (Test-Path "$uipathCliFilePath")) {
        Write-Host "❌ UiPath CLI not found at: $uipathCliFilePath" -ForegroundColor Red
        
        # Provide helpful diagnostics
        $parentDir = Split-Path $uipathCliFilePath -Parent
        if (Test-Path $parentDir) {
            Write-Host "Contents of parent directory ($parentDir):" -ForegroundColor Yellow
            Get-ChildItem $parentDir | ForEach-Object { 
                Write-Host "  $($_.Name) $(if($_.PSIsContainer){'[DIR]'}else{"($($_.Length) bytes)"})" -ForegroundColor Gray
            }
        } else {
            Write-Host "Parent directory does not exist: $parentDir" -ForegroundColor Red
        }
        throw "UiPath CLI not found at specified path"
    }
    Write-Host "✅ UiPath CLI found at: $uipathCliFilePath" -ForegroundColor Green

    # Test CLI accessibility
    try {
        $cliVersion = & "$uipathCliFilePath" --version 2>&1
        Write-Host "✅ CLI Version: $cliVersion" -ForegroundColor Green
    } catch {
        Write-Warning "Could not get CLI version: $_"
    }

    # ✅ DIRECT REST API APPROACH - More reliable than CLI for job execution
    Write-Host "`n=== USING DIRECT API APPROACH ===" -ForegroundColor Yellow
    Write-Host "Using REST API calls for better reliability and control..." -ForegroundColor Cyan
    
    # Step 1: Get OAuth token
    Write-Host "`nStep 1: Obtaining OAuth token..." -ForegroundColor Cyan
    $tokenUri = "$uriOrch/identity_/connect/token"
    $tokenBody = @{
        grant_type = "client_credentials"
        client_id = $applicationId
        client_secret = $applicationSecret
        scope = $applicationScope
    }
    
    try {
        Write-Host "Token endpoint: $tokenUri" -ForegroundColor Gray
        $tokenResponse = Invoke-RestMethod -Uri $tokenUri -Method POST -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
        $accessToken = $tokenResponse.access_token
        Write-Host "✅ OAuth token obtained successfully" -ForegroundColor Green
        Write-Host "Token type: $($tokenResponse.token_type)" -ForegroundColor Gray
        Write-Host "Expires in: $($tokenResponse.expires_in) seconds" -ForegroundColor Gray
    } catch {
        Write-Host "❌ Failed to get OAuth token" -ForegroundColor Red
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response body: $responseBody" -ForegroundColor Red
        }
        throw "Failed to get OAuth token: $($_.Exception.Message)"
    }
    
    # Step 2: Get Release Key for the process
    Write-Host "`nStep 2: Getting release information for process: $processName" -ForegroundColor Cyan
    $releasesUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Releases?\$filter=Name eq '$processName'"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
        "Content-Type" = "application/json"
        "X-UIPATH-TenantName" = $tenantlName
        "X-UIPATH-OrganizationUnitId" = $folder_organization_unit
    }
    
    try {
        Write-Host "Releases endpoint: $releasesUri" -ForegroundColor Gray
        $releasesResponse = Invoke-RestMethod -Uri $releasesUri -Method GET -Headers $headers
        
        if ($releasesResponse.value.Count -eq 0) {
            Write-Host "❌ Process '$processName' not found in Orchestrator" -ForegroundColor Red
            Write-Host "Available processes in folder:" -ForegroundColor Yellow
            
            # Try to list available processes
            try {
                $allReleasesUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Releases"
                $allReleases = Invoke-RestMethod -Uri $allReleasesUri -Method GET -Headers $headers
                $allReleases.value | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
            } catch {
                Write-Host "Could not retrieve available processes" -ForegroundColor Red
            }
            
            throw "Process '$processName' not found in Orchestrator"
        }
        
        $release = $releasesResponse.value[0]
        $releaseKey = $release.Key
        Write-Host "✅ Found release:" -ForegroundColor Green
        Write-Host "  Name: $($release.Name)" -ForegroundColor Gray
        Write-Host "  Key: $releaseKey" -ForegroundColor Gray
        Write-Host "  Version: $($release.Version)" -ForegroundColor Gray
        
    } catch {
        Write-Host "❌ Failed to get release information" -ForegroundColor Red
        throw "Failed to get release information: $($_.Exception.Message)"
    }
    
    # Step 3: Start the job
    Write-Host "`nStep 3: Starting job execution..." -ForegroundColor Cyan
    $jobsUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Jobs/UiPath.Server.Configuration.OData.StartJobs"
    
    $jobBody = @{
        startInfo = @{
            ReleaseKey = $releaseKey
            Strategy = "Specific"
            RobotIds = @()  # Empty for any available robot
            NoOfRobots = 1
            Source = "Manual"
            InputArguments = "{}"
        }
    } | ConvertTo-Json -Depth 5
    
    try {
        Write-Host "Jobs endpoint: $jobsUri" -ForegroundColor Gray
        Write-Host "Job payload: $jobBody" -ForegroundColor Gray
        
        $jobResponse = Invoke-RestMethod -Uri $jobsUri -Method POST -Headers $headers -Body $jobBody
        
        if ($jobResponse.value -and $jobResponse.value.Count -gt 0) {
            $job = $jobResponse.value[0]
            Write-Host "✅ Job started successfully" -ForegroundColor Green
            Write-Host "  Job ID: $($job.Id)" -ForegroundColor Cyan
            Write-Host "  Job Key: $($job.Key)" -ForegroundColor Cyan
            Write-Host "  State: $($job.State)" -ForegroundColor Cyan
            Write-Host "  Robot: $($job.Robot.Name)" -ForegroundColor Cyan
        } else {
            throw "No job information returned from start jobs API"
        }
        
    } catch {
        Write-Host "❌ Failed to start job" -ForegroundColor Red
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        throw "Failed to start job: $($_.Exception.Message)"
    }
    
    # Step 4: Monitor job execution
    if ($timeout -gt 0 -and $job) {
        Write-Host "`nStep 4: Monitoring job execution (timeout: $timeout seconds)..." -ForegroundColor Cyan
        $jobId = $job.Id
        $startTime = Get-Date
        $checkInterval = 5  # Check every 5 seconds
        $lastState = ""
        
        do {
            Start-Sleep -Seconds $checkInterval
            try {
                $jobStatusUri = "$uriOrch/$tenantlName/$accountForApp/orchestrator_/odata/Jobs($jobId)"
                $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Method GET -Headers $headers
                
                if ($jobStatus.State -ne $lastState) {
                    Write-Host "Job Status: $($jobStatus.State)" -ForegroundColor Yellow
                    $lastState = $jobStatus.State
                    
                    # Show additional info for
