<#   
    Description :   The runbook will process AAS and Captures errored firewall IP. 
                    Whitelist IP to the SQL Server firewall
    Author: Rajesh Kotian
    Last Updated: June 2019      
#>  

#parameters
param(
# AAS resource group 
	[parameter(Mandatory=$true)]
	[string] $AASResourceGroupName,

	#AAS Server Name
	[parameter(Mandatory=$true)]
	[string] $AASServerName,

	#AAS Database Name
	[parameter(Mandatory=$true)]
	[string] $AASDatabaseName,

	#AAS Table Name
	[parameter(Mandatory=$true)]
	[string] $AASTableName,

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

try
{
    #processing the Cube
    Invoke-ProcessTable -Database $AASDatabaseName -TableName $AASTableName -Server $AASServerName -RefreshType "Full" -Credential $SPCredential  -ErrorAction Stop
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

        try
        {
                New-AzureRmSqlServerFirewallRule -ResourceGroupName $SQLServerResourceName `
                    -ServerName $SQLServerName `
                    -FirewallRuleName "AAS_IP" `
                    -StartIpAddress $ipaddress `
                    -EndIpAddress $ipaddress

        }
        catch
        {
                Set-AzureRmSqlServerFirewallRule -ResourceGroupName $SQLServerResourceName `
                    -ServerName $SQLServerName `
                    -FirewallRuleName "AAS_IP" `
                    -StartIpAddress $ipaddress `
                    -EndIpAddress $ipaddress
        }

    }

}
