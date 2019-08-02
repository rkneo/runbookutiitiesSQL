<#   
    Description :   Removing AAS Whitelisted IP from the SQL Server firewall
    Author: Rajesh Kotian
    Last Updated: July 2019      
#>  

#parameters
param(

#SQL Server Name
[parameter(Mandatory=$true)]
[string] $SQLServerName,

#SQL Resource Name
[parameter(Mandatory=$true)]
[string] $SQLServerResourceName

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
    Connect-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
}
catch 
{
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

"Removing Whitelisted AAS IP......."

Remove-AzureRmSqlServerFirewallRule -FirewallRuleName "AAS_IP" `
                                    -ResourceGroupName $SQLServerResourceName `
                                    -ServerName $SQLServerName       

"Completed Removing Whitelisted AAS IP"

