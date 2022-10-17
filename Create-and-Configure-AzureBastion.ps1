<#
.SYNOPSIS

A script used to create and configure Azure Bastion within the HUB spoke VNet.

.DESCRIPTION

A script used to create and configure Azure Bastion (basic SKU) within the HUB spoke VNet in a management subscription.
The script will do all of the following:

Check if the PowerShell window is running as Administrator (when not running from Cloud Shell), otherwise the Azure PowerShell script will be exited.
Suppress breaking change warning messages.
Change the current context to use a management subscription (a subscription with *management* in the subscription name will be automatically selected).
Save the Log Analytics workspace from the management subscription in a variable.
Store a specified set of tags in a hash table.
Register Insights provider in order for flow logging to work, if not already registered. Registration may take up to 10 minutes.
Create a resource group for the storage account which will store the NSG flow log data, if it not already exists.
Create a general purpose v2 storage account for storing the flow logs with specific configuration settings, if it not already exists. Also apply the necessary tags to this storage account.
Create a resource group for the Azure Bastion resources if it not already exists. Also apply the necessary tags to this resource group.
Create the AzureBastionSubnet with an associated network security group (NSG), if it not already exists. 
The NSG itself will contain all the required inbound and outbound security rules. If the AzureBastionSubnet exists but does not have an associated NSG, it will attach the newly created NSG. 
The AzureBastionSubnet at least must have a subnet size of /26 or larger. * Also apply the necessary tags and diagnostic settings to the NSG.
Create a Standard SKU PIP for the Bastion host, if it not already exists. Also apply the necessary tags and diagnostic settings to this PIP.
Enable NSG Flow logs (Version 2) and Traffic Analytics for the AzureBastionSubnet NSG.
Create the Bastion host (Basic SKU), if it not already exists. Keep in mind that it can take up to 9 minutes for the Bastion host to be deployed. Also apply the necessary tags to the Bastion host.
Set the diagnostic settings (log and metrics) for the bastion resource if they don’t exist.
Lock the Azure Bastion resource group with a CanNotDelete lock.

.NOTES

Filename:       Create-and-Configure-AzureBastion.ps1
Created:        01/06/2021
Last modified:  17/10/2022
Author:         Wim Matthyssen
Version:        3.0
PowerShell:     Azure PowerShell and Azure Cloud Shell
Requires:       PowerShell Az (v5.9.0) and Az.Network (v4.7.0)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "As Is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx" (if not using the default tenant)
.\Create-and-Configure-AzureBastion.ps1

.LINK

https://wmatthyssen.com/2022/04/19/azure-bastion-azure-powershell-deployment-script/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$spoke = "hub"
$region = #<your region here> The used Azure public region. Example: "westeurope"
$purpose = "bastion"

$rgNameBastion = #<your Bastion resource group name here> The name of the new Azure resource group in which the new Bastion resource will be created. Example: "rg-hub-myh-bastion-01"
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
$nsgBastionName = #<your AzureBastionSubnet NSG name here> The name of the NSG associated with the AzureBastionSubnet. Example: "nsg-AzureBastionSubnet"
$nsgBastionDiagnosticsName = #<your NSG Bastion Diagnostics settings name here> The name of the NSG diagnostic settings for Bastion. Example: "diag-nsg-AzureBastionSubnet"

$bastionName = #<your Bastion name here> The name of the new Bastion resource. Example: "bas-hub-myh-01"
$bastionSku = "Basic"
$bastionDiagnosticsName = #<your Bastion Diagnostics settings name here> The name of the new diagnostic settings for Bastion. Example: "diag-bas-hub-myh-01"

$pipNameBastion = #<your Bastion PIP name here> The public IP address of the Bastion resource. Example: "pip-bas-hub-myh-01"
$pipAllocationMethodBastion = "Static"
$pipSkuBastion = "Standard"
$pipTierBastion = "Regional"
$pipIpAddressVersionBastion = "IPv4"
$pipBastionDiagnosticsName = #<your PIP Bastion Diagnostics settings name here> The name of the PIP diagnostic settings for Bastion. Example: "diag-pip-bas-hub-myh-01"

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
$tagVnetName = #<your VNet tag name here> The vnet tag name you want to use. Example:"VNet"
$tagSkuName = "Sku"
$tagSkuValue = $storageAccountSkuName

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

