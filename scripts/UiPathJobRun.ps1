<#
.SYNOPSIS 
    Run UiPath Orchestrator Job via Orchestrator API.

.DESCRIPTION 
    This script triggers an Orchestrator job using direct API calls (OAuth2 External Application authentication).
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
    [Parameter(Mandatory=$true)] # Make these mandatory as this is the chosen authentication method
    [string] $accountForApp = "", 
    [Parameter(Mandatory=$true)]
    [string] $applicationId = "", 
    [Parameter(Mandatory=$true)]
    [string] $applicationSecret = "", 
    [Parameter(Mandatory=$true)]
    [string] $applicationScope = "", 

    # Other job parameters, similar to before
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
        Add-Content -Path $debugLog -Value $logEntry
    } else {
        Write-Host $logEntry
        Add-Content -Path $debugLog -Value $logEntry
    }
}

# Running Path for log file
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$debugLog = "$scriptPath\orchestrator-job-run.log"

# Clear previous log file on each run for fresh logs
if (Test-Path $debugLog) {
    Remove-Item $debugLog -Force
}

WriteLog "Starting UiPath Orchestrator Job via API..."

# Define the base URL for Orchestrator OData API calls
# This correctly appends /orchestrator_ for Cloud Orchestrator API endpoints
$orchestratorApiBase = "$uriOrch/orchestrator_"
WriteLog "Orchestrator API Base for OData calls: $orchestratorApiBase"

# Determine the Identity Server Base URL from $uriOrch
# For UiPath Cloud, the Identity Server URL is typically the root domain.
# Example: if $uriOrch is "https://cloud.uipath.com/myaccount/mytenant",
# then $identityServerRoot should be "https://cloud.uipath.com"
$identityServerRoot = ""
if ($uriOrch -match "^(https?:\/\/[^\/]+)\/") {
    # Extract the base URL (e.g., https://cloud.uipath.com)
    $identityServerRoot = $Matches[1]
} else {
    # Fallback if regex doesn't match expected pattern (e.g., if $uriOrch is just a domain)
    # This might happen for on-prem if uriOrch is already the root Identity URL
    $identityServerRoot = $uriOrch
}
WriteLog "Determined Identity Server Root URL for token acquisition: $identityServerRoot"

# --- 1. Get Access Token from External Application Credentials ---
Function Get-OrchestratorAccessToken {
    Param (
        [string]$accountName,
        [string]$applicationId,
        [string]$applicationSecret,
        [string]$applicationScope,
        [string]$identityBaseUrl # This parameter now correctly expects the root Identity URL
    )
    WriteLog "Attempting to get access token for external application..."
    
    # This line is now correct as $identityBaseUrl should hold the correct root domain
    $identityUrl = "$($identityBaseUrl)/identity_/connect/token" 
    WriteLog "Identity URL for token: $identityUrl"

    # Define parameters as a hashtable. Invoke-RestMethod will convert this to x-www-form-urlencoded
    # when ContentType is set correctly.
    $bodyParams = @{
        "grant_type"    = "client_credentials";
        "client_id"     = $applicationId;
        "client_secret" = $applicationSecret;
        "scope"         = $applicationScope;
    }
    
    # For logging purposes, create a masked string that looks like form-urlencoded
    # Note: ConvertTo-Json here is ONLY for logging. The actual request uses $bodyParams directly.
    $maskedBodyForLog = "grant_type=client_credentials&client_id=$applicationId&client_secret=********&scope=$applicationScope"
    WriteLog "Token request body (masked): $maskedBodyForLog"

    try {
        WriteLog "Invoking Invoke-RestMethod for access token..."
        # Pass the hashtable directly as Body, and set ContentType to application/x-www-form-urlencoded
        $response = Invoke-RestMethod -Uri $identityUrl -Method Post -ContentType "application/x-www-form-urlencoded" -Body $bodyParams -ErrorAction Stop 
        
        WriteLog "Invoke-RestMethod for access token completed."
        if ($response.access_token) {
            WriteLog "Successfully retrieved access token."
            return $response.access_token
        } else {
            WriteLog "Failed to retrieve access token. Response: $($response | Out-String)" -err
            exit 1
        }
    }
    catch {
        WriteLog "Error getting access token: $($_.Exception.Message)" -err
        WriteLog "Check identity URL: $identityUrl and external app credentials." -err
        # Log the full error response if available from $_.Exception.Response
        if ($_.Exception.Response) {
            try {
                $errorResponseStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponseStream)
                $responseBody = $reader.ReadToEnd()
                WriteLog "Full error response body: $responseBody" -err
            } catch {
                WriteLog "Could not read full error response body: $($_.Exception.Message)" -err
            }
        }
        exit 1
    }
}

