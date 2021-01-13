
$AZURE_SQL_RESOURCE_ID = "https://database.windows.net/"

function Get-FusionAzSqlConnection {
    [OutputType([System.Data.SqlClient.SqlConnection])]
    param(
        [ValidateSet('Test', 'Prod', $null)]
		[string]$InfraEnv = $null,
        $SqlServerName,
        $DatabaseName,
        $Timeout = 30
    )

    if (-not [string]::IsNullOrEmpty($InfraEnv)) {
		if ($InfraEnv -eq 'Prod') { $SqlServerName = "fusion-prod-sqlserver" } 
		else { $SqlServerName = "fusion-test-sqlserver" }
    }
    
    $connectionString = Get-FusionSqlServerConnectionString -SqlServerName $SqlServerName -DatabaseName $DatabaseName -Timeout $Timeout
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
    $batches = $content -split "[\r\n]+\bGO\b[\r\n]+"

    $SqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName -Timeout 200

    # Is ok to print the sql connection, as there is no credentials used.
    Write-Host "Executing migration on sql connection: "
    Write-Host $SqlConnection.ConnectionString  

    $SqlConnection.Open()
    
    Write-Host "$($batches.Count) blocks to execute"
    Write-Host "Starting transaction..."    
    $transaction = $SqlConnection.BeginTransaction("EF Migration");

    $index = 0
    foreach($batch in $batches)
    {
        $index++

        if ($batch.Trim() -ne "") {
            Write-Host "-- Statement $index"
            Write-Host $batch

            $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
            $SqlCmd.CommandText = $batch
            $SqlCmd.CommandTimeout = 600
            $SqlCmd.Connection = $SqlConnection
            $SqlCmd.Transaction = $transaction
            $rowsAffected = $SqlCmd.ExecuteNonQuery()

            if ($rowsAffected -gt 0) {
                Write-Host "$rowsAffected rows affected"
            }

            Write-Host ""
            Write-Host "----------------------------------------"
            Write-Host ""
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
        [Parameter(Mandatory=$true)]
        $ApplicationId,
        $SqlServerName,
        [Parameter(Mandatory=$true)]
        $DatabaseName
    )
    
    $sqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    Write-Host "Resolving ad app for client id $ApplicationId..."
    $adApp = Get-AzADApplication -ApplicationId $ApplicationId
    $ServicePrincipalName = $adApp.DisplayName

    function ConvertTo-Sid {
        param (
            [string]$appId
        )
        [guid]$guid = [System.Guid]::Parse($appId)
        foreach ($byte in $guid.ToByteArray()) {
            $byteGuid += [System.String]::Format("{0:X2}", $byte)
        }
        return "0x" + $byteGuid
    }

    $SID = ConvertTo-Sid -appId $clientId

    Write-Host "Ensuring service principal [$ServicePrincipalName] user on database $DatabaseName..."

    $sql = @"
      if not exists(select * from sys.sysusers where name = '$ServicePrincipalName') 
      BEGIN
        CREATE USER [$ServicePrincipalName] WITH DEFAULT_SCHEMA=[dbo], SID = $SID, TYPE = E;
      END
      ALTER ROLE db_datareader ADD MEMBER [$ServicePrincipalName];
      ALTER ROLE db_datawriter ADD MEMBER [$ServicePrincipalName];
"@

    $sqlConnection.Open()
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.CommandText = $sql
    $SqlCmd.Connection  = $sqlConnection    
    $SqlCmd.ExecuteNonQuery() | Out-Null

    Write-Host "Done."

    $sqlConnection.Close()
}

function Set-FusionAzSqlUserAccess {
    param(
        [ValidateSet('Test', 'Prod', $null)]
        [string]$InfraEnv = $null,
        [string]$ObjectId,
        [string]$Mail,
        [Parameter(Mandatory=$true)]
        $DatabaseName
    )
    
    $sqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    if ([string]::IsNullOrEmpty($ObjectId) -and [string]::IsNullOrEmpty($Mail)) {
        throw "Either mail or object id has to be used"
    }

    $user = $null

    if (-not [string]::IsNullOrEmpty($Mail)) {
        Write-Host "Resolving user by mail [$Mail]"
        $user = Get-AzADUser -Mail $Mail
        if ($null -eq $user) {
            throw "Could not locate user"
        }
    } else {
        Write-Host "Resolving user by object id [$ObjectId]"
        $user = Get-AzADUser -ObjectId $ObjectId
    }

    function ConvertTo-Sid {
        param (
            [string]$objectId
        )
        [guid]$guid = [System.Guid]::Parse($objectId)
        foreach ($byte in $guid.ToByteArray()) {
            $byteGuid += [System.String]::Format("{0:X2}", $byte)
        }
        return "0x" + $byteGuid
    }

    $SID = ConvertTo-Sid -objectId $user.Id

    $username = $user.UserPrincipalName
    Write-Host "Ensuring user [$($user.DisplayName) ($username)] user on database $DatabaseName..."

    $sql = @"
      if not exists(select * from sys.sysusers where name = '$username') 
      BEGIN
        CREATE USER [$username] WITH DEFAULT_SCHEMA=[dbo], SID = $SID, TYPE = E;
      END
      ALTER ROLE db_datareader ADD MEMBER [$username];
      ALTER ROLE db_datawriter ADD MEMBER [$username];
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
        [string]$SqlCmd,
        [string]$SqlFile
    )

    $sqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    if (-not [string]::IsNullOrEmpty($SqlFile)) {
        if (Test-Path -Path $SqlFile) {
            $SqlCmd = [System.IO.File]::ReadAllText($SqlFile)
        } else {
            throw "Could not locate sql file @ $SqlFile"
        }
    }

    if ([string]::IsNullOrEmpty($SqlCmd)) {
        throw "Must specify sql to execute"
    }

    $sqlConnection.Open()
    $sqlcommand = New-Object System.Data.SqlClient.SqlCommand
    $sqlcommand.CommandText = $SqlCmd
    $sqlcommand.Connection  = $sqlConnection    
    $affectedRows = $sqlcommand.ExecuteNonQuery()

    $sqlConnection.Close()

    return $affectedRows
}

function Invoke-FusionAzSqlSelectScript {
    [OutputType('System.Data.DataTable')]
    param(
        [ValidateSet('Test', 'Prod', $null)]
		[string]$InfraEnv = $null,
        $SqlServerName,
        $DatabaseName,
        [string]$Query,
        [string]$SqlFile
    )

    $sqlConnection = Get-FusionAzSqlConnection -InfraEnv $InfraEnv -SqlServerName $SqlServerName -DatabaseName $DatabaseName

    if (-not [string]::IsNullOrEmpty($SqlFile)) {
        if (Test-Path -Path $SqlFile) {
            $Query = [System.IO.File]::ReadAllText($SqlFile)
        } else {
            throw "Could not locate sql file @ $SqlFile"
        }
    }

    if ([string]::IsNullOrEmpty($Query)) {
        throw "Must specify sql query to execute (-Query)"
    }

    $sqlConnection.Open()

    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlCmd.Connection = $sqlConnection
    $sqlCmd.CommandText = $Query

    $dataTable = New-Object System.Data.DataTable
    $sqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $sqlAdapter.SelectCommand = $sqlCmd
    $rows = $sqlAdapter.Fill($dataTable)
    $sqlConnection.Close()

    Write-Verbose "$rows Rows selected"
    return $dataTable
}


Export-ModuleMember -Function *