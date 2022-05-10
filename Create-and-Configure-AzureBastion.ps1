<#
.SYNOPSIS

A script used to create and configure Azure Bastion within the HUB spoke VNet.

.DESCRIPTION

A script used to create and configure Azure Bastion (basic SKU) within the HUB spoke VNet. 
The script will first store the set of specified tags into a hash table.
Then it will create a resource group for the Azure Bastion resources (if it not already exists).
Next it will create the AzureBastionSubnet (/26) with an associated network security group (NSG), which holds all the required inbound and outbound security rules (if it not already exists). 
If the AzureBastionSubnet exists but does not have an associated NSG, it will attach the newly created NSG. 
The script will also create a Public IP Address (PIP) for the Bastion host (if it not exists), and create the Bastion host (basic SKU), which can take up to 6 minutes (if it not exists). 
It will also set the log and metrics settings for the bastion resource if they don't exist. 
And at the end it will lock the Azure Bastion resource group with a CanNotDelete lock.

.NOTES

Filename:       Create-and-Configure-AzureBastion.ps1
Created:        01/06/2021
Last modified:  09/05/2022
Author:         Wim Matthyssen
Version:        2.1
PowerShell:     Azure Cloud Shell or Azure PowerShell
Requires:       PowerShell Az (v5.9.0) and Az.Network (v4.7.0) Module
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "As Is" with no warranties.

.EXAMPLE

Connect-AzAccount
.\Create-and-Configure-AzureBastion.ps1

.LINK

https://wmatthyssen.com/2022/01/14/azure-bastion-azure-PowerShell-deployment-script/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$spoke = "hub"
$region = #<your region here> The used Azure public region. Example: "westeurope"
$purpose = "bastion"

$rgBastion = #<your Bastion rg here> The new Azure resource group in which the new Bastion resource will be created. Example: "rg-hub-myh-bastion"
$rgNetworkSpoke = #<your VNet rg here> The Azure resource group in which your existing VNet is deployed. Example: "rg-hub-myh-networking"
$rgLogAnalyticsSpoke = #<your Log Analytics rg here> The Azure resource group your existing Log Analytics workspace is deployed. Example: "rg-hub-myh-management"

$logAnalyticsName = #<your Log Analytics workspace name here> The name of your existing Log Analytics workspace. Example: "law-hub-myh-01"

$vnetName = #<your VNet name here> The existing VNet in which the Bastion resource will be created. Example: "vnet-hub-myh-weu"
$subnetBastionName = "AzureBastionSubnet"
$subnetBastionAddress = #<your AzureBastionSubnet range here> The subnet must have a minimum subnet size of /26. Example: "10.1.1.128/26"
$nsgBastionName = #<your AzureBastionSubnet NSG name here> The name of the NSG associated with the AzureBastionSubnet. Example: "nsg-AzureBastionSubnet"
$nsgBastionDiagnosticsName = #<your NSG Bastion Diagnostics settings name here> The name of the NSG diagnostic settings for Bastion. Example: "diag-nsg-AzureBastionSubnet"

$bastionName = #<your name here> The name of the new Bastion resource. Example: "bas-hub-myh"

$pipBastionName = #<your Bastion PIP here> The public IP address of the Bastion resource. Example: "pip-bas-hub-myh"
$pipBastionAllocationMethod = "Static"
$pipBastionSku = "Standard"
$pipBastionDiagnosticsName = #<your PIP Bastion Diagnostics settings name here> The name of the PIP diagnostic settings for Bastion. Example: "diag-nsg-AzureBastionSubnet"

$bastionDiagnosticsName = #<your Bastion Diagnostics settings name here> The name of the new diagnostic settings for Bastion. Example: "diag-bas-hub-myh"

