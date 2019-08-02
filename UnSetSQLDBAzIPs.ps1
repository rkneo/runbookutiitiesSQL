<#   
.SYNOPSIS   
    Set Azure SQL Firewall with AllowAllAzureIPs.    
   
.DESCRIPTION   
    This Azure Automation runbook to toggle AllowAllAzureIPs to OFF.

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
[parameter(Mandatory=$True)]
[string] $resourceGroupName = "rajeshtestRaa",

[parameter(Mandatory=$True)]
[string] $serverName = "raacensusdatasrv"

)

filter timestamp {"[$(Get-Date -Format G)]: $_"}

Write-Output "Script started." | timestamp

#$credential = Get-AutomationPSCredential -Name "runbookcredential" 
$Connection= Get-AutomationConnection -Name 'AzureClassicRunAsConnection' 
$SPCredential = Get-AutomationPSCredential -Name 'runbookcredential'
$TenantId = $Connection.TenantId
$SubscriptionId = $Connection.SubscriptionId



#login to azure account 
$null = Login-AzureRmAccount -SubscriptionId $SubscriptionId -Credential $SPCredential

Get-AzureRmSqlServerFirewallRule -ServerName $serverName  -ResourceGroupName $resourceGroupName |  `
Where-Object {$_.StartIpAddress -eq "0.0.0.0" -and $_.EndIpAddress -eq "0.0.0.0" -and   `
$_.FirewallRuleName -like "AllowAll*AzureIPs"} | Remove-AzureRmSqlServerFirewallRule -Force

Write-Output "Setting firewall on $($serverName)" | timestamp


Write-Output "Script finished." | timestamp