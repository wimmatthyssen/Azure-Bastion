<#
.SYNOPSIS

A script used to set the required NSG Inbound security rules on a Target VM subnet for Azure Bastion connectivity.

.DESCRIPTION

A script used to set the required NSG Inbound security rules on a Target VM subnet for Azure Bastion connectivity.
The script will do all of the following:

Check if the PowerShell window is running as Administrator (when not running from Cloud Shell), otherwise the Azure PowerShell script will be exited.
Suppress breaking change warning messages.
Create the Target VM Subnet NSG if it does not exist.
Store the Target VM Subnet NSG in a variable.
Add inbound rule 1 to allow ingress RDP traffic from AzureBastionSubnet to the Target VM Subnet NSG, if it not already exists.
Add inbound rule 2 to allow ingress SSH traffic from AzureBastionSubnet to the Target VM Subnet NSG, if it not already exists.
Add inbound rule 3 to deny all other inbound virtual network traffic to the Target VM Subnet NSG, if it not already exists.
Update the NSG with the new inbound rules.

.NOTES

Filename:       Set-AzureBastion-NSG-Inbound-security-rules-on-Target-VM-Subnet.ps1
Created:        10/08/2022
Last modified:  10/08/2022
Author:         Wim Matthyssen
Version:        1.0
PowerShell:     Azure Cloud Shell or Azure PowerShell
Requires:       PowerShell Az (v5.9.0) and Az.Network (v4.7.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "As Is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "<xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx>" (if not using the default tenant)
Set-AzContext -Subscription "<SubscriptionName>" (if not using the default subscription)
.\Set-AzureBastion-NSG-Inbound-security-rules-on-Target-VM-Subnet <"your NSG name here"> <"your NSG resource group name here"> 

-> .\Set-AzureBastion-NSG-Inbound-security-rules-on-Target-VM-Subnet nsg-tst-myh-app-01 rg-tst-myh-networking-01

.LINK

https://wmatthyssen.com/2022/08/11/azure-bastion-set-azure-bastion-nsg-inbound-security-rules-on-the-target-vm-subnet-with-azure-powershell/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $nsgNameTargetVMSubnet -> Name of the NSG associated to the Target VM Subnet
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $nsgNameTargetVMSubnet,
    # $rgNameNetworking -> Name of the resource group holding the NSG
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $rgNameNetworking
)

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$inboundRule1Name = #<your RDP inbound rule here> The name of the RDP inbound rule. Example: "Allow_RDP_3389_AzureBastionSubnet_Inbound"
$inboundRule2Name = #<your SSH inbound rule here> The name of the SSH inbound rule. Example: "Allow_SSH_22_AzureBastionSubnet_Inbound"
$inboundRule3Name = #<your deny all other traffic inbound rule here> The name of the deny all other traffic inbound rule. Example: "Deny_Any_Other_Inbound_Traffic_Inbound"

$inboundRule1Priority = #<your RDP inbound rule priority here> The priority of the RDP inbound rule. Example: "100"
$inboundRule2Priority = #<your SSH inbound rule priority here> The priority of the SSH inbound rule. Example: "110"
$inboundRule3Priority = #<your deny all other traffic inbound rule priority here> The priority of the deny all other traffic inbound rule. Example: "900"

$bastionSubnetAddressRange = "10.1.1.128/26"

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
    Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will need around 1 minute to complete" + $writeSeperatorSpaces + $currentTime)`
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
        Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will need around 1 minute to complete" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine 
        }
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Suppress breaking change warning messages

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Create the Target VM Subnet NSG if it does not exist

try {
    Get-AzNetworkSecurityGroup -Name $nsgNameTargetVMSubnet -ResourceGroupName $rgNameNetworking -ErrorAction Stop | Out-Null 
} catch {
    New-AzNetworkSecurityGroup -Name $nsgNameTargetVMSubnet -ResourceGroupName $rgNameNetworking -Location $region -Force | Out-Null 
}

