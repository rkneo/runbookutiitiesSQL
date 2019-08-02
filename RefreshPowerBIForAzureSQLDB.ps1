param( 
    [parameter(Mandatory=$true)] 
    [string] $CredentialName,

    [parameter(Mandatory=$true)] 
    [string] $clientId, 
        
    [parameter(Mandatory=$true)] 
    [string] $pbiDatasetName, 
        
    [parameter(Mandatory=$false)] 
    [string] $pbiGroupName
) 
# Create Azure AD Application for PowerBI: 
# https://dev.powerbi.com/apps

# PowerBI REST API Reference:
# https://msdn.microsoft.com/en-us/library/mt203551.aspx#

#https://docs.microsoft.com/en-us/azure/data-lake-store/data-lake-store-get-started-rest-api

#$VerbosePreference = Continue

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