$tagSpokeName = #<your environment tag name here> The environment tag name you want to use. Example:"Env"
$tagSpokeValue = "$($spoke[0].ToString().ToUpper())$($spoke.SubString(1))"
$tagCostCenterName  = #<your costCenter tag name here> The costCenter tag name you want to use. Example:"CostCenter"
$tagCostCenterValue = #<your costCenter tag value here> The costCenter tag value you want to use. Example: "23"
$tagCriticalityName = #<your businessCriticality tag name here> The businessCriticality tag name you want to use. Example:"Criticality"
$tagCriticalityValue = #<your businessCriticality tag value here> The businessCriticality tag value you want to use. Example: "High"
$tagPurposeName  = #<your purpose tag name here> The purpose tag name you want to use. Example:"Purpose"
$tagPurposeValue = "$($purpose[0].ToString().ToUpper())$($purpose.SubString(1))" 
$tagVnetName = #<your VNet tag name here> The vnet tag name you want to use. Example:"VNet"

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
    Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will need around 10 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
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
        Write-Host ($writeEmptyLine + "# Script started. Without any errors, it will need around 10 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor1 $writeEmptyLine 
        }
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Suppress breaking change warning messages

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to use the Management subscription

$subNameTest = Get-AzSubscription | Where-Object {$_.Name -like "*management*"}
$tenant = Get-AzTenant | Where-Object {$_.Name -like "*$companyShortName*"}

Set-AzContext -TenantId $tenant.TenantId -SubscriptionId $subNameTest.SubscriptionId | Out-Null 

