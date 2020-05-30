$RUNTIME_OPTIONS_CONTAINER = "config"

function Get-RuntimeOptions {
	param(
		[string]$Environment,
		[string]$Key,
		[string]$Variation = $null
	)
	
	$blobPath = "runtime-opts/$Key"
	$blobPathVariation = "runtime-opts/$Variation/$Key"
		
	$ctx = Get-AzStorageAccount -ResourceGroupName "ProView_$Environment" -Name "proview$($Environment.ToLower())"
	$container = Get-AzStorageContainer -Name $RUNTIME_OPTIONS_CONTAINER -Context $ctx.Context -ErrorAction SilentlyContinue

	if ($null -ne $container) {
		$tmpBlobFile = [System.IO.Path]::GetTempFileName()

		$blob = $null
		if (![string]::IsNullOrEmpty($Variation)) {
			$blob = Get-AzStorageBlobContent -Container $RUNTIME_OPTIONS_CONTAINER -Blob $blobPathVariation -Context $ctx.Context -Destination $tmpBlobFile -Force -ErrorAction SilentlyContinue				
		}
		if ($null -eq $blob) {
			$blob = Get-AzStorageBlobContent -Container $RUNTIME_OPTIONS_CONTAINER -Blob $blobPath -Context $ctx.Context -Destination $tmpBlobFile -Force -ErrorAction SilentlyContinue
		}

		if ($null -eq $blob) {
			Remove-Item $tmpBlobFile
			return $null
		}

		$blobContent = Get-Content $tmpBlobFile | ConvertFrom-Json
		Remove-Item $tmpBlobFile

		return $blobContent
	}
	
	return $null
}

function Set-RuntimeOptions {
	param(
		[string]$Environment,
		[string]$Key,
		[string]$Variation,
		$Options
	)

	$blobPath = "runtime-opts/$Key"
	if (![string]::IsNullOrEmpty($Variation)) {
		$blobPath = "runtime-opts/$Variation/$Key"
	}

	$ctx = Get-AzStorageAccount -ResourceGroupName "ProView_$Environment" -Name "proview$($Environment.ToLower())"
	$container = Get-AzStorageContainer -Name $RUNTIME_OPTIONS_CONTAINER -Context $ctx.Context -ErrorAction SilentlyContinue
	if ($null -eq $container) {
		New-AzStorageContainer -Name $RUNTIME_OPTIONS_CONTAINER -Permission Off -Context $ctx.Context
	}

	$tmpBlobFile = [System.IO.Path]::GetTempFileName()
	ConvertTo-Json -InputObject $Options -Depth 20 | Out-File $tmpBlobFile -Force -Encoding utf8

	Set-AzStorageBlobContent -File $tmpBlobFile -Container $RUNTIME_OPTIONS_CONTAINER -Blob $blobPath -BlobType Block -Context $ctx.Context -Properties @{ ContentType = "application/json" } -Force

	Remove-Item $tmpBlobFile
}

Export-ModuleMember -Function *-RuntimeOptions