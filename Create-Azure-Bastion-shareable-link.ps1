<#

.SYNOPSIS

A script used to create an Azure Bastion shareable link for a specific VM.

.DESCRIPTION

A script used to create an Azure Bastion shareable link for a specific VM.
The script will do all of the following:

Remove the breaking change warning messages.
Validate if the target VM exists, and if so, find the subscription it belongs to; otherwise, exit the script.
Validate if an Azure Bastion host exists, and if so, save the Bastion host as a variable if it uses the Standard SKU; otherwise, exit the script.
Create and get the shareable link for the VM using the REST API.
Get the shareable link for the VM using the REST API.

.NOTES

Filename:       Create-Azure-Bastion-shareable-link.ps1
Created:        20/01/2023
Last modified:  20/01/2023
Author:         Wim Matthyssen
Version:        1.0
PowerShell:     Azure PowerShell
Requires:       PowerShell Az (v9.3.0)
CLI:            Azure CLI
Requires:       azure-cli 2.45.0
Action:         Change variables as needed to fit your needs.
Disclaimer:     This script is provided "as is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx" (if not using the default tenant)
.\Create-Azure-Bastion-shareable-link.ps1 -VMName <"your VM name here">

-> Create-Azure-Bastion-shareable-link.ps1 -VMName swpdc003

.LINK

https://wmatthyssen.com/2023/01/11/azure-bastion-connect-to-an-azure-vm-without-accessing-the-azure-portal-by-using-a-shareable-link/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $vmName -> Name of the target Azure Windows VM
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $vmName
)

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$subscriptionNameVM = ""
$vmObject = $null

$httpsUriStart = "https://management.azure.com/subscriptions/"
$createApiVersion = "createShareableLinks?api-version=2022-07-01"
$getApiVersion = "GetShareableLinks?api-version=2022-07-01"
$authenticationType = "Bearer"
$method = "Post"
$contentType = "application/json"

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages

Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true | Out-Null
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script started

Write-Host ($writeEmptyLine + "# Script started. Without errors, it takes up to 1 minute to complete" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Validate if the target VM exists, and if so, find the subscription it belongs to; otherwise, exit the script

$allSubscriptions = Get-AzSubscription | Where-Object { "Enabled" -eq $_.State}

if ($allSubscriptions){
    foreach ($subscription in $allSubscriptions){
        Set-AzContext -Subscription $Subscription.Name | Out-Null
        $vmObject = Get-AzVM -Name $vmName
        if ($vmObject) {
            $subscriptionNameVM = $subscription.Name
            Write-Host ($writeEmptyLine + "# Target VM $vmName found in subscription $subscriptionNameVM" + $writeSeperatorSpaces + $currentTime)`
            -foregroundcolor $foregroundColor2 $writeEmptyLine
            break 
        }
    }
}

if (-not $vmObject) {
    Write-Host ($writeEmptyLine + "# VM not found" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host ($writeEmptyLine + "# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return
}

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Validate if an Azure Bastion host exists, and if so, save the Bastion host as a variable if it uses the Standard SKU; otherwise, exit the script

$bastionObject = Get-AzBastion 
$bastionName = ($bastionObject).Name

if ($null -eq $bastionObject){
    Write-Host ($writeEmptyLine + "# There is no Bastion host included in the current subscription" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host ($writeEmptyLine + "# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return
} else {
    if ($bastionObject.SkuText.Contains("Basic")) {
        Write-Host ($writeEmptyLine + "# Bastion host runs with the Basic SKU, please upgrade to Standard SKU" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor3 $writeEmptyLine
        Start-Sleep -s 3
        Write-Host ($writeEmptyLine + "# Press any key to exit the script ..." + $writeEmptyLine)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine;
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
        return
    } else {
        Write-Host ($writeEmptyLine + "# Bastion host $bastionName exists in the current subscription; the script will continue" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor2 $writeEmptyLine
    }
}

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create the shareable link for the VM using the REST API

# Get subscription ID
$subscriptionObject = Get-AzContext | Select-Object Subscription 
$subscriptionID = $subscriptionObject.Subscription.Id

# Get Bastion parameters
$bastionResourceGroupName = ($bastionObject).ResourceGroupName

# Create REST API parameters
$uri = $httpsUriStart + $subscriptionID + "/resourceGroups/$($bastionResourceGroupName)/providers/Microsoft.Network/bastionHosts/$bastionName/$createApiVersion"
$token = (Get-AzAccessToken).Token | ConvertTo-SecureString -AsPlainText -Force
$body = @{vms = @(@{vm = @{id = $(($vmObject).Id) }})} | ConvertTo-Json -Depth 10

# Send an HTTP or HTTPS request to a REST API endpoint
Invoke-WebRequest -Uri $uri -Authentication $authenticationType -Token $token -Method $method -Body $body -ContentType $contentType | Out-Null

# Wait for the link to be created. This is to avoid the error "The link is not ready yet. Please try again later."
Write-Host ($writeEmptyLine + "# Waiting for the shareable link for VM $vmName to be created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

Start-Sleep -Seconds 5

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Get the shareable link for the VM using the REST API

# Get REST API parameters
$uri = $httpsUriStart + $subscriptionID + "/resourceGroups/$($bastionResourceGroupName)/providers/Microsoft.Network/bastionHosts/$bastionName/$getApiVersion"

$getShareableLink = Invoke-RestMethod -Uri $uri -Authentication $authenticationType -Token $token -Method $method -Body $body -ContentType $contentType 
$shareableLink = $getShareableLink.value.bsl

Write-Host ($writeEmptyLine + "# Shareable link for VM $vmName available: $shareableLink" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------