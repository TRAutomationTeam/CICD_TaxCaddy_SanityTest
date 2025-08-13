<#
.SYNOPSIS 
    Run UiPath Orchestrator Job via Orchestrator API with External Application authentication.

.DESCRIPTION 
    This script triggers an Orchestrator job using direct API calls with OAuth2 External Application authentication.
    Updated to align with GitHub Actions workflow requirements.
#>
Param (
    #Required
    [Parameter(Mandatory=$true, Position = 0)]
    [string] $processName = "", #Process Name (pos. 0)           Required.
    [Parameter(Mandatory=$true, Position = 1)]
    [string] $uriOrch = "", #Orchestrator URL (pos. 1)       Required. The URL of the Orchestrator instance.
    [Parameter(Mandatory=$true, Position = 2)]
    [string] $tenantlName = "", #Orchestrator Tenant (pos. 2)    Required. The tenant of the Orchestrator instance.

    #External Apps (Option 1) - ONLY these will be used for authentication
    [Parameter(Mandatory=$true)]
    [string] $accountForApp = "", 
    [Parameter(Mandatory=$true)]
    [string] $applicationId = "", 
    [Parameter(Mandatory=$true)]
    [string] $applicationSecret = "", 
    [Parameter(Mandatory=$true)]
    [string] $applicationScope = "", 

    # Other job parameters
    [string] $input_path = "", 
    [string] $jobscount = "1", # Default to 1
    [string] $result_path = "", 
    [string] $priority = "Normal", 
    [string] $robots = "", 
    [string] $folder_organization_unit = "", 
    [string] $machine = "", 
    [string] $timeout = "1800", 
    [string] $fail_when_job_fails = "true", 
    [string] $wait = "true", 
    [string] $job_type = "Unattended" # Assuming unattended for CI/CD
)

function WriteLog {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [switch]$err,
        [switch]$noTimestamp
    )
    $timestamp = if ($noTimestamp) { "" } else { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') " }
    $logEntry = "$timestamp$Message"
    if ($err) {
        Write-Error $logEntry
        if ($debugLog -and (Test-Path (Split-Path $debugLog -Parent))) {
            Add-Content -Path $debugLog -Value $logEntry -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host $logEntry
        if ($debugLog -and (Test-Path (Split-Path $debugLog -Parent))) {
            Add-Content -Path $debugLog -Value $logEntry -ErrorAction SilentlyContinue
        }
    }
}

# Running Path for log file
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = "$scriptPath\orchestrator-job-run.log"

# Create log directory if it doesn't exist
$logDir = Split-Path $debugLog -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# Clear previous log file on each run for fresh logs
if (Test-Path $debugLog) {
    Remove-Item $debugLog -Force -ErrorAction SilentlyContinue
}

WriteLog "🚀 Starting UiPath Orchestrator Job via API..."
WriteLog "Script Parameters:"
WriteLog "  - Process Name: $processName"
WriteLog "  - Orchestrator URL: $uriOrch"
WriteLog "  - Tenant: $tenantlName"
WriteLog "  - Account: $accountForApp"
WriteLog "  - Folder: $folder_organization_unit"
WriteLog "  - Robots: $robots"
WriteLog "  - Machine: $machine"
WriteLog "  - Timeout: $timeout"

# Define the base URL for Orchestrator OData API calls
$orchestratorApiBase = "$uriOrch/orchestrator_"
WriteLog "Orchestrator API Base for OData calls: $orchestratorApiBase"

# Determine the Identity Server Base URL from $uriOrch
$identityServerRoot = ""
if ($uriOrch -match "^(https?:\/\/[^\/]+)\/") {
    $identityServerRoot = $Matches[1]
} else {
    $identityServerRoot = $uriOrch
}
WriteLog "Identity Server Root URL: $identityServerRoot"

# --- 1. Get Access Token from External Application Credentials ---
Function Get-OrchestratorAccessToken {
    Param (
        [string]$accountName,
        [string]$applicationId,
        [string]$applicationSecret,
        [string]$applicationScope,
        [string]$identityBaseUrl
    )
    WriteLog "🔐 Attempting to get access token for external application..."
    
    $identityUrl = "$($identityBaseUrl)/identity_/connect/token" 
    WriteLog "Identity URL for token: $identityUrl"

    $bodyParams = @{
        "grant_type"    = "client_credentials"
        "client_id"     = $applicationId
        "client_secret" = $applicationSecret
        "scope"         = $applicationScope
    }
    
    $maskedBodyForLog = "grant_type=client_credentials&client_id=$applicationId&client_secret=***MASKED***&scope=$applicationScope"
    WriteLog "Token request body (masked): $maskedBodyForLog"

    try {
        WriteLog "Invoking token request..."
        $response = Invoke-RestMethod -Uri $identityUrl -Method Post -ContentType "application/x-www-form-urlencoded" -Body $bodyParams -ErrorAction Stop 
        
        if ($response.access_token) {
            WriteLog "✅ Successfully retrieved access token"
            return $response.access_token
        } else {
            WriteLog "❌ Failed to retrieve access token. Response: $($response | ConvertTo-Json)" -err
            exit 1
        }
    }
    catch {
        WriteLog "❌ Error getting access token: $($_.Exception.Message)" -err
        WriteLog "Check identity URL: $identityUrl and external app credentials." -err
        
        if ($_.Exception.Response) {
            try {
                $errorResponseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponseStream)
                $responseBody = $reader.ReadToEnd()
                WriteLog "Full error response body: $responseBody" -err
            } catch {
                WriteLog "Could not read error response: $($_.Exception.Message)" -err
            }
        }
        exit 1
    }
}

