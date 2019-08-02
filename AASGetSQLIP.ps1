<#   
    Description :   The runbook will process AAS and Captures errored firewall IP. 
                    Writes  the IP to Blob storage
    Author: Rajesh Kotian
    Last Updated: June 2019      
#>  

#parameters
param(
# AAS resource group 
[parameter(Mandatory=$true)]
[string] $resourceGroupName,

#AAS Server Name
[parameter(Mandatory=$true)]
[string] $serverName,

#AAS Database Name
[parameter(Mandatory=$true)]
[string] $DatabaseName,

#AAS Table Name
[parameter(Mandatory=$true)]
[string] $TableName,

#Blob Storage account name for writing IP to
[parameter(Mandatory=$true)]
[string] $StorageAccountName,

#Blob Storage account Key
[parameter(Mandatory=$true)]
[string] $StorageAccountKey
)

filter timestamp {"[$(Get-Date -Format G)]: $_"}

Write-Output "Script started." | timestamp

#fetching Credentials to process model
$SPCredential = Get-AutomationPSCredential -Name 'runbookcredential'

#fetching the connection for making SQL Firewall changes
$connectionName = "AzureRunAsConnection"
    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

        "Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint    
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }

try
{
    #processing the Cube
    Invoke-ProcessTable -Database $DatabaseName -TableName $TableName -Server $serverName -RefreshType "Full" -Credential $SPCredential  -ErrorAction Stop
    Write-Output "Script finished." | timestamp
}
catch
{
    #capturing the error message - IP address
    $ErrorMessage = $_.Exception.Message
    $ErrorMessage
    $exception = $ErrorMessage.ToUpper()
    $startpos=$exception.IndexOf("CLIENT WITH IP ADDRESS '") + ("CLIENT WITH IP ADDRESS '").Length
    $endpos=$exception.IndexOf("' IS NOT ALLOWED TO ACCESS THE SERVER")
    if ($startpos -ne 0)
    {

        $iplen=$endpos-$startpos
        $ipaddress=$exception.substring($startpos,$iplen)
        Write-Output $ipaddress
        #Writing the file to the blob
        $ipaddressfile = "ipaddressfile.ip" 
        $LogItem = New-Item -ItemType File -Name $ipaddressfile

        $ipaddress | Out-File -FilePath $ipaddressfile
        $ctx = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
        Set-AzureStorageBlobContent -File $ipaddressfile -Container "ipaddresstxt" -context $ctx -Force
    }

}
