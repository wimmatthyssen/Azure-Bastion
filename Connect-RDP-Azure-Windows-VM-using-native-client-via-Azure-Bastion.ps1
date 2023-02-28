<#

.SYNOPSIS

A script used to RDP to a target Azure Windows VM using Tunneling from Azure Bastion with Azure CLI and PowerShell.

.DESCRIPTION

A script used to RDP to a target Azure Windows VM using Tunneling from Azure Bastion with Azure CLI and PowerShell.
The script will do all of the following:

Check if the PowerShell window is running as Administrator (when not running from Cloud Shell); otherwise, the Azure PowerShell script will be exited.
Remove the breaking change warning messages.
Change the current context to the subscription holding the Azure Bastion host.
Save the Bastion host as a variable.
Change the current context to the specified subscription holding the target VM.
RDP to the target VM using the native client through Azure Bastion.
Remote Desktop File "conn.rdp" will be removed when the RDP connection is terminated.

.NOTES

Filename:       Connect-RDP-Azure-Windows-VM-using-native-client-via-Azure-Bastion.ps1
Created:        26/02/2023
Last modified:  28/02/2023
Author:         Wim Matthyssen
Version:        1.2
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
.\Connect-RDP-Azure-Windows-VM-using-native-client-via-Azure-Bastion.ps1 <"your target VM Azure subscription name here"> <"your VM name here">

-> Connect-RDP-Azure-Windows-VM-using-native-client-via-Azure-Bastion.ps1 sub-hub-myh-management-01 swpadm025

.LINK

https://wmatthyssen.com/2023/02/27/connecting-to-an-azure-windows-vm-using-an-azure-powershell-script-and-native-client-via-azure-bastion/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $subscriptionName -> Name of the subscription of the target Azure Windows VM
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $subscriptionName,
    # $vmName -> Name of the target Azure Windows VM
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $vmName
)

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Red"
$foregroundColor2 = "Yellow"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Check if PowerShell runs as Administrator; otherwise, exit the script

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Check if you are running PowerShell as an administrator; otherwise, exit the script
if ($isAdministrator -eq $false) {
    Write-Host ($writeEmptyLine + "# Please run PowerShell as Administrator" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine
    Start-Sleep -s 3
    exit
} else {
    # Begin script execution if you are running as Administrator 
    Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will need around 1 minute to complete" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine 
    }

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to the subscription holding the Azure Bastion host

#<your subscription value hare> Replace with the name value of your Azure Bastion subscription. Example: "management" -> {$_.Name -like "*management"*"} 
$subNameBastion = Get-AzSubscription | Where-Object {$_.Name -like "*<your subscription value here>*"} 

Set-AzContext -SubscriptionId $subNameBastion.SubscriptionId | Out-Null 

Write-Host ($writeEmptyLine + "# Bastion host subscription in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Save the Bastion host as a variable

$bastion = Get-AzBastion

Write-Host ($writeEmptyLine + "# Bastion host variable created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to the specified subscription holding the target VM

Set-AzContext -Subscription $subscriptionName | Out-Null

Write-Host ($writeEmptyLine + "# Target VM subscription in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## RDP to the target VM using the native client through Azure Bastion

$vm = Get-AzVM -Name $vmName

# Azure CLI
az network bastion rdp --name $bastion.Name --resource-group $bastion.ResourceGroupName --target-resource-id $vm.Id --output none --only-show-errors

Write-Host ($writeEmptyLine + "# Please use the correct credentials to log in to the open Remote Desktop connection" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remote Desktop File "conn.rdp" will be removed when the RDP connection is terminated

Get-ChildItem | Where-Object Name -Like $rdpFileName | ForEach-Object { Remove-Item -LiteralPath $_.Name }

Write-Host ($writeEmptyLine + "# Remote Destkop File $rdpFileName removed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
