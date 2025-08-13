<#
.SYNOPSIS 
    Run UiPath Orchestrator Job via API with External Application authentication.
    UPDATED: Automatically finds ReleaseKey GUID via API call
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

# --- 3. NEW: Find ReleaseKey by Looking Up Process/Release ---
WriteLog "🔍 Looking up ReleaseKey for process '$processName'..."

$releaseKey = $null
$foundProcess = $null

# Try multiple endpoints to find the process
$endpoints = @(
    @{ Name = "Releases"; Uri = "$orchestratorApiBase/odata/Releases"; KeyField = "Key"; NameField = "Name"; ProcessField = "ProcessKey" },
    @{ Name = "Processes"; Uri = "$orchestratorApiBase/odata/Processes"; KeyField = "Key"; NameField = "Name"; ProcessField = "Key" }
)

foreach ($endpoint in $endpoints) {
    try {
        WriteLog "Trying endpoint: $($endpoint.Name)"
        $response = Invoke-RestMethod -Uri $endpoint.Uri -Method Get -Headers $headers -ErrorAction Stop
        
        if ($response.value) {
            WriteLog "Found $($response.value.Count) items in $($endpoint.Name)"
            
            # List all available processes for debugging
            WriteLog "Available processes in $($endpoint.Name):"
            $response.value | ForEach-Object {
                $name = $_."$($endpoint.NameField)"
                $key = $_."$($endpoint.KeyField)"
                $processKey = if ($endpoint.ProcessField) { $_."$($endpoint.ProcessField)" } else { $key }
                WriteLog "  - Name: '$name', Key: '$key', ProcessKey: '$processKey'"
            }
            
            # Try to find exact match by name
            $foundProcess = $response.value | Where-Object { 
                $_."$($endpoint.NameField)" -eq $processName
            }
            
            if ($foundProcess) {
                $releaseKey = $foundProcess."$($endpoint.KeyField)"
                WriteLog "✅ Found exact match in $($endpoint.Name)!"
                WriteLog "✅ Process Name: '$($foundProcess."$($endpoint.NameField)")"
                WriteLog "✅ ReleaseKey: '$releaseKey'"
                break
            } else {
                WriteLog "⚠️ No exact match found in $($endpoint.Name)"
            }
        } else {
            WriteLog "⚠️ No data returned from $($endpoint.Name)"
        }
    }
    catch {
        WriteLog "❌ Error accessing $($endpoint.Name): $($_.Exception.Message)"
    }
}

# If we still haven't found it, try partial matching
if (-not $releaseKey) {
    WriteLog "🔍 Trying partial name matching..."
    
    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-RestMethod -Uri $endpoint.Uri -Method Get -Headers $headers -ErrorAction SilentlyContinue
            if ($response.value) {
                # Try partial match (contains)
                $foundProcess = $response.value | Where-Object { 
                    $_."$($endpoint.NameField)" -like "*$processName*" -or $processName -like "*$($_."$($endpoint.NameField)")*"
                }
                
                if ($foundProcess) {
                    if ($foundProcess.Count -gt 1) {
                        WriteLog "⚠️ Multiple partial matches found in $($endpoint.Name):"
                        $foundProcess | ForEach-Object { 
                            WriteLog "  - '$($_."$($endpoint.NameField)")' (Key: '$($_."$($endpoint.KeyField)")')" 
                        }
                        $foundProcess = $foundProcess[0]
                        WriteLog "Using first match: '$($foundProcess."$($endpoint.NameField)")'"
                    }
                    
                    $releaseKey = $foundProcess."$($endpoint.KeyField)"
                    WriteLog "✅ Found partial match in $($endpoint.Name)!"
                    WriteLog "✅ Process Name: '$($foundProcess."$($endpoint.NameField)")"
                    WriteLog "✅ ReleaseKey: '$releaseKey'"
                    break
                }
            }
        }
        catch {
            # Silent continue for partial matching attempts
        }
    }
}

# Final fallback: use the process name as-is
if (-not $releaseKey) {
    WriteLog "⚠️ Could not find ReleaseKey via API calls"
    WriteLog "⚠️ Using process name directly as ReleaseKey (might fail): $processName"
    $releaseKey = $processName
}

# --- 4. Start Job with Found ReleaseKey ---
WriteLog "🚀 Starting job with ReleaseKey: $releaseKey"

# Use the most basic strategy that should work
$startJobBody = @{
    "startInfo" = @{
        "ReleaseKey" = $releaseKey
        "JobsCount" = [int]$jobscount
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
    
    # Enhanced error logging
    if ($_.Exception.Response) {
        $statusCode = $_.Exception.Response.StatusCode
        WriteLog "HTTP Status Code: $statusCode" -err
        
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorBody = $reader.ReadToEnd()
            WriteLog "Detailed error response: $errorBody" -err
        } catch {
            WriteLog "Could not read detailed error response" -err
        }
    }
    
    WriteLog "🔧 TROUBLESHOOTING:" -err
    WriteLog "   1. Verify process '$processName' exists and is published" -err
    WriteLog "   2. Check if your external app has execution permissions" -err
    WriteLog "   3. Ask admin to add 'OR.Execution' scope to your external application" -err
    exit 1
}