# Get access token
$accessToken = Get-OrchestratorAccessToken `
    -accountName $accountForApp `
    -applicationId $applicationId `
    -applicationSecret $applicationSecret `
    -applicationScope $applicationScope `
    -identityBaseUrl $identityServerRoot 

# Set up headers for API calls
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "X-UIPATH-TenantName" = $tenantlName
    "X-UIPATH-AccountName" = $accountForApp
    "Content-Type" = "application/json"
}
WriteLog "Headers configured for API calls"

# --- 2. Resolve IDs (Folder, Process, Robots/Machine) ---
Function Resolve-OrchestratorId {
    Param (
        [hashtable]$headers,
        [string]$endpoint,
        [string]$nameToResolve,
        [string]$filterProperty,
        [string]$idProperty
    )
    WriteLog "🔍 Resolving $endpoint '$nameToResolve'..."
    
    if ($endpoint -eq "Folders") {
        $uri = "$orchestratorApiBase/odata/Folders"
        WriteLog "Getting all folders: $uri"
        
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
            WriteLog "Retrieved $($response.value.Count) folders"
            
            $matchingFolder = $response.value | Where-Object { $_.($filterProperty) -eq $nameToResolve }
            if ($matchingFolder) {
                WriteLog "✅ Found '$nameToResolve' ID: $($matchingFolder.($idProperty))"
                return $matchingFolder.($idProperty)
            } else {
                WriteLog "❌ Could not find folder '$nameToResolve'. Available folders:" -err
                $response.value | ForEach-Object { WriteLog "  - $($_.DisplayName) (ID: $($_.Id))" }
                exit 1
            }
        }
        catch {
            WriteLog "❌ Error getting folders: $($_.Exception.Message)" -err
            exit 1
        }
    } else {
        $uri = "$orchestratorApiBase/odata/$endpoint`?`$filter=($filterProperty eq '$nameToResolve')"
        WriteLog "Resolution URI: $uri"

        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
            if ($response.value -and $response.value.Count -gt 0) {
                WriteLog "✅ Found '$nameToResolve' ID: $($response.value[0].($idProperty))"
                return $response.value[0].($idProperty)
            } else {
                WriteLog "❌ Could not find $endpoint '$nameToResolve'" -err
                exit 1
            }
        }
        catch {
            WriteLog "❌ Error resolving $endpoint '$nameToResolve': $($_.Exception.Message)" -err
            exit 1
        }
    }
}

# Resolve folder first to get the OrganizationUnitId
WriteLog "📁 Resolving folder organization unit..."
$folderId = Resolve-OrchestratorId -headers $headers -endpoint "Folders" -nameToResolve $folder_organization_unit -filterProperty "DisplayName" -idProperty "Id"

# Add the OrganizationUnitId header for folder-scoped requests
$headers."X-UIPATH-OrganizationUnitId" = $folderId
WriteLog "Updated headers with folder context"

# Resolve process
WriteLog "⚙️ Resolving process..."
$processKey = Resolve-OrchestratorId -headers $headers -endpoint "Processes" -nameToResolve $processName -filterProperty "ProcessKey" -idProperty "Key"

# Robot ID resolution
$targetRobotIds = @()
if ($robots -ne "") {
    WriteLog "🤖 Resolving robot IDs..."
    $robotNames = $robots.Split(',') | ForEach-Object { $_.Trim() }
    foreach ($robotName in $robotNames) {
        $robotId = Resolve-OrchestratorId -headers $headers -endpoint "Robots" -nameToResolve $robotName -filterProperty "Name" -idProperty "Id"
        if ($robotId) { $targetRobotIds += $robotId }
    }
    if ($targetRobotIds.Count -eq 0) {
        WriteLog "❌ No valid Robot IDs found for names: $robots" -err
        exit 1
    }
    WriteLog "✅ Resolved Robot IDs: $($targetRobotIds -join ', ')"
} else {
    WriteLog "❌ Robot names must be specified for job execution" -err
    exit 1
}

# --- 3. Construct Start Job Request Body ---
WriteLog "📝 Constructing job start request..."
$startJobBody = @{
    "startInfo" = @{
        "ReleaseKey" = $processKey
        "Strategy" = "Specific"
        "RobotIds" = $targetRobotIds
        "JobsCount" = [int]$jobscount
        "JobPriority" = $priority
        "InputArguments" = ""
    }
} | ConvertTo-Json -Depth 10

WriteLog "Job request body prepared"

# --- 4. Start the Job ---
$startJobUri = "$orchestratorApiBase/odata/Jobs/UiPath.Server.Configuration.OData.StartJobs"
WriteLog "🚀 Starting job via API: $startJobUri"

try {
    $startJobResponse = Invoke-RestMethod -Uri $startJobUri -Method Post -Headers $headers -Body $startJobBody -ErrorAction Stop
    WriteLog "✅ Job started successfully"
    
    if ($startJobResponse.value -and $startJobResponse.value.Count -gt 0) {
        $jobIds = $startJobResponse.value | ForEach-Object { $_.Id }
        WriteLog "Started job IDs: $($jobIds -join ', ')"
        
        # --- 5. Wait for job completion if requested ---
        if ($wait -eq "true") {
            WriteLog "⏳ Waiting for job completion (timeout: $timeout seconds)..."
            $timeoutSeconds = [int]$timeout
            $startTime = Get-Date
            $allJobsCompleted = $false
            
            do {
                Start-Sleep -Seconds 10
                $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds
                
                WriteLog "Checking job status... (elapsed: $([math]::Round($elapsedSeconds))s)"
                
                $allCompleted = $true
                $jobStatuses = @()
                
                foreach ($jobId in $jobIds) {
                    try {
                        $jobStatusUri = "$orchestratorApiBase/odata/Jobs($jobId)"
                        $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Method Get -Headers $headers -ErrorAction Stop
                        
                        $status = $jobStatus.State
                        $jobStatuses += "Job $jobId : $status"
                        
                        if ($status -notin @("Successful", "Failed", "Stopped", "Faulted")) {
                            $allCompleted = $false
                        }
                    }
                    catch {
                        WriteLog "❌ Error checking job $jobId status: $($_.Exception.Message)" -err
                        $allCompleted = $false
                    }
                }
                
                WriteLog "Current status: $($jobStatuses -join ', ')"
                
                if ($allCompleted) {
                    $allJobsCompleted = $true
                    WriteLog "✅ All jobs completed"
                } elseif ($elapsedSeconds -ge $timeoutSeconds) {
                    WriteLog "⏰ Timeout reached ($timeout seconds)" -err
                    break
                }
                
            } while (-not $allJobsCompleted)
            
            # Check final job results
            if ($fail_when_job_fails -eq "true") {
                $hasFailedJobs = $false
                foreach ($jobId in $jobIds) {
                    try {
                        $jobStatusUri = "$orchestratorApiBase/odata/Jobs($jobId)"
                        $jobStatus = Invoke-RestMethod -Uri $jobStatusUri -Method Get -Headers $headers -ErrorAction Stop
                        
                        if ($jobStatus.State -in @("Failed", "Faulted")) {
                            WriteLog "❌ Job $jobId failed with state: $($jobStatus.State)" -err
                            $hasFailedJobs = $true
                        } else {
                            WriteLog "✅ Job $jobId completed with state: $($jobStatus.State)"
                        }
                    }
                    catch {
                        WriteLog "❌ Error getting final status for job $jobId : $($_.Exception.Message)" -err
                        $hasFailedJobs = $true
                    }
                }
                
                if ($hasFailedJobs) {
                    WriteLog "❌ One or more jobs failed. Exiting with error." -err
                    exit 1
                }
            }
        }
        
        WriteLog "🎉 Job execution completed successfully!"
        exit 0
        
    } else {
        WriteLog "❌ No jobs were started. Response: $($startJobResponse | ConvertTo-Json)" -err
        exit 1
    }
}
catch {
    WriteLog "❌ Error starting job: $($_.Exception.Message)" -err
    
    if ($_.Exception.Response) {
        try {
            $errorResponseStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorResponseStream)
            $responseBody = $reader.ReadToEnd()
            WriteLog "Full error response: $responseBody" -err
        } catch {
            WriteLog "Could not read error response: $($_.Exception.Message)" -err
        }
    }
    exit 1
}
