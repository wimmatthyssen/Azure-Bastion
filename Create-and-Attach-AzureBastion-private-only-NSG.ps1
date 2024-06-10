<#
.SYNOPSIS

A script used to create and attach an NSG to the AzureBastionSubnet for an Azure Bastion private-only deployment (Public Preview) in a management subscription.

.DESCRIPTION

A script used to create and attach an NSG to the AzureBastionSubnet for an Azure Bastion private-only deployment (Public Preview) in a management subscription.
The script will do all of the following:

Remove the breaking change warning messages.
Change the current context to use a management subscription (a subscription with *management* in the subscription name will be automatically selected).
Save the Log Analytics workspace from the management subscription in a variable.
Store a specified set of tags in a hash table.
If it does not already exist, create a resource group for the storage account that will store the NSG flow log data.
If it does not already exist, create a general-purpose v2 storage account for storing the flow logs with specific configuration settings. Also apply the necessary tags to this storage account.
Create the AzureBastionSubnet with the network security group if it does not already exist. Add the required inbound and outbound security rules. Add specified tags and diagnostic settings.
Enable NSG Flow logs (Version 2) and Traffic Analytics for the AzureBastionSubnet NSG.

.NOTES

Filename:       Create-and-Attach-AzureBastion-private-only-NSG.ps1
Created:        10/06/2024
Last modified:  10/06/2024
Author:         Wim Matthyssen
Version:        1.0
PowerShell:     Azure PowerShell and Azure Cloud Shell
Requires:       PowerShell Az (v10.4.1) and Az.Network (v6.2.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "as is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx" (if not using the default tenant)
.\Create-and-Attach-AzureBastion-private-only-NSG.ps1

.LINK


#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$spoke = "hub"
$region = #<your region here> The used Azure public region. Example: "westeurope"
$purpose = "Bastion"

$rgNameNetworking = #<your VNet resource group name here> The name of the Azure resource group in which you're existing VNet is deployed. Example: "rg-hub-myh-networking-01"
$rgNameStorage = #<your storage account resource group name here> The name of the Azure resource group in which you're new or existing storage account is deployed. Example: "rg-hub-myh-storage-01"
$rgNameNetworkWatcher = #<your Network Watcher resource group name here> The name of the Azure resource group in which you're existing Network Watcher is deployed. Example: "rg-hub-myh-networking-01"

$networkWatcherName = #<your Network Watcher name here> The name of your existing Network Watcher. Example: "nw-hub-myh-we-01"
$logAnalyticsWorkspaceName = #<your Log Analytics workspace name here> The name of your existing Log Analytics workspace. Example: "law-hub-myh-01"

$storageAccountName = #<your storage account name here> The existing or new storage account to store the NSG Flow logs. Example: "sthubmyhlog01"
$storageAccountSkuName = "Standard_LRS"
$storageAccountType = "StorageV2"
$storageMinimumTlsVersion = "TLS1_2"

$nsgFlowLogsRetention = "90"
$trafficAnalyticsInterval = "60"

$vnetName = #<your VNet name here> The existing VNet in which the Bastion resource will be created. Example: "vnet-hub-myh-weu-01"
$subnetNameBastion = "AzureBastionSubnet"
$subnetAddressBastion = #<your AzureBastionSubnet range here> The subnet must have a minimum subnet size of /26. Example: "10.1.1.128/26"
$nsgNameBastion = #<your AzureBastionSubnet NSG name here> The name of the NSG associated with the AzureBastionSubnet. Example: "nsg-AzureBastionSubnet"
$nsgBastionDiagnosticsName = #<your NSG Bastion Diagnostics settings name here> The name of the NSG diagnostic settings for Bastion. Example: "diag-nsg-AzureBastionSubnet"

$tagSpokeName = #<your environment tag name here> The environment tag name you want to use. Example:"Env"
$tagSpokeValue = "$($spoke[0].ToString().ToUpper())$($spoke.SubString(1))"
$tagCostCenterName  = #<your costCenter tag name here> The costCenter tag name you want to use. Example:"CostCenter"
$tagCostCenterValue = #<your costCenter tag value here> The costCenter tag value you want to use. Example: "23"
$tagCriticalityName = #<your businessCriticality tag name here> The businessCriticality tag name you want to use. Example: "Criticality"
$tagCriticalityValue = #<your businessCriticality tag value here> The businessCriticality tag value you want to use. Example: "High"
$tagPurposeName  = #<your purpose tag name here> The purpose tag name you want to use. Example:"Purpose"
$tagPurposeValueBastion = "$($purpose[0].ToString().ToUpper())$($purpose.SubString(1))"
$tagPurposeValueStorage = "Storage" 
$tagPurposeValueLog = "Log"   
$tagSkuName = "Sku"
$tagSkuValue = $storageAccountSkuName

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

# ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages
 
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true | Out-Null
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
$warningPreference = "SilentlyContinue"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script started

Write-Host ($writeEmptyLine + "# Script started. Without errors, it can take up to 2 minutes to complete" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to use a management subscription

$subNameManagement = Get-AzSubscription | Where-Object {$_.Name -like "*management*"}

Set-AzContext -SubscriptionId $subNameManagement.SubscriptionId | Out-Null 

Write-Host ($writeEmptyLine + "# Management subscription in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Save Log Analytics workspace from the management subscription in a variable

$workSpace = Get-AzOperationalInsightsWorkspace | Where-Object Name -Match $logAnalyticsWorkSpaceName

Write-Host ($writeEmptyLine + "# Log Analytics workspace variable created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Store the specified set of tags in a hash table

$tags = @{$tagSpokeName=$tagSpokeValue;$tagCostCenterName=$tagCostCenterValue;$tagCriticalityName=$tagCriticalityValue}

Write-Host ($writeEmptyLine + "# Specified set of tags available to add" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## If it does not already exist, create a resource group for the storage account that will store the NSG flow log data.

try {
    Get-AzResourceGroup -Name $rgNameStorage -ErrorAction Stop | Out-Null 
} catch {
    New-AzResourceGroup -Name $rgNameStorage -Location $region -Force | Out-Null 
}

# Save variable tags in a new variable to add tags
$tagsResourceGroup = $tags

# Add Purpose tag to tagsResourceGroup
$tagsResourceGroup += @{$tagPurposeName = $tagPurposeValueStorage}

# Set tags rg storage
Set-AzResourceGroup -Name $rgNameStorage -Tag $tagsResourceGroup | Out-Null

Write-Host ($writeEmptyLine + "# Resource group $rgNameStorage available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## If it does not already exist, create a general-purpose v2 storage account for storing the flow logs with specific configuration settings. 
## Also apply the necessary tags to this storage account.

try {
    Get-AzStorageAccount -ResourceGroupName $rgNameStorage -Name $storageAccountName -ErrorAction Stop | Out-Null 
} catch {
    New-AzStorageAccount -ResourceGroupName $rgNameStorage -Name $storageAccountName -SkuName $storageAccountSkuName -Location $region -Kind $storageAccountType `
    -AllowBlobPublicAccess $false -MinimumTlsVersion $storageMinimumTlsVersion | Out-Null 
}

# Save variable tags in a new variable to add tags
$tagsStorageAccount = $tags

# Add Purpose tag to tagsStorageAccount
$tagsStorageAccount += @{$tagPurposeName = $tagPurposeValueLog}

# Add Sku tag to tagsStorageAccount
$tagsStorageAccount += @{$tagSkuName = $tagSkuValue}

# Set tags storage account
Set-AzStorageAccount -ResourceGroupName $rgNameStorage -Name $storageAccountName -Tag $tagsStorageAccount | Out-Null

Write-Host ($writeEmptyLine + "# Storage account $storageAccountName created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create the AzureBastionSubnet with the network security group if it does not already exist. Add the required inbound and outbound security rules. Add specified tags and diagnostic settings

# Inbound rules

# Rule to allow Ingress Traffic from public Internet
$inboundRule1 = New-AzNetworkSecurityRuleConfig -Name "Allow_TCP_443_Internet_Inbound" -Description "Allow_TCP_443_Internet_Inbound" `
-Access Allow -Protocol TCP -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 443

# Rule to allow Ingress Traffic to Azure Bastion data plane
$inboundRule2 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_8080_5701_BastionHostCommunication_Inbound" -Description "Allow_Any_8080_5701_BastionHostCommunication_Inbound" `
-Access Allow -Protocol * -Direction Inbound -Priority 110 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork `
-DestinationPortRange 8080,5701

# Rule to allow Ingress Traffic to Virtual Network
$inboundRule3 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_Any_Vnet_Inbound" -Description "Allow_Any_Any_Vnet_Inbound" `
-Access Allow -Protocol * -Direction Inbound -Priority 120 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork `
-DestinationPortRange *

# Rule to deny all other inbound virtual network traffic
$inboundRule4 = New-AzNetworkSecurityRuleConfig -Name "Deny_Any_Other_Traffic_Inbound" -Description "Deny_Any_Other_Inbound_Traffic_Inbound" `
-Access Deny -Protocol * -Direction Inbound -Priority 900 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange *

# Outbound rules

# Rule to allow Egress Traffic to target VMs via RDP (TCP and UDP)
$outboundRule1 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_3389_VirtualNetwork_Outbound" -Description "Allow_Any_3389_VirtualNetwork_Outbound" `
-Access Allow -Protocol * -Direction Outbound -Priority 100 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 3389

# Rule to allow Egress Traffic to target VMs via SSH (TCP and UPD)
$outboundRule2 = New-AzNetworkSecurityRuleConfig -Name "Allow_Any_22_VirtualNetwork_Outbound" -Description "Allow_Any_22_VirtualNetwork_Outbound" `
-Access Allow -Protocol * -Direction Outbound -Priority 110 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 22

# Rule to allow Egress Traffic to other public endpoints in Azure (e.g., for storing diagnostics logs and metering logs)
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

# Create the NSG if it does not exist

try {
    Get-AzNetworkSecurityGroup -Name $nsgNameBastion -ResourceGroupName $rgNameNetworking -ErrorAction Stop | Out-Null 
} catch {
    New-AzNetworkSecurityGroup -Name $nsgNameBastion -ResourceGroupName $rgNameNetworking -Location $region `
    -SecurityRules $inboundRule1,$inboundRule2,$inboundRule3,$inboundRule4,$outboundRule1,$outboundRule2,$outboundRule3,$outboundRule4,$outboundRule5,`
    $outboundRule6 -Force | Out-Null 
}

# Save variable tags in a new variable to add tags
$tagsBastion = $tags

# Add Purpose tag to $tagsBastion
$tagsBastion += @{$tagPurposeName = $tagPurposeValueBastion}

# Set tags NSG
$nsg = Get-AzNetworkSecurityGroup -Name $nsgNameBastion -ResourceGroupName $rgNameNetworking
$nsg.Tag = $tagsBastion
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null

Write-Host ($writeEmptyLine + "# NSG $nsgNameBastion available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

# Set the log settings for the NSG if they don't exist

$nsgLog = @()
$nsgLog += New-AzDiagnosticSettingLogSettingsObject -Enabled $true -CategoryGroup "allLogs"

try {
    Get-AzDiagnosticSetting -Name $nsgBastionDiagnosticsName -ResourceId ($nsg.Id) -ErrorAction Stop | Out-Null
} catch {   
    New-AzDiagnosticSetting -Name $nsgBastionDiagnosticsName -ResourceId ($nsg.Id) -Log $nsgLog `
    -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

# Create the AzureBastionSubnet if it does not exist
try {
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupname $rgNameNetworking

    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetNameBastion -VirtualNetwork $vnet -ErrorAction Stop | Out-Null 
} catch {
    $subnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetNameBastion -VirtualNetwork $vnet -AddressPrefix $subnetAddressBastion | Out-Null

    $vnet | Set-AzVirtualNetwork | Out-Null 
}

# Attach the NSG to the AzureBastionSubnet (also if the AzureBastionSubnet exists but lacks an NSG)
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetNameBastion -VirtualNetwork $vnet
$nsg = Get-AzNetworkSecurityGroup -Name $nsgNameBastion -ResourceGroupName $rgNameNetworking
$subnet.NetworkSecurityGroup = $nsg
$vnet | Set-AzVirtualNetwork | Out-Null 

Write-Host ($writeEmptyLine + "# Subnet $subnetNameBastion available with attached NSG $nsgNameBastion" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Enable NSG Flow logs (Version 2) and Traffic Analytics for the AzureBastionSubnet NSG

$networkWatcher = Get-AzNetworkWatcher -Name $networkWatcherName -ResourceGroupName $rgNameNetworkWatcher
$storageAccount = Get-AzStorageAccount -ResourceGroupName $rgNameStorage -Name $storageAccountName

try {
    Get-AzNetworkWatcherFlowLog -Name "$($nsg.Name)-flow-log" -NetworkWatcher $networkWatcher -TargetResourceId $nsg.Id -ErrorAction Stop | Out-Null 
} catch {
    # Configure Flow log and Traffic Analytics
    Set-AzNetworkWatcherFlowLog -Name "$($nsg.Name)-flow-log" -NetworkWatcher $networkWatcher -TargetResourceId $nsg.Id -StorageId $storageAccount.Id -Enabled $true -FormatType Json `
    -FormatVersion 2 -EnableTrafficAnalytics -TrafficAnalyticsWorkspaceId ($workSpace.ResourceId) -TrafficAnalyticsInterval $trafficAnalyticsInterval -EnableRetention $true `
    -RetentionPolicyDays $nsgFlowLogsRetention -Tag $tagsBastion -Force | Out-Null
}

Write-Host ($writeEmptyLine + "# NSG FLow logs and Traffic Analytics for $($nsg.Name) enabled" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------