Write-Host ($writeEmptyLine + "# Management Subscription in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Store the specified set of tags in a hash table

$tags = @{$tagSpokeName=$tagSpokeValue;$tagCostCenterName=$tagCostCenterValue;$tagCriticalityName=$tagCriticalityValue;$tagPurposeName=$tagPurposeValue}

Write-Host ($writeEmptyLine + "# Specified set of tags available to add" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create a resource group for the Azure Bastion resources, if it not already exists. Add specified tags

try {
    Get-AzResourceGroup -Name $rgBastion -ErrorAction Stop | Out-Null
} catch {
    New-AzResourceGroup -Name $rgBastion.ToLower() -Location $region -Force | Out-Null
}

# Set tags Bastion resource group
Set-AzResourceGroup -Name $rgBastion -Tag $tags | Out-Null

Write-Host ($writeEmptyLine + "# Resource group $rgBastion available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create the AzureBastionSubnet with the network security group, if it not already exists. Add the required inbound and outbound security rules. Add specified tags and diagnostic settings

# Inbound rules

# Rule to allow Ingress Traffic from public Internet
$inboundRule1 = New-AzNetworkSecurityRuleConfig -Name "Allow_TCP_443_Internet_Inbound" -Description "Allow_TCP_443_Internet_Inbound" `
-Access Allow -Protocol TCP -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

# Rule to allow Ingress Traffic to Azure Bastion control plane
$inboundRule2 = New-AzNetworkSecurityRuleConfig -Name "Allow_TCP_443_GatewayManager_Inbound" -Description "Allow_TCP_443_GatewayManager_Inbound" `
-Access Allow -Protocol TCP -Direction Inbound -Priority 110 -SourceAddressPrefix GatewayManager -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

# Rule to allow Ingress Traffic to Azure Bastion control plane
$inboundRule3 = New-AzNetworkSecurityRuleConfig -Name "Allow_TCP_4443_GatewayManager_Inbound" -Description "Allow_TCP_4443_GatewayManager_Inbound" `
-Access Allow -Protocol TCP -Direction Inbound -Priority 120 -SourceAddressPrefix GatewayManager -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 4443

# Rule to allow Ingress Traffic from Azure Load Balancer
$inboundRule4 = New-AzNetworkSecurityRuleConfig -Name "Allow_TCP_443_AzureLoadBalancer_Inbound" -Description "Allow_TCP_443_AzureLoadBalancer_Inbound" `
-Access Allow -Protocol TCP -Direction Inbound -Priority 130 -SourceAddressPrefix AzureLoadBalancer -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

# Rule to allow Ingress Traffic to Azure Bastion data plane
$inboundRule5 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_8080_5701_BastionHostCommunication_Inbound" -Description "Allow_Any_8080_5701_BastionHostCommunication_Inbound" `
-Access Allow -Protocol * -Direction Inbound -Priority 140 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork `
-DestinationPortRange 8080,5701

# Rule to deny all other inbound virtual network traffic
$inboundRule6 = New-AzNetworkSecurityRuleConfig -Name "Deny_Any_Other_Traffic_Inbound" -Description "Deny_Any_Other_Inbound_Traffic_Inbound" `
-Access Deny -Protocol * -Direction Inbound -Priority 900 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange *

# Outbound rules

# Rule to allow Egress Traffic to target VMs via RDP (TCP and UDP)
$outboundRule1 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_3389_VirtualNetwork_Outbound" -Description "Allow_Any_3389_VirtualNetwork_Outbound" `
-Access Allow -Protocol * -Direction Outbound -Priority 100 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 3389

# Rule to allow Egress Traffic to target VMs via SSH (TCP and UPD)
$outboundRule2 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_22_VirtualNetwork_Outbound" -Description "Allow_Any_22_VirtualNetwork_Outbound" `
-Access Allow -Protocol * -Direction Outbound -Priority 110 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 22

# Rule to allow Egress Traffic to other public endpoints in Azure (e.g. for storing diagnostics logs and metering logs)
$outboundRule3 = New-AzNetworkSecurityRuleConfig -Name "Allow_TCP_443_AzureCloud_Outbound" -Description "Allow_TCP_443_AzureCloud_Outbound" `
-Access Allow -Protocol TCP -Direction Outbound -Priority 120 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix AzureCloud -DestinationPortRange 443

# Rule to allow Egress Traffic to Azure Bastion data plane
$outboundRule4 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_8080_5701_BastionHostCommunication_Outbound" -Description "Allow_Any_8080_5701_BastionHostCommunication_Outbound" `
-Access Allow -Protocol * -Direction Outbound -Priority 130 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork `
-DestinationPortRange 8080,5701

# Rule to allow Egress Traffic to Internet to allow Azure Bastion to communicate with the Internet for session and certificate validation
$outboundRule5 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_80_Internet_Outbound" -Description "Allow_Any_80_Internet_Outbound" `
-Access Allow -Protocol * -Direction Outbound -Priority 140 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix Internet `
-DestinationPortRange 80

# Rule to deny all other outbound virtual network traffic
$outboundRule6 = New-AzNetworkSecurityRuleConfig -Name "Deny_Any_Other_Traffic_Outbound" -Description "Deny_Any_Other_Outbound_Traffic_Outbound" `
-Access Deny -Protocol * -Direction Outbound -Priority 900 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange *

# Create the NSG if it not exists

try {
    Get-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNetworkSpoke -ErrorAction Stop | Out-Null 
} catch {
    New-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNetworkSpoke -Location $region `
    -SecurityRules $inboundRule1,$inboundRule2,$inboundRule3,$inboundRule4,$inboundRule5,$inboundRule6,$outboundRule1,$outboundRule2,$outboundRule3,$outboundRule4,$outboundRule5,`
    $outboundRule6 -Force | Out-Null 
}

# Set tags NSG
$nsg = Get-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNetworkSpoke
$nsg.Tag = $tags
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null

Write-Host ($writeEmptyLine + "# NSG $nsgBastionName available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

# Set the log settings for the NSG if they don't exist
try {
    Get-AzDiagnosticSetting -Name $nsgBastionDiagnosticsName -ResourceId ($nsg.Id) -ErrorAction Stop | Out-Null
} catch {
    $workSpace = Get-AzOperationalInsightsWorkspace -Name $logAnalyticsName -ResourceGroupName $rgLogAnalyticsSpoke
    
    Set-AzDiagnosticSetting -Name $nsgBastionDiagnosticsName -ResourceId ($nsg.Id) -Category NetworkSecurityGroupEvent,NetworkSecurityGroupRuleCounter -Enabled $true `
    -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

# Create the AzureBastionSubnet if it not exists

try {
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupname $rgNetworkSpoke

    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetBastionName -VirtualNetwork $vnet -ErrorAction Stop | Out-Null 
} catch {
    $subnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetBastionName -VirtualNetwork $vnet -AddressPrefix $subnetBastionAddress

    $vnet | Set-AzVirtualNetwork | Out-Null 
}

# Attach the NSG to the AzureBastionSubnet (also if the AzureBastionSubnet exists and misses and NSG)

$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetBastionName -VirtualNetwork $vnet
$nsg = Get-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNetworkSpoke
$subnet.NetworkSecurityGroup = $nsg
$vnet | Set-AzVirtualNetwork | Out-Null 

Write-Host ($writeEmptyLine + "# Subnet $subnetBastionName available with attached NSG $nsgBastionName" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create a Public IP Address (PIP) for the Bastion host if it not exists. Add specified tags and diagnostic settings

try {
    Get-AzPublicIpAddress -Name $pipBastionName -ResourceGroupName $rgBastion -ErrorAction Stop | Out-Null 
} catch {
    New-AzPublicIpAddress -Name $pipBastionName -ResourceGroupName $rgBastion -Location $region -AllocationMethod $pipBastionAllocationMethod -Sku $pipBastionSku -Force | Out-Null 
}

# Set tags on PIP
$pipBastion = Get-AzPublicIpAddress -ResourceGroupName $rgBastion -Name $pipBastionName
$pipBastion.Tag = $tags
Set-AzPublicIpAddress -PublicIpAddress $pipBastion | Out-Null

# Set the log and metrics settings for the PIP if they don't exist

try {
    Get-AzDiagnosticSetting -Name $pipBastionDiagnosticsName -ResourceId ($pipBastion.Id) -ErrorAction Stop | Out-Null
} catch {
    $workSpace = Get-AzOperationalInsightsWorkspace -Name $logAnalyticsName -ResourceGroupName $rgLogAnalyticsSpoke
    
    Set-AzDiagnosticSetting -Name $pipBastionDiagnosticsName -ResourceId ($pipBastion.Id) -Category DDoSProtectionNotifications,DDoSMitigationFlowLogs,DDoSMitigationReports -MetricCategory AllMetrics -Enabled $true `
    -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

Write-Host ($writeEmptyLine + "# Pip " + $pipBastionName + " available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create the Bastion host (it takes around 10 minutes for the Bastion host to be deployed) if it not exists

try {
    Get-AzBastion -ResourceGroupName $rgBastion -Name $bastionName  -ErrorAction Stop | Out-Null 
} catch {
    Write-Host ($writeEmptyLine + "# Bastion host deployment started, this can take up to 10 minutes" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine

    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupname $rgNetworkSpoke

    New-AzBastion -ResourceGroupName $rgBastion -Name $bastionName -PublicIpAddress $pipBastion -VirtualNetwork $vnet | Out-Null 
}

Write-Host ($writeEmptyLine + "# Bastion host $bastionName available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Set tags for the bastion resource

# Add VNet tag to tags
$tags += @{$tagVnetName=$vnetName}

# Set tags on Bastion host
$bastion = Get-AzBastion -ResourceGroupName $rgBastion -Name $bastionName 
Set-AzBastion -InputObject $bastion -Tag $tags -Force | Out-Null

Write-Host ($writeEmptyLine + "# $bastionName tags set" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Set the diagnostic settings (log and metrics) for the bastion resource, if they don't exist

try {
    Get-AzDiagnosticSetting -Name $bastionDiagnosticsName -ResourceId ($bastion.Id) -ErrorAction Stop | Out-Null
} catch {
    $workSpace = Get-AzOperationalInsightsWorkspace -Name $logAnalyticsName -ResourceGroupName $rgLogAnalyticsSpoke
    
    Set-AzDiagnosticSetting -Name $bastionDiagnosticsName -ResourceId ($bastion.Id) -Category BastionAuditLogs -MetricCategory AllMetrics -Enabled $true `
    -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

Write-Host ($writeEmptyLine + "# $bastionName diagnostic settings set" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Lock the Azure Bastion resource group with a CanNotDelete lock

$lock = Get-AzResourceLock -ResourceGroupName $rgBastion

if ($null -eq $lock){
    New-AzResourceLock -LockName DoNotDeleteLock -LockLevel CanNotDelete -ResourceGroupName $rgBastion -LockNotes "Prevent $rgBastion from deletion" -Force | Out-Null
    } 

Write-Host ($writeEmptyLine + "# Resource group $rgBastion locked" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
