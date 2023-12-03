<#

.SYNOPSIS

A script used to enable all the Azure Bastion Standard SKU features (kerberos authentication, copy and paste, native client support, IP-based connection, and shareable link) on an Azure Bastion host.

.DESCRIPTION

A script used to enable all the Azure Bastion Standard SKU features (kerberos authentication, copy and paste, native client support, IP-based connection, and shareable link) on an Azure Bastion host.

The script will do all of the following:

Remove the breaking change warning messages.
Change the current context to the subscription holding the Azure Bastion host, if the subscription exists; otherwise, exit the script.
Save the Bastion host as a variable if it exists in the subscription and uses the Standard SKU; otherwise, exit the script.
Store the current set of Azure Bastion host tags in a hash table.
Enable the Azure Bastion Standard SKU features using the REST API.
Set stored tags on the Azure Bastion host.

.NOTES

Filename:       Enable-Azure-Bastion-Standard-SKU-features.ps1
Created:        02/12/2023
Last modified:  02/12/2023
Author:         Wim Matthyssen
Version:        1.0
PowerShell:     Azure PowerShell and Azure Cloud Shell
Requires:       PowerShell Az (v10.4.1)
Action:         Change variables were needed to fit your needs. 
Disclaimer:     This script is provided "as is" with no warranties.

.EXAMPLE

Connect-AzAccount
Get-AzTenant (if not using the default tenant)
Set-AzContext -tenantID "xxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx" (if not using the default tenant)
.\Enable-Azure-Bastion-Standard-SKU-features.ps1 <"your azure bastion host subscription name here"> <"your bastion host name here"> 

-> .\Enable-Azure-Bastion-Standard-SKU-features.ps1 sub-hub-myh-management-01 bas-hub-myh-01

.LINK


#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $subscriptionName -> Name of the subscription holding the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $subscriptionName,
    # $bastionName -> Name of the Azure Bastion host
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $bastionName
)

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$httpsUriStart = "https://management.azure.com/subscriptions/"
$createApiVersion = "?api-version=2022-07-01"
$authenticationType = "Bearer"
$method = "Put"
$contentType = "application/json"

$bastionSubnetName = "AzureBastionSubnet"

# Time, colors, and formatting
Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime = Get-Date -Format "dddd MM/dd/yyyy HH:mm"} | Out-Null 
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages

Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true | Out-Null
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
$warningPreference = "SilentlyContinue"

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script started

Write-Host ($writeEmptyLine + "# Script started. Without errors, it takes up to 1 minute to complete" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to the subscription holding the Azure Bastion host, if the subscription exists; otherwise, exit the script

Get-AzSubscription -SubscriptionName $subscriptionName -ErrorVariable subscriptionNotPresent -ErrorAction SilentlyContinue | Out-Null

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

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Save the Bastion host as a variable if it exists in the subscription and uses the Standard SKU; otherwise, exit the script

$bastionObject = Get-AzBastion 
$bastionName = ($bastionObject).Name

if ($null -eq $bastionObject){
    Write-Host ($writeEmptyLine + "# There is no Bastion host included in the current subscription" + $writeSeperatorSpaces + $currentTime) -foregroundcolor $foregroundColor2 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host ($writeEmptyLine + "# Press any key to exit the script ..." + $writeEmptyLine) -foregroundcolor $foregroundColor1 $writeEmptyLine
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
        Write-Host ($writeEmptyLine + "# Bastion host $bastionName exists in the current subscription and uses the Standard SKU; the script will continue" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor2 $writeEmptyLine
    }
}

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Store the current set of Azure Bastion host tags in a hash table

$bastionTags = (Get-AzResource -ResourceGroupName $rgNameBastion -ResourceName $bastion.Name).Tags

Write-Host ($writeEmptyLine + "# Specified set of tags available to add" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Enable the Azure Bastion Standard SKU features using the REST API

# Get subscription ID
$subscriptionID = (Get-AzContext).Subscription.Id

# Get Bastion parameters
$bastionResourceGroupName = $bastionObject.ResourceGroupName
$bastionLocation = $bastionObject.Location

# Get Public IP Address (PIP)
$publicip = Get-AzPublicIpAddress -ResourceGroupName $bastionResourceGroupName

# Get AzureBastionSubnet
$bastionSubnet = Get-AzVirtualNetwork | Where-Object { $_.Subnets -ne $null -and $_.Subnets.Name -contains $bastionSubnetName } | Get-AzVirtualNetworkSubnetConfig -Name $bastionSubnetName

# Create REST API parameters
$uri = $httpsUriStart + $subscriptionID + "/resourceGroups/$($bastionResourceGroupName)/providers/Microsoft.Network/bastionHosts/$bastionName/$createApiVersion"
$token = (Get-AzAccessToken).Token | ConvertTo-SecureString -AsPlainText -Force
$body = @{
    location = $bastionLocation
    properties = @{
        disableCopyPaste = $false
        enableKerberos = $true #also requires setting the DNS settings of your VNet to your Azure-hosted domain controller(s)
        enableTunneling = $true
        enableIpConnect = $true
        enableShareableLink = $true
        ipConfigurations = @(@{name = "bastionHostIpConfiguration"; properties = @{subnet = @{id = $bastionSubnet.id}; publicIPAddress = @{id = $publicip.Id}}})
    }
} | ConvertTo-Json -Depth 6

# Send an HTTP or HTTPS request to a REST API endpoint
Invoke-WebRequest -Uri $uri -Authentication $authenticationType -Token $token -Method $method -Body $body -ContentType $contentType | Out-Null

Write-Host ($writeEmptyLine + "# The Azure Bastion Standard SKU features are enabled for bastion host $bastionName" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Set stored tags on the Azure Bastion host

Set-AzBastion -InputObject $bastion -Tag $bastionTags -Force | Out-Null

Write-Host ($writeEmptyLine + "# Azure resource tags re-applied on the Azure Bastion host" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed; keep in mind that it can take up to 6 minutes before all features are fully usable" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
