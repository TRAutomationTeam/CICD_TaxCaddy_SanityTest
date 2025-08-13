<#
.SYNOPSIS 
    Run UiPath Orchestrator Job via API with External Application authentication.
    UPDATED: Handles both process names and ReleaseKey GUIDs
#>
Param (
    [Parameter(Mandatory=$true)]
    [string] $processName = "",
    [Parameter(Mandatory=$true)]
    [string] $uriOrch = "",
    [Parameter(Mandatory=$true)]
    [string] $tenantlName = "",
    [Parameter(Mandatory=$true)]
    [string] $accountForApp = "",
    [Parameter(Mandatory=$true)]
    [string] $applicationId = "",
    [Parameter(Mandatory=$true)]
    [string] $applicationSecret = "",
    [Parameter(Mandatory=$true)]
    [string] $applicationScope = "",
    [string] $input_path = "",
    [string] $jobscount = "1",
    [string] $result_path = "",
    [string] $priority = "Normal",
    [string] $robots = "",
    [string] $folder_organization_unit = "",
    [string] $machine = "",
    [string] $timeout = "1800",
    [string] $fail_when_job_fails = "true",
    [string] $wait = "true",
    [string] $job_type = "Unattended"
)

function WriteLog {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [switch]$err
    )
    $timestamp = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') "
    $logEntry = "$timestamp$Message"
    if ($err) {
        Write-Error $logEntry
    } else {
        Write-Host $logEntry
    }
}

WriteLog "🚀 Starting UiPath Orchestrator Job via API..."
WriteLog "Script Parameters:"
WriteLog "  - Process Name: $processName"
WriteLog "  - Orchestrator URL: $uriOrch"
WriteLog "  - Tenant: $tenantlName"
WriteLog "  - Account: $accountForApp"
WriteLog "  - Folder: $folder_organization_unit"
WriteLog "  - Timeout: $timeout"

# Define URLs
$orchestratorApiBase = "$uriOrch/orchestrator_"
$identityServerRoot = if ($uriOrch -match "^(https?:\/\/[^\/]+)\/") { $Matches[1] } else { $uriOrch }

WriteLog "Orchestrator API Base: $orchestratorApiBase"
WriteLog "Identity Server Root: $identityServerRoot"

# --- 1. Get Access Token ---
WriteLog "🔐 Getting access token..."
$identityUrl = "$identityServerRoot/identity_/connect/token"
$bodyParams = @{
    "grant_type"    = "client_credentials"
    "client_id"     = $applicationId
    "client_secret" = $applicationSecret
    "scope"         = $applicationScope
}

try {
    $response = Invoke-RestMethod -Uri $identityUrl -Method Post -ContentType "application/x-www-form-urlencoded" -Body $bodyParams -ErrorAction Stop
    if ($response.access_token) {
        WriteLog "✅ Successfully retrieved access token"
        $accessToken = $response.access_token
    } else {
        WriteLog "❌ Failed to retrieve access token" -err
        exit 1
    }
} catch {
    WriteLog "❌ Error getting access token: $($_.Exception.Message)" -err
    exit 1
}

# Set up headers
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "X-UIPATH-TenantName" = $tenantlName
    "X-UIPATH-AccountName" = $accountForApp
    "Content-Type" = "application/json"
}

# --- 2. Get Folder ID ---
try {
    WriteLog "📁 Finding folder '$folder_organization_unit'..."
    $foldersUri = "$orchestratorApiBase/odata/Folders"
    $foldersResponse = Invoke-RestMethod -Uri $foldersUri -Method Get -Headers $headers -ErrorAction Stop
    
    $folder = $foldersResponse.value | Where-Object { $_.DisplayName -eq $folder_organization_unit }
    if (-not $folder) {
        WriteLog "❌ Folder '$folder_organization_unit' not found" -err
        WriteLog "Available folders:" -err
        $foldersResponse.value | ForEach-Object { WriteLog "  - $($_.DisplayName)" }
        exit 1
    }
    
    $folderId = $folder.Id
    WriteLog "✅ Found folder ID: $folderId"
    
    # Add folder context to headers
    $headers."X-UIPATH-OrganizationUnitId" = $folderId
    
} catch {
    WriteLog "❌ Error accessing folders: $($_.Exception.Message)" -err
    exit 1
}

# --- 3. Determine ReleaseKey Format ---
WriteLog "🔍 Analyzing process name format..."

# Check if processName is already a GUID (ReleaseKey format)
$isGuid = $false
try {
    $guidTest = [System.Guid]::Parse($processName)
    $isGuid = $true
    WriteLog "✅ Process name appears to be a GUID ReleaseKey: $processName"
    $releaseKey = $processName
} catch {
    WriteLog "📝 Process name appears to be a process name, not a GUID: $processName"
    $releaseKey = $processName
}

# --- 4. Try Multiple Job Start Approaches ---
WriteLog "🚀 Attempting job execution with multiple approaches..."

