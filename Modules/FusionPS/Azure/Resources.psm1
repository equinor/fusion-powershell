
Import-Module Az.Sql

function Get-ServiceSqlDatabaseName {
	<#
	.SYNOPSIS
	Generate an environment postfixed database following default service database naming convention.
	The prefix should be the domain specific area - like "Fusion-Roles"

	The final database name will be "[PREFIX]-DB-[ENVIRONMENT]".
	
	.PARAMETER Environment
	Fusion environment name, like "CI", "PR", "FQA" or "FPRD"
	
	.PARAMETER DatabasePrefix
	The main name of the database. This should indicate what domain it belongs to etc. Like Org/People etc.
	
	.PARAMETER PullRequest
	Will postfix the pull request id "-[PRID]" to the database name. If empty or null, nothing is done.
	Final name will be "Fusion-Org-DB-PR-[PRID]"
	
	.EXAMPLE
	Get-ServiceSqlDatabaseName -Environment PR -DatabasePrefix "Fusion-Roles" -PullRequest 2974
	Get-ServiceSqlDatabaseName -Environment CI -DatabasePrefix "Fusion-Roles"	
	#>
	param(
		[string]$Environment,
		[string]$DatabasePrefix,
		[string]$PullRequest = $null
	)
	
	if (-not [string]::IsNullOrEmpty($PullRequest)) {
		return "$DatabasePrefix-DB-$Environment-$PullRequest"
	} else {
		return "$DatabasePrefix-DB-$Environment"
	}
}

function Get-FusionSqlServer {
    [OutputType([Microsoft.Azure.Commands.Sql.Server.Model.AzureSqlServerModel])]    
    param(
		[ValidateSet('Test', 'Prod', $null)]
		[string]$InfraEnv = $null,
        $SqlServerName = $null
	)

	if (-not [string]::IsNullOrEmpty($InfraEnv)) {
		if ($InfraEnv -eq 'Prod') { $sqlServerName = "fusion-prod-sqlserver" } 
		else { $sqlServerName = "fusion-test-sqlserver" }
	}

    $dbResource = Get-AzSqlServer | Where-Object -Property ServerName -eq $SqlServerName | Select-Object -First 1
    return $dbResource;    
}

function Get-FusionSqlServerConnectionString {
    [OutputType([string])]
    param(
		[ValidateSet('Test', 'Prod', $null)]
		[string]$InfraEnv = $null,
        $SqlServerName,
        $DatabaseName,
        $Timeout = 30
    )

    $sqlServer = Get-FusionSqlServer -InfraEnv $InfraEnv -SqlServerName $SqlServerName

    return "Server=tcp:$($sqlServer.FullyQualifiedDomainName),1433;Initial Catalog=$DatabaseName;Persist Security Info=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=$Timeout;"
}

Export-ModuleMember -Function *