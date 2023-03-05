<#
.SYNOPSIS

A script used to upgrade Azure Bastion Basic SKU to Standard SKU with an instance count of two.

.DESCRIPTION

A script used to upgrade Azure Bastion Basic SKU to Standard SKU with an instance count of two.
The script will do all of the following:

Remove the breaking change warning messages.
Change the current context to the subscription holding the Azure Bastion host, if the subscription exists; otherwise, exit the script.
Save the Bastion host if it exists in the subscription as a variable and check if it uses the Basic SKU; if so, exit the script, otherwise the script will continue.
Store the specified set of Azure Bastion host tags in a hash table.
Upgrade Bastion to Standard SKU if Basic SKU is currently set.

** Keep in mind upgrading Bastion to the Standard SKU can take up to 6 minutes. **

.NOTES

Filename:       Upgrade-AzureBastion-Basic-SKU-to-Standard-SKU.ps1
Created:        03/10/2022
Last modified:  05/03/2023
Author:         Wim Matthyssen
Version:        2.0
PowerShell:     Azure Cloud Shell or Azure PowerShell
Requires:       PowerShell Az (v8.1.0) and Az.Network (v4.18.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "as is" with no warranties.
.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "<xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx>" (if not using the default tenant)
.\Upgrade-AzureBastion-Basic-SKU-to-Standard-SKU <"your azure bastion host subscription name here"> <"your bastion host name here"> 

-> .\Upgrade-AzureBastion-Basic-SKU-to-Standard-SKU sub-hub-myh-management-01 bas-hub-myh-01

.LINK

https://wmatthyssen.com/2022/10/04/azure-bastion-upgrade-basic-sku-to-standard-sku-with-azure-powershell/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $subscriptionName -> Name of the subscription holding the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $subscriptionInputName,
    # $bastionName -> Name of the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $bastionInputName
)

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$bastionSkuStandard = "Standard"
$bastionScaleUnit = "2"

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true" | Out-Null

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script started

Write-Host ($writeEmptyLine + "# Script started. Without errors, it can take up to 8 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to the subscription holding the Azure Bastion host, if the subscription exists; otherwise, exit the script

Get-AzSubscription -SubscriptionName $subscriptionInputName -ErrorVariable subscriptionNotPresent -ErrorAction SilentlyContinue | Out-Null

if ($subscriptionNotPresent) {
    Write-Host ($writeEmptyLine + "# Subscription with name $subscriptionInputName does not exist in the current tenant" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return 
} else {
    Set-AzContext -Subscription $subscriptionInputName | Out-Null
    Write-Host ($writeEmptyLine + "# Subscription with name $subscriptionInputName in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine 
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Save the Bastion host if it exists in the subscription as a variable and check if it uses the Basic SKU; if so, the script will continue; otherwise, exit the script

$bastionObject = Get-AzBastion | Where-Object Name -Match $bastionInputName

# Check if a Bastion host exists in the subscription; otherwise, exit the script
if ($null -eq $bastionObject){
    Write-Host ($writeEmptyLine + "# No Bastion host exists in the current subscription, please select the correct context and rerun the script" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return
} 

# Check if the Bastion host is running the Basic SKU; otherwise, exit the script
if ($bastionObject.SkuText.Contains("Standard")) {
    Write-Host ($writeEmptyLine + "# Bastion host already using the Standard SKU" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return
}

Write-Host ($writeEmptyLine + "# Bastion host variable created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Store the specified set of Azure Bastion host tags in a hash table

$bastionTags = (Get-AzResource -ResourceGroupName $bastionObject.ResourceGroupName -ResourceName $bastionObject.Name).Tags

Write-Host ($writeEmptyLine + "# Specified set of tags available to add" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Upgrade Bastion to Standard SKU if Basic SKU is currently set

$bastionName = $bastionObject.Name

# Upgrade Bastion host to Standard SKU and 2 Scale Units
Set-AzBastion -InputObject $bastionObject -Sku $bastionSkuStandard -ScaleUnit $bastionScaleUnit -Force | Out-Null

# Set tags on Bastion host
Set-AzBastion -InputObject $bastionObject -Tag $bastionTags -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName running with Standard SKU and $bastionScaleUnit Scale Units" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
