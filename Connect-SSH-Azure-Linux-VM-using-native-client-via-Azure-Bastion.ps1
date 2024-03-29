<#

.SYNOPSIS

A script used to SSH to a target Azure Linux VM using Tunneling from Azure Bastion with Azure CLI and PowerShell.

.DESCRIPTION

A script used to SSH to a target Azure Linux VM using Tunneling from Azure Bastion with Azure CLI and PowerShell.
The script will do all of the following:

Remove the breaking change warning messages.
Check if Azure CLI is already installed and, if required, update it to the latest version. If Azure CLI is not installed, install it.
Change the current context to the subscription holding the Azure Bastion host.
Save the Bastion host as a variable and check if it uses the Standard SKU; otherwise, exit the script.
Update the Bastion host to enable native client support, if not already enabled.
Install the ssh extension.
Validate if the target VM exists, and if so, find the subscription it belongs to; otherwise, exit the script.
SSH to the target VM using the native client through Azure Bastion.

.NOTES

Filename:       Connect-SSH-Azure-Linux-VM-using-native-client-via-Azure-Bastion.ps1
Created:        07/03/2023
Last modified:  04/12/2023
Author:         Wim Matthyssen
Version:        2.4
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
.\Connect-SSH-Azure-Linux-VM-using-native-client-via-Azure-Bastion.ps1 <"your VM name here"> <"your User name here">

-> Connect-SSH-Azure-Linux-VM-using-native-client-via-Azure-Bastion.ps1 swpadm023 demo_admin

.LINK

https://wmatthyssen.com/2023/03/09/connecting-to-an-azure-linux-vm-using-an-azure-powershell-script-and-native-client-via-azure-bastion/
#>

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Parameters

param(
    # $vmName -> Name of the target Azure Windows VM
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $vmName,
    # $userName -> Username
    [parameter(Mandatory =$true)][ValidateNotNullOrEmpty()] [string] $userName
    # $password -> Username
)

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Variables

$allSubscriptions = Get-AzSubscription | Where-Object { "Enabled" -eq $_.State}
$subscriptionNameVM = ""
$vmObject = $null

$global:currenttime= Set-PSBreakpoint -Variable currenttime -Mode Read -Action {$global:currenttime= Get-Date -UFormat "%A %m/%d/%Y %R"}
$foregroundColor1 = "Green"
$foregroundColor2 = "Yellow"
$foregroundColor3 = "Red"
$writeEmptyLine = "`n"
$writeSeperatorSpaces = " - "

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Remove the breaking change warning messages

Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true | Out-Null
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script started

Write-Host ($writeEmptyLine + "# Script has started. Without errors and required installations, it can take up to 1 minute to connect to $vmName" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Check if Azure CLI is already installed and, if required, update it to the latest version. If Azure CLI is not installed, install it 

try {
    if ($null -ne (az version)) {
        Write-Host ($writeEmptyLine + "# If needed, the Azure CLI will be updated to the latest version, which can take a few minutes to complete" + $writeSeperatorSpaces + $currentTime)`
        -foregroundcolor $foregroundColor2 $writeEmptyLine
        & az upgrade --yes 2>$null
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

## Change the current context to the subscription holding the Azure Bastion host

# Replace <your subscription purpose name here> with purpose name of your subscription. Example: "*management*"
$subcriptionNameBastion = Get-AzSubscription | Where-Object {$_.Name -like "*management*"}

Set-AzContext -SubscriptionId $subcriptionNameBastion.SubscriptionId | Out-Null
az account set --subscription $subcriptionNameBastion.Name

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
    return
}

Write-Host ($writeEmptyLine + "# Bastion host variable created" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Update the Bastion host to enable native client support, if not already enabled

# Set Azure CLI core configuration to only show errors
az config set core.only_show_errors=yes --output none --only-show-errors

if ((az network bastion show --name $bastion.Name --resource-group $bastion.ResourceGroupName --query "enableTunneling") -ne $true)  {
    Write-Host ($writeEmptyLine + "# Native client support is not enabled. To proceed, it will now be enabled, which can take up to 6 minutes" + $writeSeperatorSpaces + $currentTime)`
    -foregroundcolor $foregroundColor2 $writeEmptyLine
    az network bastion update --name $bastion.Name --resource-group $bastion.ResourceGroupName --enable-tunneling 
} 

Write-Host ($writeEmptyLine + "# Bastion host has native client support enabled" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

## ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Install the ssh extension

az extension add --name ssh --output none --only-show-errors

Write-Host ($writeEmptyLine + "# The extension ssh is installed" + $writeSeperatorSpaces + $currentTime)`
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
    return 
}

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## SSH to the target VM using the native client through Azure Bastion

Write-Host ($writeEmptyLine + "# Setting up an SSH connection to target VM $vmName and signing in. You will be prompted for the password" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor2 $writeEmptyLine

$vm = Get-AzVM -Name $vmName

# Azure CLI
az network bastion ssh --name $bastion.Name  --resource-group $bastion.ResourceGroupName --target-resource-id $vm.Id --auth-type "password" --username $userName

# Set Azure CLI core configuration only show errors to no
az config set core.only_show_errors=no --output none --only-show-errors

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Write script completed

Write-Host ($writeEmptyLine + "# Script completed" + $writeSeperatorSpaces + $currentTime)`
-foregroundcolor $foregroundColor1 $writeEmptyLine 

## ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
