<#

.SYNOPSIS

A script used to RDP to a target Azure Windows VM using Tunneling from Azure Bastion with Azure CLI and PowerShell.

.DESCRIPTION

A script used to RDP to a target Azure Windows VM using Tunneling from Azure Bastion with Azure CLI and PowerShell.
The script will do all of the following:

Check if the PowerShell window is running as Administrator (when not running from Cloud Shell); otherwise, the Azure PowerShell script will be exited.
Remove the breaking change warning messages.
Check if Azure CLI is already installed and, if required, update it to the latest version. If Azure CLI is not installed, install it.
Change the current context to the subscription holding the Azure Bastion host.
Save the Bastion host as a variable and check if it uses the Standard SKU; otherwise, exit the script.
Validate if the target VM exists, and if so, find the subscription it belongs to; otherwise, exit the script.
RDP to the target VM using the native client through Azure Bastion.
Remote Desktop File conn.rdp will be removed when the RDP connection is terminated.

.NOTES

Filename:       Connect-RDP-Azure-Windows-VM-using-native-client-via-Azure-Bastion.ps1
Created:        26/02/2023
Last modified:  01/03/2023
Author:         Wim Matthyssen
Version:        2.0
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
    # $vmName -> Name of the target Azure Windows VM
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $vmName
)

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$allSubscriptions = Get-AzSubscription
$subscriptionNameVM = ""
$vmObject = $null
$rdpFileName = "conn.rdp"

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Check if PowerShell runs as Administrator; otherwise, exit the script

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdministrator = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Check if you are running PowerShell as an administrator; otherwise, exit the script
if ($isAdministrator -eq $false) {
    Write-Host ($writeEmptyLine + "# Please run PowerShell as Administrator" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
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

## Check if Azure CLI is already installed and, if required, update it to the latest version. If Azure CLI is not installed, install it 

try {
    if ($null -ne (az version)) {
        Write-Host ($writeEmptyLine + "# If needed, the Azure CLI will be updated to the latest version, which can take a few minutes to complete" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor2 $writeEmptyLine
        az upgrade --yes 2>nul
    }
} catch {
    if ($error[0].ToString() -match "The term 'az' is not recognized as a name of a cmdlet") {
        Write-Host ($writeEmptyLine + "# Azure CLI is not installed. To proceed, it will now be installed, which can take up to 2 minutes" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor2 $writeEmptyLine
        
        # Install Azure CLI with MSI
        $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; 
        Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; 
        Remove-Item .\AzureCLI.msi
        }
}
Finally {
    Write-Host ($writeEmptyLine + "# Azure CLI is installed and running the latest version" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine
}

# Enable Azure CLI auto-upgrade
# az config set auto-upgrade.enable=yes

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Change the current context to the subscription holding the Azure Bastion host

#<your subscription value hare> Replace with the name value of your Azure Bastion subscription. Example: "management" -> {$_.Name -like "*management"*"} 
$subNameBastion = Get-AzSubscription | Where-Object {$_.Name -like "*<your subscription value here>*"} 

Set-AzContext -SubscriptionId $subNameBastion.SubscriptionId | Out-Null 

Write-Host ($writeEmptyLine + "# Bastion host subscription in current tenant selected" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Save the Bastion host as a variable and check if it uses the Standard SKU; otherwise, exit the script

$bastion = Get-AzBastion

if ($bastion.SkuText.Contains("Basic")) {
    Write-Host ($writeEmptyLine + "# Bastion host runs with the Basic SKU, please upgrade to Standard SKU" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    exit
}

Write-Host ($writeEmptyLine + "# Bastion host variable created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Validate if the target VM exists, and if so, find the subscription it belongs to; otherwise, exit the script

if ($allSubscriptions){
    foreach ($subscription in $allSubscriptions){
        Set-AzContext -Subscription $Subscription.Name | Out-Null
        $vmObject = Get-AzVM -Name $vmName
        if ($vmObject) {
            $subscriptionNameVM = $subscription.Name
            Write-Host ($writeEmptyLine + "# Target VM found in subscription $subscriptionNameVM" + $writeSeperatorSpaces + $currentTime)`
            -foregroundcolor $foregroundColor2 $writeEmptyLine
            break 
        }
    }
}

if (-not $vmObject) {
    Write-Host ($writeEmptyLine + "# VM not found" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor3 $writeEmptyLine
    Start-Sleep -s 3
    Write-Host -NoNewLine ("# Press any key to exit the script ..." + $writeEmptyLine)`
    -foregroundcolor $foregroundColor1 $writeEmptyLine;
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null;
    exit
}

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## RDP to the target VM using the native client through Azure Bastion

Write-Host ($writeEmptyLine + "# Setting up remote desktop connection to target VM $vmName" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

$vm = Get-AzVM -Name $vmName

# Azure CLI
az network bastion rdp --name $bastion.Name --resource-group $bastion.ResourceGroupName --target-resource-id $vm.Id --output none --only-show-errors

Write-Host ($writeEmptyLine + "# Please use the correct credentials to log in to the open Remote Desktop connection" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remote Desktop File conn.rdp will be removed when the RDP connection is terminated

Get-ChildItem | Where-Object Name -Like $rdpFileName | ForEach-Object { Remove-Item -LiteralPath $_.Name }

Write-Host ($writeEmptyLine + "# Remote Destkop File $rdpFileName removed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
