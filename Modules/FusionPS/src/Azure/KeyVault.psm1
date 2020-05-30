

function Set-WebAppMSIKeyVaultPermissions {
	<#
		.SYNOPSIS
			Ensure that the MSI (Managed Service Identity) for a spcified web app has access to the 
			default env key vault. 
	#>
	param(
		$ResourceGroupName,
		$WebAppName,
		$KeyVaultName
	)

	# Get the managed identity 
	$app = Get-AzWebApp -ResourceGroupName $ResourceGroupName -Name $WebAppName
	$servicePrincipalId = $app.identity.PrincipalId

	Write-Host "Found app $($app.Name)"
	Write-Output $app.Identity

	if ($null -eq $servicePrincipalId) {
		# Workaround for shitty vsts ps 
		$sp = Get-AzADServicePrincipal -SearchString $WebAppName
		$servicePrincipalId = $sp.Id
	}

	$sp = Get-AzADServicePrincipal -ObjectId $servicePrincipalId
	$spn = $sp.ApplicationId

	Write-Host "Adding permissions for $servicePrincipalId, spn=$spn to $KeyVaultName"
	Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName -ServicePrincipalName $spn -PermissionsToSecrets get,list,set
}

function Set-EFContextKeyVaultConnectionString {
	<#
		.SYNOPSIS
			Ensure the database connection string for a new database exist in the env key vault.
			This is mainly used by individual service deployments, to make them self contained. 
			Otherwise the main Azure template would have to be updated each time and executed.
	#>
	param(
		$Environment,
		$ContextName,
		$SqlDbName
	)

	$DB_ADMIN_PASSWORD_SECRET_NAME = "DB-AdminPassword"
	$RES_KEYVAULT_NAME = "proview-$Environment-keys"
	$DB_SECRET_NAME = "DB-$ContextName"
	$CONFIG_CONFIG_KEY_PATH = "ConnectionStrings:$ContextName"      ## The connection string will be autoloaded, need to specify where in the config object it should be resolved.
	$ENV_SQL_SERVER_NAME = "proview-sql-$($Environment.ToLower())"


	# Only set key if it's not there already
	$existingKey = Get-AzKeyVaultSecret -VaultName $RES_KEYVAULT_NAME -Name $DB_SECRET_NAME -ErrorAction SilentlyContinue
	if ($null -ne $existingKey) {
		return
	}	

	# Set key vault connection string
	# Get db admin password from the key vault.
	$pwSecret = Get-AzKeyVaultSecret -VaultName $RES_KEYVAULT_NAME -Name $DB_ADMIN_PASSWORD_SECRET_NAME -ErrorAction SilentlyContinue

	if ($null -eq $pwSecret) {
		Write-Host "Could not locate db password in key vault, have proper template been executed?"
		throw "Missing database password secret"
	}
	$DbPassword = $pwSecret.SecretValueText
	$SqlConnectionString = "Server=tcp:$ENV_SQL_SERVER_NAME.database.windows.net,1433;Initial Catalog=$SqlDbName;Persist Security Info=False;User ID=dbadmin;Password=$DbPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
	$secretValue = ConvertTo-SecureString -AsPlainText -Force -String $SqlConnectionString

	Write-Host "Setting DB Connection string to keyvault $RES_KEYVAULT_NAME"
	Set-AzKeyVaultSecret -VaultName $RES_KEYVAULT_NAME -Name $DB_SECRET_NAME -SecretValue $secretValue -ContentType $CONFIG_CONFIG_KEY_PATH -Tag @{Autoload = "True"}
}

Export-ModuleMember -Function *