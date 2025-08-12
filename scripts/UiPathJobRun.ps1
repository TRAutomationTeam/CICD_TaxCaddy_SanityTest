<#
.SYNOPSIS
    Run UiPath Orchestrator Job.

.DESCRIPTION
    This script is to run orchestrator job.

.PARAMETER processName
    orchestrator process name to run.

.PARAMETER uriOrch
    The URL of Orchestrator.

.PARAMETER tenantlName
    The tenant name

.PARAMETER accountForApp
    The Orchestrator CloudRPA account name. Must be used together with id, secret and scope(s) for external application.

.PARAMETER applicationId
    The external application id. Must be used together with account, secret and scope(s) for external application.

.PARAMETER applicationSecret
    The external application secret. Must be used together with account, id and scope(s) for external application.

.PARAMETER applicationScope
    The space-separated list of application scopes. Must be used together with account, id and secret for external application.

.PARAMETER orchestrator_user
    On-premises Orchestrator admin user name who has a Role of Create Package.

.PARAMETER orchestrator_pass
    The password of the on-premises Orchestrator admin user.

.PARAMETER userKey
    User key for Cloud Platform Orchestrator

.PARAMETER accountName
    Account logical name for Cloud Platform Orchestrator

.PARAMETER input_path
    The full path to a JSON input file. Only required if the entry-point workflow has input parameters.

.PARAMETER jobscount
    The number of job runs. (default 1)

.PARAMETER result_path
    The full path to a JSON file or a folder where the result json file will be created.

.PARAMETER priority
    The priority of job runs. One of the following values: Low, Normal, High. (default Normal)

.PARAMETER robots
    The comma-separated list of specific robot names.

.PARAMETER folder_organization_unit
    The Orchestrator folder (organization unit).

.PARAMETER user
    The name of the user. This should be a machine user, not an orchestrator user. For local users, the format should be MachineName\UserName

.PARAMETER language
    The orchestrator language.

.PARAMETER machine
    The name of the machine.

.PARAMETER timeout
    The timeout for job executions in seconds. (default 1800)

.PARAMETER fail_when_job_fails
    The command fails when at least one job fails. (default true)

.PARAMETER wait
    The command waits for job runs completion. (default true)

.PARAMETER job_type
    The type of the job that will run. Values supported for this command: Unattended, NonProduction. For classic folders do not specify this argument

.PARAMETER disableTelemetry
    Disable telemetry data.

.PARAMETER uipathCliFilePath
    if not provided, the script will auto download the cli from uipath public feed. the script was testing on version 22.10.8432.18709. if provided, it is recommended to have cli version 22.10.8432.18709

.EXAMPLE
SYNTAX:
    .\UiPathJobRun.ps1 <process_name> <orchestrator_url> <orchestrator_tenant> [-input_path <input_path>] [-jobscount <jobscount>] [-result_path <result_path>] [-priority <priority>] [-robots <robots>]
    [-fail_when_job_fails <do_not_fail_when_job_fails>] [-timeout <timeout>] [-wait <do_not_wait>] [-orchestrator_user <orchestrator_user> -orchestrator_pass <orchestrator_pass>] [-userKey <auth_token> -accountName <account_name>]
    [-accountForApp <account_for_app> -applicationId <application_id> -applicationSecret <application_secret> -applicationScope <applicationScope>] [-folder_organization_unit <folder_organization_unit>] [-language <language>] [-user <robotUser>]
    [-machine <robotMachine>] [-job_type <Unattended, NonProduction>]

  Examples:

    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -orchestrator_pass -priority Low
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -orchestrator_pass -priority Normal -folder_organization_unit MyFolder
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -orchestrator_user admin -orchestrator_pass 123456 -orchestrator_pass -priority High -folder_organization_unit MyFolder
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -userKey a7da29a2c93a717110a82 -accountName myAccount -fail_when_job_fails false -timeout 0
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -userKey a7da29a2c93a717110a82 -accountName myAccount -orchestrator_pass -priority High -jobscount 3 -wait false -machine ROBOTMACHINE
    .\UiPathJobRun.ps1 "ProcessName" "https://cloud.uipath.com/" default -userKey a7da29a2c93a717110a82 -accountName myAccount -orchestrator_pass -priority Low -robots robotName -result_path C:\Temp
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -userKey a7da29a2c93a717110a82 -accountName myAccount -robots robotName -result_path C:\Temp\status.json
    .\UiPathJobRun.ps1 "ProcessName" "https://uipath-orchestrator.myorg.com" default -accountForApp accountForExternalApp -applicationId myExternalAppId -applicationSecret myExternalAppSecret -applicationScope "OR.Folders.Read OR.Settings.Read" -robots robotName -result_path C:\Temp\status.json

