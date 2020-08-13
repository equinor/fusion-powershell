
$AZURE_SQL_RESOURCE_ID = "https://database.windows.net/"

function Get-FusionAzSqlConnection {
    [OutputType([System.Data.SqlClient.SqlConnection])]
    param(
        $SqlServerName,
        $DatabaseName
    )

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
        $SqlServerName,
        $DatabaseName
    )

    if (-not [IO.File]::Exists($SqlFile)) {
        throw "Could not locate file $SqlFile"
    }

    $content = [IO.File]::ReadAllText($SqlFile)
    $batches = $content -split "[\r\n]*GO[\r\n]*"

    $SqlConnection = Get-FusionAzSqlConnection -SqlServerName $SqlServerName -DatabaseName $DatabaseName

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

function Set-FusionAzSqlServicePrincipalAccess {
    param(
        $ServicePrincipalName,
        $SqlServerName,
        $DatabaseName
    )
    
    $sqlConnection = Get-FusionAzSqlConnection -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    Write-Host "Ensuring service principal [$ServicePrincipalName] user on database $DatabaseName..."

    $sql = @"
      if not exists(select * from sys.sysusers where name = '$ServicePrincipalName') 
      BEGIN
        CREATE USER [$ServicePrincipalName] FROM EXTERNAL PROVIDER;
        ALTER ROLE db_datareader ADD MEMBER [$ServicePrincipalName];
        ALTER ROLE db_datawriter ADD MEMBER [$ServicePrincipalName];
      END
"@

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $sql
    $SqlCmd.Connection  = $sqlConnection    
    $affectedRows = $SqlCmd.ExecuteNonQuery()

    if ($affectedRows -gt 0) {
        Write-Host "User added"
    } else {
        Write-Host "User already exists"
    }

    $sqlConnection.Close()
}

function Invoke-FusionAzSqlScript {
    [OutputType([int])]
    param(
        $SqlServerName,
        $DatabaseName,
        [string]$SqlCmd
    )

    $sqlConnection = Get-FusionAzSqlConnection -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $SqlCmd
    $SqlCmd.Connection  = $sqlConnection    
    $affectedRows = $SqlCmd.ExecuteNonQuery()

    $sqlConnection.Close()

    return $affectedRows
}

Export-ModuleMember -Function *