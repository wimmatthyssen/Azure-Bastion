<#
.SYNOPSIS

A script used to switch an Azure Bastion host with Standard SKU to the Basic SKU.

.DESCRIPTION

A script used to switch an Azure Bastion host with Standard SKU to the Basic SKU.
The script will do all of the following:

Check if PowerShell runs as Administrator when not running from Cloud Shell; otherwise, exit the script.
Remove the breaking change warning messages.
Change the current context to the subscription holding the Azure Bastion host, if the subscription exists; otherwise, exit the script.
Save the Bastion host if it exists in the subscription as a variable and check if it uses the Basic SKU; if so, exit the script, otherwise the script will continue.
Check if the Bastion resource group has a resource lock; if so, exit the script.
Store the specified set of Azure Bastion host tags in a hash table.
Delete Azure Bastion host with Standard SKU.
Redeploy same Azure Bastion host with Basic SKU.
Lock the Azure Bastion resource group with a CanNotDelete lock.

** Keep in mind running this script can take up to 19 minutes. **
** If you have a resource lock on the resource group holding the bastion host, remove it temporarily while running the script. **

.NOTES

Filename:       Switch-AzureBastion-Standard-SKU-to-Basic-SKU.ps1
Created:        04/10/2022
Last modified:  03/03/2023
Author:         Wim Matthyssen
Version:        2.1
PowerShell:     Azure Cloud Shell or Azure PowerShell
Requires:       PowerShell Az (v8.1.0) and Az.Network (v4.18.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "as is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "<xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx>" (if not using the default tenant)
.\Switch-AzureBastion-Standard-SKU-to-Basic-SKU.ps1 <"your azure bastion host subscription name here"> <"your bastion host name here"> 

-> .\Switch-AzureBastion-Standard-SKU-to-Basic-SKU.ps1 sub-hub-myh-management-01 bas-hub-myh-01

.LINK

https://wmatthyssen.com/2022/10/05/azure-bastion-switch-standard-sku-to-basic-sku-with-azure-powershell/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $subscriptionName -> Name of the subscription holding the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $subscriptionName,
    # $bastionName -> Name of the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $bastionName
)

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$bastionSkuBasic = "Basic"
$bastionSkuStandard = "Standard"

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Check if PowerShell runs as Administrator when not running from Cloud Shell; otherwise, exit the script

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($PSVersionTable.Platform -eq "Unix") {
    Write-Host ($writeEmptyLine + "# Running in Cloud Shell" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine
    
    # Begin script execution
    Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will take around 19 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine    
} else {
    # Check if you are running PowerShell as an administrator; otherwise, return the script
    if ($isAdministrator -eq $false) {
        Write-Host ($writeEmptyLine + "# Please run PowerShell as Administrator" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor3 $writeEmptyLine
        Start-Sleep -s 3
        Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine;
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
        return
    } else {
        # Begin script execution if you are running as Administrator 
        Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will take around 19 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine 
    }
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages.

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to the subscription holding the Azure Bastion host, if the subscription exists; otherwise, exit the script

Get-AzSubscription -SubscriptionName $subscriptionName -ErrorVariable subscriptionNotPresent -ErrorAction SilentlyContinue

if ($subscriptionNotPresent) {
    Write-Host ($writeEmptyLine + "# Subscription with name $subscriptionName does not exist in the current tenant" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return 
} else {
    Set-AzContext -Subscription $subscriptionName | Out-Null
    Write-Host ($writeEmptyLine + "# Subscription with name $subscriptionName in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine 
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Save the Bastion host if it exists in the subscription as a variable and check if it uses the Basic SKU; if so, exit the script, otherwise the script will continue

$bastion = Get-AzBastion | Where-Object Name -Match $bastionName

# Check if a Bastion host exists in the subscription; otherwise, exit the script
if ($null -eq $bastion){
    Write-Host ($writeEmptyLine + "# No Bastion host exists in the current subscription, please select the correct context and rerun the script" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return
} 

# Check if the Bastion host is running the Standard SKU; otherwise, exit the script
if ($bastion.SkuText.Contains("Basic")) {
    Write-Host ($writeEmptyLine + "# Bastion host already using the Basic SKU" + $writeSeperatorSpaces + $currentTime)`
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

## Check if the Bastion resource group has a resource lock; if so, exit the script

$lock = Get-AzResourceLock -ResourceGroupName $bastion.ResourceGroupName
$rgNameBastion = $bastion.ResourceGroupName

if ($null -ne $lock){
    Write-Host ($writeEmptyLine + "# Bastion resource group has a resource lock; please remove it and rerun the script" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    return
    } 

Write-Host ($writeEmptyLine + "# Resource group $rgNameBastion has no resource lock; the script will continue" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Store the specified set of Azure Bastion host tags in a hash table

$bastionTags = (Get-AzResource -ResourceGroupName $bastion.ResourceGroupName -ResourceName $bastion.Name).Tags

Write-Host ($writeEmptyLine + "# Specified set of tags available to add" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Delete Bastion host with Standard SKU

Write-Host ($writeEmptyLine + "# Delete bastion host $bastionName with the $bastionSkuStandard SKU, which can take up to 8 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine

$bastionName = $bastion.Name

Remove-AzBastion -InputObject $bastion -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName temporarily removed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Redeploy Bastion host with Basic SKU

$pipNameBastion = Get-AzPublicIpAddress -ResourceGroupName $bastion.ResourceGroupName
$vnetName = Get-AzVirtualNetwork | ForEach-Object {if($_.Subnets.Name.Contains("AzureBastionSubnet")){return $_.Name}}
$rgNameNetworking = Get-AzVirtualNetwork | ForEach-Object {if($_.Subnets.Name.Contains("AzureBastionSubnet")){return $_.ResourceGroupName }}

Write-Host ($writeEmptyLine + "# Redeploy bastion host $bastionName with $bastionSkuBasic SKU, which can take up to 10 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine

# Redeploy Bastion host with Basic SKU
New-AzBastion -ResourceGroupName $bastion.ResourceGroupName -Name $bastion.Name -PublicIpAddress $pipNameBastion -VirtualNetworkRgName $rgNameNetworking `
-VirtualNetworkName $vnetName -Sku $bastionSkuBasic | Out-Null

# Set tags on Bastion host
Set-AzBastion -InputObject $bastion -Tag $bastionTags -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName with $bastionSkuBasic SKU available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Lock the Azure Bastion resource group with a CanNotDelete lock

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