## Register Insights provider (Microsoft.Insights) in order for flow logging to work, if not already registered. Registration may take up to 10 minutes

# Register Microsoft.Insights resource provider
Register-AzResourceProvider -ProviderNamespace Microsoft.Insights  | Out-Null

Write-Host ($writeEmptyLine + "# Microsoft.Insights resource provider currently registering or already registerd" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create a resource group for the storage account which will store the flow logs, if it not already exists

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

## Create a general purpose v2 storage account for storing the flow logs with specific configuration settings, if it not already exists. Also apply the necessary tags to this storage account.

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

## Create a resource group for the Azure Bastion resources if it not already exists. Add specified tags and lock with a CanNotDelete lock

try {
    Get-AzResourceGroup -Name $rgNameBastion -ErrorAction Stop | Out-Null
} catch {
    New-AzResourceGroup -Name $rgNameBastion.ToLower() -Location $region -Force | Out-Null
}

# Save variable tags in a new variable to add tags
$tagsBastion = $tags

# Add Purpose tag to $tagsBastion
$tagsBastion += @{$tagPurposeName = $tagPurposeValueBastion}

# Set tags Bastion resource group
Set-AzResourceGroup -Name $rgNameBastion -Tag $tagsBastion | Out-Null

Write-Host ($writeEmptyLine + "# Resource group $rgNameBastion available" + $writeSeperatorSpaces + $currentTime)`
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
    Get-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNameNetworking -ErrorAction Stop | Out-Null 
} catch {
    New-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNameNetworking -Location $region `
    -SecurityRules $inboundRule1,$inboundRule2,$inboundRule3,$inboundRule4,$inboundRule5,$inboundRule6,$outboundRule1,$outboundRule2,$outboundRule3,$outboundRule4,$outboundRule5,`
    $outboundRule6 -Force | Out-Null 
}

# Set tags NSG
$nsg = Get-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNameNetworking
$nsg.Tag = $tagsBastion
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsg | Out-Null

Write-Host ($writeEmptyLine + "# NSG $nsgBastionName available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

# Set the log settings for the NSG if they don't exist
try {
    Get-AzDiagnosticSetting -Name $nsgBastionDiagnosticsName -ResourceId ($nsg.Id) -ErrorAction Stop | Out-Null
} catch { 
    Set-AzDiagnosticSetting -Name $nsgBastionDiagnosticsName -ResourceId ($nsg.Id) -Category NetworkSecurityGroupEvent,NetworkSecurityGroupRuleCounter -Enabled $true `
    -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

# Create the AzureBastionSubnet if it does not exist
try {
    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupname $rgNameNetworking

    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetNameBastion -VirtualNetwork $vnet -ErrorAction Stop | Out-Null 
} catch {
    $subnet = Add-AzVirtualNetworkSubnetConfig -Name $subnetNameBastion -VirtualNetwork $vnet -AddressPrefix $subnetAddressBastion

    $vnet | Set-AzVirtualNetwork | Out-Null 
}

# Attach the NSG to the AzureBastionSubnet (also if the AzureBastionSubnet exists and misses and NSG)
$subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetNameBastion -VirtualNetwork $vnet
$nsg = Get-AzNetworkSecurityGroup -Name $nsgBastionName -ResourceGroupName $rgNameNetworking
$subnet.NetworkSecurityGroup = $nsg
$vnet | Set-AzVirtualNetwork | Out-Null 

Write-Host ($writeEmptyLine + "# Subnet $subnetNameBastion available with attached NSG $nsgBastionName" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create a Public IP Address (PIP) for the Bastion host if it does not exist. Add specified tags and diagnostic settings

try {
    Get-AzPublicIpAddress -Name $pipNameBastion -ResourceGroupName $rgNameBastion -ErrorAction Stop | Out-Null 
} catch {
    New-AzPublicIpAddress -Name $pipNameBastion -ResourceGroupName $rgNameBastion -Location $region -AllocationMethod $pipAllocationMethodBastion -Sku $pipSkuBastion `
    -Tier $pipTierBastion -IpAddressVersion $pipIpAddressVersionBastion | Out-Null 
}

# Set tags on PIP
$pipBastion = Get-AzPublicIpAddress -Name $pipNameBastion -ResourceGroupName $rgNameBastion 
$pipBastion.Tag = $tagsBastion
Set-AzPublicIpAddress -PublicIpAddress $pipBastion | Out-Null

# Set the log and metrics settings for the PIP, if they don't exist
try {
    Get-AzDiagnosticSetting -Name $pipBastionDiagnosticsName -ResourceId ($pipBastion.Id) -ErrorAction Stop | Out-Null
} catch {   
    Set-AzDiagnosticSetting -Name $pipBastionDiagnosticsName -ResourceId ($pipBastion.Id) -Category DDoSProtectionNotifications,DDoSMitigationFlowLogs,DDoSMitigationReports `
    -MetricCategory AllMetrics -Enabled $true -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

Write-Host ($writeEmptyLine + "# Pip " + $pipNameBastion + " available and diagnostic settings set" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Enable NSG Flow logs (Version 2) and Traffic Analytics for the AzureBastionSubnet NSG

$networkWatcher = Get-AzNetworkWatcher -Name $networkWatcherName -ResourceGroupName $rgNameNetworkWatcher
$storageAccount = Get-AzStorageAccount -ResourceGroupName $rgNameStorage -Name $storageAccountName

# Configure Flow log and Traffic Analytics
Set-AzNetworkWatcherFlowLog -Name ($nsg.Name + "-flow-log") -NetworkWatcher $networkWatcher -TargetResourceId $nsg.Id -StorageId $storageAccount.Id -Enabled $true -FormatType Json `
-FormatVersion 2 -EnableTrafficAnalytics -TrafficAnalyticsWorkspaceId ($workSpace.ResourceId) -TrafficAnalyticsInterval $trafficAnalyticsInterval -EnableRetention $true `
-RetentionPolicyDays $nsgFlowLogsRetention -Tag $tagsBastion -Force | Out-Null

Write-Host ($writeEmptyLine + "# NSG FLow logs and Traffic Analytics for $($nsg.Name) enabled" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Create the Bastion host (it takes around 9 minutes for the Bastion host to be deployed) if it does not exist

try {
    Get-AzBastion -ResourceGroupName $rgNameBastion -Name $bastionName -ErrorAction Stop | Out-Null 
} catch {
    Write-Host ($writeEmptyLine + "# Bastion host deployment started; this can take up to 9 minutes" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine

    $vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupname $rgNameNetworking
    New-AzBastion -ResourceGroupName $rgNameBastion -Name $bastionName -PublicIpAddress $pipBastion -VirtualNetwork $vnet -Sku $bastionSku | Out-Null 
}

# Add VNet tag to tags
$tagsBastion += @{$tagVnetName=$vnetName}

# Set tags on Bastion host
$bastion = Get-AzBastion -ResourceGroupName $rgNameBastion -Name $bastionName 
Set-AzBastion -InputObject $bastion -Tag $tagsBastion -Force | Out-Null

Write-Host ($writeEmptyLine + "# Bastion host $bastionName available" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Set the log and metrics settings for the bastion resource if they don't exist

try {
    Get-AzDiagnosticSetting -Name $bastionDiagnosticsName -ResourceId ($bastion.Id) -ErrorAction Stop | Out-Null
} catch {    
    Set-AzDiagnosticSetting -Name $bastionDiagnosticsName -ResourceId ($bastion.Id) -Category BastionAuditLogs -MetricCategory AllMetrics -Enabled $true `
    -WorkspaceId ($workSpace.ResourceId) | Out-Null
}

Write-Host ($writeEmptyLine + "# Bastion host $bastionName diagnostic settings set" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Lock the Azure Bastion resource group with a CanNotDelete lock

$lock = Get-AzResourceLock -ResourceGroupName $rgNameBastion

if ($null -eq $lock){
    New-AzResourceLock -LockName DoNotDeleteLock -LockLevel CanNotDelete -ResourceGroupName $rgNameBastion -LockNotes "Prevent $rgNameBastion from deletion" -Force | Out-Null
    } 

Write-Host ($writeEmptyLine + "# Resource group $rgNameBastion locked" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
