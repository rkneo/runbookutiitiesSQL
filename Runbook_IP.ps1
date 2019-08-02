<#   
    Description :  Whitelist Runbook IP to the AAS firewall
    Author: Rajesh Kotian
    Last Updated: July 2018      
#>  

#parameters
Param 
(
    [Parameter(Mandatory = $true)]
	[string]$resourceGroupName,
    
	[Parameter(Mandatory = $true)]
	[string]$analysisServicesName,
    
	#AAS Database Name
	[parameter(Mandatory=$true)]
	[string] $AASDatabaseName,

	#AAS Table Name
	[parameter(Mandatory=$true)]
	[string] $AASTableName
)

function Add-AnalysisServicesFirewallRule($props, $firewallRuleName, $rangeStart, $rangeEnd) {
    # Check if the rule exists
    "Checking Rule Exists - Running Add-AnalysisServicesFirewallRule"

    $existingRules = $props.ipV4FirewallSettings.firewallRules | `
        Where-Object {$_.firewallRuleName -eq $firewallRuleName}

    # Add the rule if needed
    if ($existingRules -eq $null) {
        # Create the rule object
        $ruleProperties = [ordered]@{
            "firewallRuleName" = $firewallRuleName;
            "rangeStart"       = $rangeStart;
            "rangeEnd"         = $rangeEnd;
        }
        $rule = New-Object -TypeName PSObject
        $rule | Add-Member -NotePropertyMembers $ruleProperties

        # Add the rule 
        "Adding the Rule - Running Add-AnalysisServicesFirewallRule"
        $rules = [System.Collections.ArrayList]$props.ipV4FirewallSettings.firewallRules
        $index = $rules.Add($rule)
        $props.ipV4FirewallSettings.firewallRules = $rules
    }
}


filter timestamp {"[$(Get-Date -Format G)]: $_"}

Write-Output "Script started." | timestamp

#fetching Credentials to process model
$SPCredential = Get-AutomationPSCredential -Name 'runbookcredential'

$firewallRuleName = "Runbook_IP"

try
{
    #processing the Cube
    Invoke-ProcessTable -Database $AASDatabaseName -TableName $AASTableName -Server $analysisServicesName -RefreshType "Full" -Credential $SPCredential  -ErrorAction Stop
    Write-Output "Script finished." | timestamp
}
catch
{
	#capturing the error message - IP address
    $ErrorMessage = $_.Exception.Message
    $ErrorMessage
    $exception = $ErrorMessage.ToUpper()
    
    if ($exception.IndexOf("TO ENABLE ACCESS, USE THE AZURE MANAGEMENT PORTAL") -nq 0)
    {
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
        
            $rangeStart = $ipaddress
            $rangeEnd = $ipaddress
        
            'Get the AnalysisServices resource properties'

            $resource = Get-AzureRmResource `
                -ResourceGroupName $resourceGroupName `
                -ResourceType "Microsoft.AnalysisServices/servers" `
                -ResourceName $analysisServicesName

            $props = $resource.Properties

            Add-AnalysisServicesFirewallRule $props $firewallRuleName $rangeStart $rangeEnd

            Set-AzureRmResource `
                -PropertyObject $props `
                -ResourceGroupName $resourceGroupName `
                -ResourceType "Microsoft.AnalysisServices/servers" `
                -ResourceName $analysisServicesName `
                -Force

        }
        
    }

    "IP Runbook applied to AAS firewall"
}


