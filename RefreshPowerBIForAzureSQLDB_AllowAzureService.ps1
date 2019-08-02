<#   
.SYNOPSIS   
    Set Azure SQL Firewall with AllowAllAzureIPs.
    Refresh PowerBI Dataset    
   
.DESCRIPTION   
    This is Azure Automation runbook to run scheduled PowerBI Dataset Refreshes.

.parameter CredentialName
	Name of the credential used in the Shared Resources->Credentials blade

.parameter ClientID
	ClientID generated when created web apps using https://dev.powerbi.com/apps
	
.parameter pbiDatasetName
	DataSet name used in the PowerBI

.Parameter pbiGroupName
	Group Name is the workspace where the dataset is deployed.
	If left "blank" will used the "My Workspace" as group.  

.PARAMETER resourceGroupName
    Name of the resource group to which the database server is 
    assigned.

.PARAMETER serverName  
    Azure SQL Database server name.

.NOTES   
    Author: Rajesh Kotian
    Last Update: April 2018   
#>  

param( 
    [parameter(Mandatory=$true)] 
    [string] $CredentialName,

    [parameter(Mandatory=$true)] 
    [string] $clientId, 
        
    [parameter(Mandatory=$true)] 
    [string] $pbiDatasetName, 
        
    [parameter(Mandatory=$false)] 
    [string] $pbiGroupName,
	
	[parameter(Mandatory=$True)]
	[string] $resourceGroupName,

	[parameter(Mandatory=$True)]
	[string] $serverName
	
	
) 

# Opening up the firewall setting on SQL Server : 

filter timestamp {"[$(Get-Date -Format G)]: $_"}

Write-Output "Script started. Opening up the firewall setting on SQL Server  : " | timestamp

#$credential = Get-AutomationPSCredential -Name "runbookcredential" 
$Connection= Get-AutomationConnection -Name 'AzureClassicRunAsConnection' 
$SPCredential = Get-AutomationPSCredential -Name $CredentialName
$TenantId = $Connection.TenantId
$SubscriptionId = $Connection.SubscriptionId


#login to azure account 
$null = Login-AzureRmAccount -SubscriptionId $SubscriptionId -Credential $SPCredential

New-AzureRmSqlServerFirewallRule `
-ResourceGroupName $resourceGroupName `
-ServerName $serverName `
-AllowAllAzureIPs

Write-Output "Setting firewall on $($serverName) Finished" | timestamp


Write-Output "Starting up the Dataset ${$pbiDatasetName} refresh." | timestamp

# Creating the power BI Refresh Script 

# Get Credential from Automation-Account 
Write-Output "Getting Credential `"$CredentialName`" from stored Automation-Credential ..." 
$Credential = Get-AutomationPSCredential -Name $CredentialName 
 
if ($Credential -eq $null) 
{ 
    throw "Could not retrieve '$CredentialName' credential asset. Check that you created this first in the Automation service." 
}   
# Get the username and password from the SQL Credential 
$pbiUsername = $Credential.UserName
$pbiPassword = $Credential.GetNetworkCredential().Password
Write-Output "Done!"


$authUrl = "https://login.windows.net/common/oauth2/token/"
$body = @{
    "resource" = “https://analysis.windows.net/powerbi/api";
    "client_id" = $clientId;
    "grant_type" = "password";
    "username" = $pbiUsername;
    "password" = $pbiPassword;
    "scope" = "openid"
}

Write-Output "Getting Authentication-Token ..." 
$authResponse = Invoke-RestMethod -Uri $authUrl –Method POST -Body $body
Write-Output "Done!"

$headers = @{
    "Content-Type" = "application/json";
    "Authorization" = $authResponse.token_type + " " + $authResponse.access_token
}

Write-Output "Checking if a GroupName was supplied ..." 

if($PSBoundParameters.ContainsKey("pbiGroupName") -and $pbiGroupName -ne "" -and $pbiGroupName -ne $null)
{
    Write-Output "GroupName was supplied - trying to get the associated GroupID ..."
    $restURL = "https://api.powerbi.com/v1.0/myorg/groups"
    $restResponse = Invoke-RestMethod -Uri $restURL –Method GET -Headers $headers

    $pbiGroupId = ($restResponse.value | Where-Object { $_.name -eq $pbiGroupName }).id

    if($pbiGroupId -eq $null)
    {
        throw "A Group called `"$pbiGroupName`" does not exist!"
    }

    $pbiGroupURI = "/groups/$pbiGroupId"

    Write-Output "GroupName was found - ID = $pbiGroupId!"
}
else
{
    $pbiGroupURI = ""
    Write-Output "GroupName was NOT supplied - Using `"My Workspace`"!"
}

$restURL = "https://api.powerbi.com/v1.0/myorg$pbiGroupURI/datasets"
$restResponse = Invoke-RestMethod -Uri $restURL –Method GET -Headers $headers

Write-Output "Trying to find the Dataset with Name `"$pbiDatasetName`" ..."  
$pbiDatasetId = ($restResponse.value | Where-Object { $_.name -eq $pbiDatasetName }).id

if($pbiDatasetId -eq $null)
{
    throw "A Dataset called `"$pbiDatasetName`" does not exist!"
}

Write-Output "Done!"

Write-Output "Triggering refresh via the API ..." 
$restResponse = Invoke-RestMethod -Uri "$restURL/$pbiDatasetId/refreshes" –Method POST -Headers $headers
Write-Output "Done!"

Start-Sleep -s 5

Write-Output "Getting status of recent refreshes ..."
$restResponse = Invoke-RestMethod -Uri "$restURL/$pbiDatasetId/refreshes/?`$top=5" –Method GET -Headers $headers
Write-Output "Done:"

$restResponse.value | select starttime,endTime,refreshType,status,id


Write-Output "Finishing the Dataset ${$pbiDatasetName} refresh." | timestamp

Write-Output "Closing the firewall on $($serverName)" | timestamp

Get-AzureRmSqlServerFirewallRule -ServerName $serverName  -ResourceGroupName $resourceGroupName |  `
Where-Object {$_.StartIpAddress -eq "0.0.0.0" -and $_.EndIpAddress -eq "0.0.0.0" -and   `
$_.FirewallRuleName -like "AllowAll*AzureIPs"} | Remove-AzureRmSqlServerFirewallRule -Force


Write-Output "Setting firewall on $($serverName) Finished" | timestamp


Write-Output "Script finished successfully." | timestamp

