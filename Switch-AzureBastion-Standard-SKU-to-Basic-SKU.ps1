<#
.SYNOPSIS

A script used to switch an Azure Bastion host with Standard SKU to the Basic SKU.

.DESCRIPTION

A script used to switch an Azure Bastion host with Standard SKU to the Basic SKU.
The script will do all of the following:

Check if the PowerShell window is running as Administrator (when not running from Cloud Shell), otherwise the Azure PowerShell script will be exited.
Suppress breaking change warning messages.
Create Bastion resource variable for later use.
Store the specified set of Azure Bastion host tags in a hash table.
Delete Azure Bastion host with Standard SKU.
Redeploy same Azure Bastion host with Basic SKU.
Lock the Azure Bastion resource group with a CanNotDelete lock.

** Keep in mind running this script can take up to 12 minutes. **
** If you have a resource lock on the resource group holding the bastion host, remove it temporarily while running the script **

.NOTES

Filename:       Switch-AzureBastion-Standard-SKU-to-Basic-SKU.ps1
Created:        04/10/2022
Last modified:  06/10/2022
Author:         Wim Matthyssen
Version:        1.2
PowerShell:     Azure Cloud Shell or Azure PowerShell
Requires:       PowerShell Az (v8.1.0) and Az.Network (v4.18.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "As Is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "<xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx>" (if not using the default tenant)
Set-AzContext -Subscription "<SubscriptionName>" (if not using the default subscription)
.\Switch-AzureBastion-Standard-SKU-to-Basic-SKU.ps1 <"your Bastion host name here"> 

-> .\Switch-AzureBastion-Standard-SKU-to-Basic-SKU.ps1 bas-hub-myh-01

.LINK

https://wmatthyssen.com/2022/10/05/azure-bastion-switch-standard-sku-to-basic-sku-with-azure-powershell/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $bastionName -> Name of the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $bastionName
)

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$bastionSkuBasic = "Basic"

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
    Write-Host ($writeEmptyLine + "# Script started. Without any errors, it can take up to 12 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
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
        Write-Host ($writeEmptyLine + "# Script started. Without any errors, it can take up to 12 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
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

## Store the specified set of Azure Bastion host tags in a hash table

$bastionTags = (Get-AzResource -ResourceGroupName $bastion.ResourceGroupName -ResourceName $bastion.Name).Tags

Write-Host ($writeEmptyLine + "# Specified set of tags available to add" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Delete Bastion host with Standard SKU

$bastionName = $bastion.Name

Remove-AzBastion -InputObject $bastion -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName temporarily removed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Redeploy Bastion host with Basic SKU

$pipNameBastion = Get-AzPublicIpAddress -ResourceGroupName $bastion.ResourceGroupName
$vnetName = Get-AzVirtualNetwork | ForEach-Object {if($_.Subnets.Name.Contains("AzureBastionSubnet")){return $_.Name}}
$rgNameNetworking = Get-AzVirtualNetwork | ForEach-Object {if($_.Subnets.Name.Contains("AzureBastionSubnet")){return $_.ResourceGroupName }}

# Redeploy Bastion host with Basic SKU
New-AzBastion -ResourceGroupName $bastion.ResourceGroupName -Name $bastion.Name -PublicIpAddress $pipNameBastion -VirtualNetworkRgName $rgNameNetworking `
-VirtualNetworkName $vnetName -Sku $bastionSkuBasic | Out-Null

# Set tags on Bastion host
Set-AzBastion -InputObject $bastion -Tag $bastionTags -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName with $bastionSkuBasic SKU available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Lock the Azure Bastion resource group with a CanNotDelete lock

$rgNameBastion = $bastion.ResourceGroupName
$lock = Get-AzResourceLock -ResourceGroupName $bastion.ResourceGroupName

if ($null -eq $lock){
    New-AzResourceLock -LockName DoNotDeleteLock -LockLevel CanNotDelete -ResourceGroupName $bastion.ResourceGroupName -LockNotes "Prevent $rgNameBastion from deletion" -Force | Out-Null
    } 

Write-Host ($writeEmptyLine + "# Resource group $rgNameBastion locked" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