#>
Param (

    #Required
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$processName = "", #Process Name (pos. 0)           Required.
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$uriOrch = "", #Orchestrator URL (pos. 1)       Required. The URL of the Orchestrator instance.
    [Parameter(Mandatory = $true, Position = 2)]
    [string]$tenantlName = "", #Orchestrator Tenant (pos. 2)    Required. The tenant of the Orchestrator instance.

    #External Apps (Option 1)
    [string]$accountForApp = "", #The Orchestrator CloudRPA account name. Must be used together with id, secret and scope(s) for external application.
    [string]$applicationId = "", #Required. The external application id. Must be used together with account, secret and scope(s) for external application.
    [string]$applicationSecret = "", #Required. The external application secret. Must be used together with account, id and scope(s) for external application.
    [string]$applicationScope = "", #Required. The space-separated list of application scopes. Must be used together with account, id and secret for external application.

    #API Access - (Option 2)
    [string]$accountName = "", #Required. The Orchestrator CloudRPA account name. Must be used together with the refresh token and client id.
    [string]$userKey = "", #Required. The Orchestrator OAuth2 refresh token used for authentication. Must be used together with the account name and client id.

    #On prem UserName & Password - (Option 3)
    [string]$orchestrator_user = "", #Required. The Orchestrator username used for authentication. Must be used together with the password.
    [string]$orchestrator_pass = "", #Required. The Orchestrator password used for authentication. Must be used together with the username.

    [string]$input_path = "", #The full path to a JSON input file. Only required if the entry-point workflow has input parameters.
    [string]$jobscount = "", #The number of job runs. (default 1)
    [string]$result_path = "", #The full path to a JSON file or a folder where the result json file will be created.
    [string]$priority = "", #The priority of job runs. One of the following values: Low, Normal, High. (default Normal)
    [string]$robots = "", #The comma-separated list of specific robot names.
    [string]$folder_organization_unit = "", #The Orchestrator folder (organization unit).
    [string]$language = "", #The orchestrator language.
    [string]$user = "", #The name of the user. This should be a machine user, not an orchestrator user. For local users, the format should be MachineName\UserName
    [string]$machine = "", #The name of the machine.
    [string]$timeout = "", #The timeout for job executions in seconds. (default 1800)
    [string]$fail_when_job_fails = "", #The command fails when at least one job fails. (default true)
    [string]$wait = "", #The command waits for job runs completion. (default true)
    [string]$job_type = "", #The type of the job that will run. Values supported for this command: Unattended, NonProduction. For classic folders do not specify this argument
    [string]$disableTelemetry = "", #Disable telemetry data.
    [string]$uipathCliFilePath = "", #if not provided, the script will auto download the cli from uipath public feed. the script was testing on version 23.10.8753.32995.
    [string]$SpecificCLIVersion = "", #CLI version to auto download if uipathCliFilePath not provided
    [Parameter(ValueFromRemainingArguments = $true)]
    $remainingArgs

)
function WriteLog {
    Param ($message, [switch]$err)

    $now = Get-Date -Format "G"
    $line = "$now`t$message"
    $line | Add-Content $debugLog -Encoding UTF8
    if ($err) {
        Write-Host $line -ForegroundColor red
    }
    else {
        Write-Host $line
    }
}
#Running Path
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
#log file
$debugLog = "$scriptPath\orchestrator-job-run.log"

#Validate provided cli folder (if any)
if ($uipathCliFilePath -ne "") {
    $uipathCLI = "$uipathCliFilePath"
    if (-not(Test-Path -Path $uipathCLI -PathType Leaf)) {
        WriteLog "UiPath cli file path provided does not exist in the provided path $uipathCliFilePath.`r`nDo not provide uipathCliFilePath paramter if you want the script to auto download the cli from UiPath Public feed"
        exit 1
    }
}
else {
    #Verifying UiPath CLI installation

    if ($SpecificCLIVersion -ne "") {
        $cliVersion = $SpecificCLIVersion;
    }
    else {
        $cliVersion = "23.10.8753.32995"; #CLI Version (Script was tested on this latest version at the time)
    }

    $uipathCLI = "$scriptPath\uipathcli\$cliVersion\tools\
