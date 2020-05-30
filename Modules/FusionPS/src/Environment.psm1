

$CONFIG_CONTAINER = "config"
$PARAMS_BLOBPATH = "env-params.json"

function Set-EnvironmentParams {
	<#
	.SYNOPSIS
		The script will store environment config to the default blob storage, for easy access 
		to subsequent deploys.
	#>
	param(
		[string]$Environment
	)

	if ([string]::IsNullOrEmpty($Environment)) {
		throw "Missing parameter, -EnvironemntName"
	}

	if ([string]::IsNullOrEmpty($env:EnvironmentParamsFile)) {
		throw "Missing environment params file, should be in the env variable EnvironmentParamsFile"
	}

	$paramsFile = Get-Content $env:EnvironmentParamsFile | Out-String | ConvertFrom-Json
	Write-Host "Found params file"
	Write-Host (ConvertTo-Json -InputObject $paramsFile)

	## Get instrument key
	$ai = Get-AzResource -ResourceGroupName "proview_$Environment" -ResourceType "microsoft.insights/components" -Name $paramsFile.applicationInsightName -ExpandProperties

	$configValues = @{
		EnvKeyVault = @{ ConfigPath = "KeyVaultUri"; Value = "https://$($paramsFile.keyVaultName).vault.azure.net" }
		SharedKeyVault = @{ ConfigPath = "KeyVaultUri-Shared"; Value = "https://proview-shared-secrets.vault.azure.net" }
		CertThumbprint = @{ ConfigPath = "Config:CertThumbprint"; Value = $paramsFile.certThumbprint }
		Environment = @{ ConfigPath = "Config:Environment"; Value = $Environment }
		AppInsights = @{ ConfigPath = "ApplicationInsights:InstrumentationKey"; Value = $ai.Properties.InstrumentationKey }
		TenantId = @{ ConfigPath = "AzureAd:TenantId"; Value = $ai.Properties.TenantId }
		ClientId = @{ ConfigPath = "AzureAd:ClientId"; Value = $paramsFile.clientId }
		AppProxyResource = @{ ConfigPath = "AzureAd:ApplicationProxy:Resource"; Value = $paramsFile.onPremRresource }
		AppSettings = @{}
	}

	$configValues.AppSettings = @{
		"KeyVaultUri" = $configValues.EnvKeyVault.Value
		"KeyVaultUri-Shared" = $configValues.SharedKeyVault.Value
		"Config:CertThumbprint" = $configValues.CertThumbprint.Value
		"Config:Environment" = $configValues.Environment.Value
		"ApplicationInsights:InstrumentationKey" = $configValues.AppInsights.Value
		"AzureAd:TenantId" = $configValues.TenantId.Value
		"AzureAd:ClientId" = $configValues.ClientId.Value
		"AzureAd:ApplicationProxy:Resource" = $configValues.AppProxyResource.Value
	}

	Write-Host "Generated param file"
	ConvertTo-Json -InputObject $configValues -Depth 20
	ConvertTo-Json -InputObject $configValues -Depth 20 | Out-File ".\environment-params.json" -Force -Encoding utf8

	$ctx = Get-AzStorageAccount -ResourceGroupName "ProView_$Environment" -Name "proview$($Environment.ToLower())"
	$container = Get-AzStorageContainer -Name $CONFIG_CONTAINER -Context $ctx.Context -ErrorAction SilentlyContinue
	if ($null -eq $container) {
		New-AzStorageContainer -Name $CONFIG_CONTAINER -Permission Off -Context $ctx.Context
	}
	Set-AzStorageBlobContent -File .\environment-params.json `
								-Container $CONFIG_CONTAINER `
								-Blob $PARAMS_BLOBPATH `
								-BlobType Block `
								-Context $ctx.Context `
								-Properties @{ ContentType = "application/json" } `
								-Force

	Write-Verbose "Removing temp file"
	Remove-Item ".\environment-params.json"
}

function Get-EnvironmentParams {
	<#
		.SYNOPSIS
			The script will get environment config stored to the default blob storage, for easy access 
			to subsequent deploys.

			Returns Hashtable with properties:
			
				Each property value is in the format of 
					@{ ConfigPath = "Path:to:config:in:Appsettings"; Value = "..." }

				{
					EnvKeyVault
					SharedKeyVault
					CertThumbprint 
					Environment
					AppInsights
					TenantId
					ClientId
					AppProxyResource

					AppSettings = @{ [precompiled app settings hashtable from values above] }
				}
	#>
	[OutputType([System.Collections.Hashtable])]
	param(
		[string]$Environment
	)

	if ([string]::IsNullOrEmpty($Environment)) {
		throw "Missing parameter, -EnvironemntName"
	}

	$ctx = Get-AzStorageAccount -ResourceGroupName "ProView_$Environment" -Name "proview$($Environment.ToLower())"
	$container = Get-AzStorageContainer -Name $CONFIG_CONTAINER -Context $ctx.Context -ErrorAction SilentlyContinue
	if ($null -eq $container) {
		throw "No config blob found"
	}

	$tmpBlobFile = [System.IO.Path]::GetTempFileName()

	$blob = Get-AzStorageBlobContent -Container $CONFIG_CONTAINER -Blob $PARAMS_BLOBPATH -Context $ctx.Context -Destination $tmpBlobFile -Force -ErrorAction SilentlyContinue
	if ($null -eq $blob) {
		throw "Could not download blob data from [$CONFIG_CONTAINER/$PARAMS_BLOBPATH]"
	}

	$blobContent = Get-Content $tmpBlobFile | ConvertFrom-Json
	Remove-Item $tmpBlobFile
	return $blobContent
}

function Get-CurrentPullRequestNumber {

	# Predefined variables - last one is used when github prs.

	# System.PullRequest.PullRequestId
	# System.PullRequest.PullRequestNumber

	if (-not [string]::IsNullOrEmpty($env:SYSTEM_PULLREQUEST_PULLREQUESTID)) {
		return $env:SYSTEM_PULLREQUEST_PULLREQUESTID
	}

	if (-not [string]::IsNullOrEmpty($env:SYSTEM_PULLREQUEST_PULLREQUESTNUMBER)) {
		return $env:SYSTEM_PULLREQUEST_PULLREQUESTNUMBER
	}

	## Fallback
	$sourceBranch = $env:BUILD_SOURCEBRANCH

	if ($sourceBranch -match "/pull/(\d+)/merge") {
		return $matches[1]
	}

	return $null
}

Export-ModuleMember -Function *-EnvironmentParams, Get-CurrentPullRequestNumber