# IMPORTANT CHANGE: Pass the newly derived $identityServerRoot to the function
$accessToken = Get-OrchestratorAccessToken `
    -accountName $accountForApp `
    -applicationId $applicationId `
    -applicationSecret $applicationSecret `
    -applicationScope $applicationScope `
    -identityBaseUrl $identityServerRoot 

# CRITICAL FIX: Add X-UIPATH-AccountName header for Cloud Orchestrator
$headers = @{
    "Authorization" = "Bearer $accessToken"
    "X-UIPATH-TenantName" = $tenantlName
    "X-UIPATH-AccountName" = $accountForApp  # Required for Cloud Orchestrator
}
WriteLog "Initial headers set: $(ConvertTo-Json $headers)"

# --- 2. Resolve IDs (Folder, Process, Robots/Machine) ---
# This is crucial because StartJobs API takes IDs, not names.

Function Resolve-OrchestratorId {
    Param (
        [hashtable]$headers,
        [string]$endpoint, # e.g., "Folders", "Processes", "Robots", "Machines"
        [string]$nameToResolve,
        [string]$filterProperty, # e.g., "DisplayName", "Name"
        [string]$idProperty # e.g., "Id", "Key"
    )
    WriteLog "Resolving $endpoint '$nameToResolve'..."
    
    # For Folders, try to get all folders first, then filter locally
    if ($endpoint -eq "Folders") {
        $uri = "$orchestratorApiBase/odata/Folders"
        WriteLog "Getting all folders first: $uri"
        
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
            WriteLog "Retrieved $($response.value.Count) folders"
            
            # Filter locally for the folder we want
            $matchingFolder = $response.value | Where-Object { $_.($filterProperty) -eq $nameToResolve }
            if ($matchingFolder) {
                WriteLog "Found '$nameToResolve' ID: $($matchingFolder.($idProperty))"
                return $matchingFolder.($idProperty)
            } else {
                WriteLog "Could not find folder '$nameToResolve' in available folders:" -err
                $response.value | ForEach-Object { WriteLog "  - $($_.DisplayName) (ID: $($_.Id))" }
                exit 1
            }
        }
        catch {
            WriteLog "Error getting folders: $($_.Exception.Message)" -err
            if ($_.Exception.Response) {
                try {
                    $errorResponseStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorResponseStream)
                    $responseBody = $reader.ReadToEnd()
                    WriteLog "Full error response body from folder resolution: $responseBody" -err
                } catch {
                    WriteLog "Could not read full error response body: $($_.Exception.Message)" -err
                }
            }
            exit 1
        }
    } else {
        # For other endpoints, use the original logic but with proper headers
        $uri = "$orchestratorApiBase/odata/$endpoint`?`$filter=($filterProperty eq '$nameToResolve')"
        WriteLog "Resolution URI: $uri"
        WriteLog "Resolution Headers: $(ConvertTo-Json $headers)"

        try {
            WriteLog "Invoking Invoke-RestMethod for ID resolution..."
            $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
            WriteLog "Invoke-RestMethod for ID resolution completed."
            if ($response.value -and $response.value.Count -gt 0) {
                WriteLog "Found '$nameToResolve' ID: $($response.value[0].($idProperty))"
                return $response.value[0].($idProperty)
            } else {
                WriteLog "Could not find $endpoint '$nameToResolve'. Response: $($response | Out-String)" -err
                exit 1
            }
        }
        catch {
            WriteLog "Error resolving $endpoint '$nameToResolve': $($_.Exception.Message)" -err
            if ($_.Exception.Response) {
                try {
                    $errorResponseStream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($errorResponseStream)
                    $responseBody = $reader.ReadToEnd()
                    WriteLog "Full error response body from ID resolution: $responseBody" -err
                } catch {
                    WriteLog "Could not read full error response body: $($_.Exception.Message)" -err
                }
            }
            exit 1
        }
    }
}

# Resolve folder first to get the OrganizationUnitId for subsequent requests
$folderId = Resolve-OrchestratorId -headers $headers -endpoint "Folders" -nameToResolve $folder_organization_unit -filterProperty "DisplayName" -idProperty "Id"

# Add the OrganizationUnitId header for folder-scoped requests
$headers."X-UIPATH-OrganizationUnitId" = $folderId
WriteLog "Updated headers with X-UIPATH-OrganizationUnitId: $(ConvertTo-Json $headers)"

# Now resolve process with the updated headers
$processKey = Resolve-OrchestratorId -headers $headers -endpoint "Processes" -nameToResolve $processName -filterProperty "ProcessKey" -idProperty "Key"

# Robot/Machine ID resolution is more complex based on how you specify robots/machines
$targetRobotIds = @()
if ($robots -ne "") {
    $robotNames = $robots.Split(',') | ForEach-Object { $_.Trim() }
    WriteLog "Resolving Robot IDs for names: $robots"
    foreach ($robotName in $robotNames) {
        $robotId = Resolve-OrchestratorId -headers $headers -endpoint "Robots" -nameToResolve $robotName -filterProperty "Name" -idProperty "Id"
        if ($robotId) { $targetRobotIds += $robotId }
    }
    if ($targetRobotIds.Count -eq 0) {
        WriteLog "No valid Robot IDs found for names: $robots" -err
        exit 1
    }
    WriteLog "Resolved Robot IDs: $($targetRobotIds -join ', ')"
} elseif ($machine -ne "") {
    WriteLog "Specifying 'machine' alone for job execution often requires more advanced Orchestrator setup (e.g. elastic robots or using all robots on that machine)."
    WriteLog "For unattended jobs, specifying specific 'robots' is generally more straightforward for API calls."
    # If your setup requires finding robots via machine, you'd add that logic here.
    WriteLog "Using Machine: '$machine'. Script is currently designed to use 'robots' parameter primarily for specific targets." -err
    WriteLog "If 'machine' is required, implement logic to find robots associated with this machine here or modify StartInfo strategy." -err
    exit 1 # Exiting because the current script requires robots to be specified for specific strategy.
} else {
    WriteLog "Either 'robots' or 'machine' (or both) must be specified for job execution target." -err
    exit 1
}

# --- 3. Construct Start Job Request Body ---
$startJobBody = [ordered]@{
    "startInfo" = [ordered]@{
        "ReleaseKey" = $processKey; # This is the Process Key (the unique identifier for the process in Orchestrator)
        "Strategy" = "Specific"; # Can be 'Specific', 'All', 'ModernFolders', etc. 'Specific' uses RobotIds
        "RobotIds" = $targetRobotIds; # Use the resolved Robot IDs
        "JobsCount" = $jobscount;
        "JobPriority" = $priority;
        "InputArguments" = ""; # Default to empty string for no input args
    }
}

# Add input arguments if provided
if ($input_path -ne "") {
    if (Test-Path $input_path) {
        $inputArgs = Get-Content $input_path | Out-String
        # Validate JSON if needed
        try {
            $inputArgs | ConvertFrom-Json | Out-Null
            $startJobBody.startInfo.InputArguments = $inputArgs
            WriteLog "Input arguments loaded from '$input_path' and validated."
        } catch {
            WriteLog "Input arguments file '$input_path' does not contain valid JSON." -err
            exit 1
        }
    } else {
        WriteLog "Input arguments file not found at: $input_path" -err
        exit 1
    }
