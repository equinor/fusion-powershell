
$AZURE_SQL_RESOURCE_ID = "https://database.windows.net/"

function Get-FusionAzSqlConnection {
    [OutputType([System.Data.SqlClient.SqlConnection])]
    param(
        [ValidateSet('Test', 'Prod', $null)]
		[InfraEnv]$InfraEnv = $null,
        $SqlServerName,
        $DatabaseName
    )

    if (-not [string]::IsNullOrEmpty($InfraEnv)) {
		if ($InfraEnv -eq 'Prod') { $SqlServerName = "fusion-prod-sqlserver" } 
		else { $SqlServerName = "fusion-test-sqlserver" }
    }
    
    $connectionString = Get-FusionSqlServerConnectionString -SqlServerName $SqlServerName -DatabaseName $DatabaseName
    $accessToken = Get-FusionAzAccessToken -Resource $AZURE_SQL_RESOURCE_ID

    $SqlConnection = new-object System.Data.SqlClient.SqlConnection
    $SqlConnection.ConnectionString = $connectionString
    $SqlConnection.AccessToken = $accessToken

    return $SqlConnection
}

function New-FusionAzSqlMigration {
    param(
        $SqlFile,
        [ValidateSet('Test', 'Prod')]
		[string]$InfraEnv = $null,
        $SqlServerName,
        $DatabaseName
    )

    if (-not [IO.File]::Exists($SqlFile)) {
        throw "Could not locate file $SqlFile"
    }

    $content = [IO.File]::ReadAllText($SqlFile)
    $batches = $content -split "[\r\n]*GO[\r\n]*"

    $SqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    # Is ok to print the sql connection, as there is no credentials used.
    Write-Host "Executing migration on sql connection: "
    Write-Host $SqlConnection.ConnectionString  

    $SqlConnection.Open()

    Write-Host "$($batches.Count) blocks to execute"
    Write-Host "Starting transaction..."    
    $transaction = $SqlConnection.BeginTransaction("EF Migration");

    foreach($batch in $batches)
    {
        if ($batch.Trim() -ne "") {
            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
            $SqlCmd.CommandText = $batch
            $SqlCmd.Connection = $SqlConnection
            $SqlCmd.Transaction = $transaction
            $rowsAffected = $SqlCmd.ExecuteNonQuery()

            if ($rowsAffected -gt 0) {
                Write-Host $batch
            } else {
                Write-Host "`tBatch -> No rows affected.."
            }
        }
    }
    Write-Host "Done. Commiting..."
    $transaction.Commit()
    $SqlConnection.Close()
}

function Set-FusionAzSqlDatabaseAccess {
    param(
        [ValidateSet('Test', 'Prod')]
		[string]$InfraEnv,
        $Environment,
        $DatabaseName
    )

	$clientId = @("5a842df8-3238-415d-b168-9f16a6a6031b", "97978493-9777-4d48-b38a-67b0b9cd88d2")[$Environment -eq "fprd"]
    Set-FusionAzSqlServicePrincipalAccess -InfraEnv $InfraEnv -ApplicationId $clientId -DatabaseName $DatabaseName
}

function Set-FusionAzSqlServicePrincipalAccess {
    param(
        [ValidateSet('Test', 'Prod', $null)]
		[string]$InfraEnv = $null,
        $ServicePrincipalName,
        $ApplicationId,
        $SqlServerName,
        $DatabaseName
    )
    
    $sqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    if ([string]::IsNullOrEmpty($ApplicationId)) {
        Write-Host "Resolving ad app for client id $ApplicationId..."
        $adApp = Get-AzADApplication -ApplicationId $ApplicationId
        $ServicePrincipalName = $adApp.DisplayName
    }

    Write-Host "Ensuring service principal [$ServicePrincipalName] user on database $DatabaseName..."

    $sql = @"
      if not exists(select * from sys.sysusers where name = '$ServicePrincipalName') 
      BEGIN
        CREATE USER [$ServicePrincipalName] FROM EXTERNAL PROVIDER;
        ALTER ROLE db_datareader ADD MEMBER [$ServicePrincipalName];
        ALTER ROLE db_datawriter ADD MEMBER [$ServicePrincipalName];
      END
"@

    $sqlConnection.Open()
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $sql
    $SqlCmd.Connection  = $sqlConnection    
    $SqlCmd.ExecuteNonQuery() | Out-Null

    Write-Host "Done."

    $sqlConnection.Close()
}

function Invoke-FusionAzSqlScript {
    [OutputType([int])]
    param(
        [ValidateSet('Test', 'Prod', $null)]
		[string]$InfraEnv = $null,
        $SqlServerName,
        $DatabaseName,
        [string]$SqlCmd
    )

    $sqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    $sqlConnection.Open()
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlCmd
    $SqlCmd.Connection  = $sqlConnection    
    $affectedRows = $SqlCmd.ExecuteNonQuery()

    $sqlConnection.Close()

    return $affectedRows
}

Export-ModuleMember -Function *