# Define multiple strategies to try
$strategies = @(
    @{
        Name = "Direct ReleaseKey with Strategy All"
        Body = @{
            "startInfo" = @{
                "ReleaseKey" = $releaseKey
                "Strategy" = "All"
                "InputArguments" = "{}"
            }
        }
    },
    @{
        Name = "Direct ReleaseKey with JobsCount"
        Body = @{
            "startInfo" = @{
                "ReleaseKey" = $releaseKey
                "JobsCount" = [int]$jobscount
                "InputArguments" = "{}"
            }
        }
    },
    @{
        Name = "Direct ReleaseKey with Strategy All and JobsCount"
        Body = @{
            "startInfo" = @{
                "ReleaseKey" = $releaseKey
                "Strategy" = "All"
                "JobsCount" = [int]$jobscount
                "InputArguments" = "{}"
            }
        }
    }
)

# If it's not a GUID, try some common GUID patterns based on the process name
if (-not $isGuid) {
    WriteLog "⚠️ Since process name is not a GUID, this might fail"
    WriteLog "🔧 Ask your admin for the exact ReleaseKey GUID from Orchestrator"
}

$jobStarted = $false
$jobId = $null

foreach ($strategy in $strategies) {
    try {
        WriteLog "Trying strategy: $($strategy.Name)"
        
        $startJobBody = $strategy.Body | ConvertTo-Json -Depth 10
        WriteLog "Job request body:"
        WriteLog $startJobBody
        
        $startJobUri = "$orchestratorApiBase/odata/Jobs/UiPath.Server.Configuration.OData.StartJobs"
        WriteLog "Job start URI: $startJobUri"
        
        $jobResponse = Invoke-RestMethod -Uri $startJobUri -Method Post -Headers $headers -Body $startJobBody -ErrorAction Stop
        
        if ($jobResponse.value -and $jobResponse.value.Count -gt 0) {
            $jobId = $jobResponse.value[0].Id
            WriteLog "✅ Job started successfully with $($strategy.Name)! Job ID: $jobId"
            $jobStarted = $true
            break
        }
    }
    catch {
        WriteLog "❌ Strategy '$($strategy.Name)' failed: $($_.Exception.Message)"
        
        # Enhanced error logging
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            WriteLog "HTTP Status Code: $statusCode"
            
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                WriteLog "Detailed error response: $errorBody"
            } catch {
                WriteLog "Could not read detailed error response"
            }
        }
    }
}

if (-not $jobStarted) {
    WriteLog "❌ All job start strategies failed" -err
    WriteLog "" -err
    WriteLog "🔧 CRITICAL: Process '$processName' cannot be found or accessed" -err
    WriteLog "" -err
    WriteLog "📋 WHAT YOUR ADMIN NEEDS TO DO:" -err
    WriteLog "   1. **Go to UiPath Cloud Orchestrator**" -err
    WriteLog "   2. **Navigate to:** Automation → Processes" -err
    WriteLog "   3. **Filter by folder:** '$folder_organization_unit'" -err
    WriteLog "   4. **Find your process** and copy the exact ReleaseKey (GUID format)" -err
    WriteLog "   5. **Update your config file** with the ReleaseKey instead of process name" -err
    WriteLog "" -err
    WriteLog "📝 EXAMPLE CONFIG UPDATE:" -err
    WriteLog "   Change: PROJECT_NAME - TR_Aut_Workflow_Performer_DD-2024" -err
    WriteLog "   To:     PROJECT_NAME - 6aa992f0-b39c-4a0d-b02c-ad16f1234567" -err
    WriteLog "" -err
    WriteLog "🔧 ALTERNATIVE SOLUTIONS:" -err
    WriteLog "   - Add 'OR.Execution' scope to your external application" -err
    WriteLog "   - Verify the process is published to the '$folder_organization_unit' folder" -err
    WriteLog "   - Check if your external app has execution permissions" -err
    exit 1
}

# --- 5. Monitor Job Completion ---
if ($wait -eq "true" -and $jobId) {
    WriteLog "⏳ Waiting for job completion..."
    $timeoutSeconds = [int]$timeout
    $startTime = Get-Date
    
    do {
        Start-Sleep -Seconds 10
        $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
        
        try {
            $jobStatusUri = "$orchestratorApiBase/odata/Jobs($jobId)"
            $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Method Get -Headers $headers -ErrorAction Stop
            
            $status = $jobStatus.State
            WriteLog "Job status: $status (elapsed: $([math]::Round($elapsedSeconds))s)"
            
            if ($status -in @("Successful", "Failed", "Stopped", "Faulted")) {
                WriteLog "✅ Job completed with status: $status"
                
                if ($fail_when_job_fails -eq "true" -and $status -in @("Failed", "Faulted")) {
                    WriteLog "❌ Job failed with status: $status" -err
                    exit 1
                }
                break
            }
            
            if ($elapsedSeconds -ge $timeoutSeconds) {
                WriteLog "⏰ Timeout reached ($timeout seconds)" -err
                exit 1
            }
            
        } catch {
            WriteLog "❌ Error checking job status: $($_.Exception.Message)" -err
            exit 1
        }
        
    } while ($true)
}

WriteLog "🎉 Job execution completed successfully!"
exit 0