Write-Host ($writeEmptyLine + "# NSG $nsgNameTargetVMSubnet available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Store the Target VM Subnet NSG in a variable

$nsg = Get-AzNetworkSecurityGroup -Name $nsgNameTargetVMSubnet -ResourceGroupName $rgNameNetworking

Write-Host ($writeEmptyLine + "# NSG $nsgNameTargetVMSubnet stored in a variable" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Add inbound rule 1 to allow Ingress RDP traffic from AzureBastionSubnet to the Target VM Subnet NSG, if it not already exists

$inboundRule1Exists = $nsg | Get-AzNetworkSecurityRuleConfig -Name $inboundRule1Name -ErrorAction SilentlyContinue

if ($inboundRule1Exists) {
    Write-Host ($writeEmptyLine + "# Inbound security rule $inboundRule1Name already exists" + $writeSeperatorSpaces + $currentTime) `
    -foregroundcolor $foregroundColor2 $writeEmptyLine
} else {
    $nsg | Add-AzNetworkSecurityRuleConfig -Name $inboundRule1Name -Description $inboundRule1Name -Access Allow -Protocol TCP -Direction Inbound -Priority $inboundRule1Priority `
    -SourceAddressPrefix $bastionSubnetAddressRange -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 | Out-Null 

    Write-Host ($writeEmptyLine + "# Inbound security rule added to allow RDP from AzureBastionSubnet to NSG $nsgNameTargetVMSubnet" + $writeSeperatorSpaces + $currentTime) `
    -foregroundcolor $foregroundColor2 $writeEmptyLine
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Add inbound rule 2 to allow Ingress SSH traffic from AzureBastionSubnet to the Target VM Subnet NSG, if it not already exists

$inboundRule2Exists = $nsg | Get-AzNetworkSecurityRuleConfig -Name $inboundRule2Name -ErrorAction SilentlyContinue

if ($inboundRule2Exists) {
    Write-Host ($writeEmptyLine + "# Inbound security rule $inboundRule2Name already exists" + $writeSeperatorSpaces + $currentTime) `
    -foregroundcolor $foregroundColor2 $writeEmptyLine
} else {
    $nsg | Add-AzNetworkSecurityRuleConfig -Name $inboundRule2Name -Description $inboundRule2Name -Access Allow -Protocol TCP -Direction Inbound -Priority $inboundRule2Priority `
    -SourceAddressPrefix $bastionSubnetAddressRange -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 22 | Out-Null 
    
    Write-Host ($writeEmptyLine + "# Inbound security rule added to allow SSH from AzureBastionSubnet to NSG $nsgNameTargetVMSubnet" + $writeSeperatorSpaces + $currentTime) `
    -foregroundcolor $foregroundColor2 $writeEmptyLine
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Add inbound rule 3 to deny all other inbound virtual network traffic to the Target VM Subnet NSG, if it not already exists

$inboundRule3Exists = $nsg | Get-AzNetworkSecurityRuleConfig -Name $inboundRule3Name -ErrorAction SilentlyContinue

if ($inboundRule3Exists) {
    Write-Host ($writeEmptyLine + "# Inbound security rule $inboundRule3Name already exists" + $writeSeperatorSpaces + $currentTime) `
    -foregroundcolor $foregroundColor2 $writeEmptyLine
} else {
    $nsg | Add-AzNetworkSecurityRuleConfig -Name $inboundRule3Name -Description $inboundRule3Name -Access Deny -Protocol * -Direction Inbound -Priority $inboundRule3Priority `
    -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange * | Out-Null 
        
    Write-Host ($writeEmptyLine + "# Inbound security rule added to deny any other traffic to NSG $nsgNameTargetVMSubnet" + $writeSeperatorSpaces + $currentTime) `
    -foregroundcolor $foregroundColor2 $writeEmptyLine
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Update the NSG with the new inbound rules

$nsg | Set-AzNetworkSecurityGroup | Out-Null 

Write-Host ($writeEmptyLine + "# NSG $nsgNameTargetVMSubnet updated" + $writeSeperatorSpaces + $currentTime) `
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
