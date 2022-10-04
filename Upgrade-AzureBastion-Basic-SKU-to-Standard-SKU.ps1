<#
.SYNOPSIS

A script used to upgrade Azure Bastion Basic SKU to Standard SKU with an instance count of two.

.DESCRIPTION

A script used to upgrade Azure Bastion Basic SKU to Standard SKU with an instance count of two.
The script will do all of the following:

Check if the PowerShell window is running as Administrator (when not running from Cloud Shell), otherwise the Azure PowerShell script will be exited.
Suppress breaking change warning messages.
Create Bastion resource variable for later use.
Upgrade Bastion to Standard SKU if Basic SKU is currently set.

** Keep in mind upgrading Bastion to the Standard SKU can take up to 6 minutes. **

.NOTES

Filename:       Upgrade-AzureBastion-Basic-SKU-to-Standard-SKU.ps1
Created:        03/10/2022
Last modified:  03/10/2022
Author:         Wim Matthyssen
Version:        1.0
PowerShell:     Azure Cloud Shell or Azure PowerShell
Requires:       PowerShell Az (v8.1.0) and Az.Network (v4.18.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "As Is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "<xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx>" (if not using the default tenant)
Set-AzContext -Subscription "<SubscriptionName>" (if not using the default subscription)
.\Upgrade-AzureBastion-Basic-SKU-to-Standard-SKU <"your Bastion host name here"> 

-> .\Upgrade-AzureBastion-Basic-SKU-to-Standard-SKU bas-hub-myh-01

.LINK

https://wmatthyssen.com/2022/10/04/azure-bastion-upgrade-basic-sku-to-standard-sku-with-azure-powershell/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $bastionName -> Name of the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $bastionName
)

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$bastionSkuStandard = "Standard"
$bastionScaleUnit = "2"

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Red"
$foregroundColor2 = "Yellow"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Check if PowerShell runs as Administrator (when not running from Cloud Shell), otherwise exit the script

if ($PSVersionTable.Platform -eq "Unix") {
    Write-Host ($writeEmptyLine + "# Running in Cloud Shell" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine
    
    ## Start script execution    
    Write-Host ($writeEmptyLine + "# Script started. Without any errors, it can take up to 6 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine 
} else {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        ## Check if running as Administrator, otherwise exit the script
        if ($isAdministrator -eq $false) {
        Write-Host ($writeEmptyLine + "# Please run PowerShell as Administrator" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine
        Start-Sleep -s 3
        exit
        }
        else {

        ## If running as Administrator, start script execution    
        Write-Host ($writeEmptyLine + "# Script started. Without any errors, it can take up to 6 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine 
        }
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Suppress breaking change warning messages

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create Bastion resource variable

$bastion = Get-AzBastion | Where-Object Name -Match $bastionName

Write-Host ($writeEmptyLine + "# Bastion variable created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Upgrade Bastion to Standard SKU if Basic SKU is currenlty set

$bastionName = $bastion.Name

Set-AzBastion -InputObject $bastion -Sku $bastionSkuStandard -ScaleUnit $bastionScaleUnit -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName running with Standard SKU with $bastionScaleUnit Scale Units" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
