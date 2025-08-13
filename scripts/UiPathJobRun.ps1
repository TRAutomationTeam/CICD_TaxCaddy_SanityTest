<#
.SYNOPSIS 
    Run UiPath Orchestrator Job via API with External Application authentication.
    UPDATED: Uses ModernJobsCount strategy - no robot resolution needed
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
WriteLog "Available scopes: $applicationScope"

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

# --- 3. Use Process Name Directly (Skip Process Resolution) ---
WriteLog "⚙️ Using process name directly as ReleaseKey: $processName"
$processKey = $processName

# --- 4. Start Job Using ModernJobsCount Strategy (No Robot Resolution Needed) ---
WriteLog "🚀 Starting job with ModernJobsCount strategy (automatic robot selection)..."

$startJobBody = @{
    "startInfo" = @{
        "ReleaseKey" = $processKey
        "Strategy" = "ModernJobsCount"
        "JobsCount" = [int]$jobscount
        "JobPriority" = $priority
        "RuntimeType" = "Unattended"
        "InputArguments" = "{}"
    }
} | ConvertTo-Json -Depth 10

WriteLog "Job request body:"
WriteLog $startJobBody

try {
    $startJobUri = "$orchestratorApiBase/odata/Jobs/UiPath.Server.Configuration.OData.StartJobs"
    WriteLog "Job start URI: $startJobUri"
    
    $jobResponse = Invoke-RestMethod -Uri $startJobUri -Method Post -Headers $headers -Body $startJobBody -ErrorAction Stop
    
    if ($jobResponse.value -and $jobResponse.value.Count -gt 0) {
        $jobId = $jobResponse.value[0].Id
        WriteLog "✅ Job started successfully! Job ID: $jobId"
        
        if ($wait -eq "true") {
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
    } else {
        WriteLog "❌ No jobs were started" -err
        exit 1
    }
    
} catch {
    WriteLog "❌ Error starting job: $($_.Exception.Message)" -err
    
    if ($_.Exception.Response.StatusCode -eq 403) {
        WriteLog "🔧 403 Forbidden - Your external app may need additional job execution permissions" -err
        WriteLog "🔧 Ask admin to assign your external app to '$folder_organization_unit' folder with appropriate roles" -err
    }
    
    # Log detailed error response if available
    if ($_.Exception.Response) {
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            WriteLog "Error response body: $errorBody" -err
        } catch {
            WriteLog "Could not read error response body" -err
        }
    }
    
    exit 1
}
