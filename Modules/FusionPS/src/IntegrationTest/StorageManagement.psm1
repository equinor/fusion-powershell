$INGT_CONTAINER = "integration-tests"
$DB_PREFIX = "databases"

function Publish-IntegrationTestDatabase {
    param(
        [string]$Mdf,
        [string]$NewName,
        [string]$StorageResourceGroup = "ProView_Support",
        [string]$StorageAccount = "fusioncommon"
    )

    if (-not (Test-Path -Path $Mdf)) {
        throw "Could not locate mdf file @ path $Mdf"
    }

    $filename = [System.IO.Path]::GetFileNameWithoutExtension($Mdf)
    $tempPath = "$([System.IO.Path]::GetTempFileName()).zip"         # Must end with .zip for compress-archive

    if (-not [string]::IsNullOrEmpty($NewName)) {
        $filename = [System.IO.Path]::GetFileNameWithoutExtension($NewName)
    }

    # Zip the content
    Compress-Archive -Path $Mdf -DestinationPath "$tempPath" -CompressionLevel Optimal -Force -ErrorAction Stop

    $ctx = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroup -Name $StorageAccount
    $container = Get-AzStorageContainer -Name $INGT_CONTAINER -Context $ctx.Context -ErrorAction SilentlyContinue
    if ($null -eq $container) {    
		New-AzStorageContainer -Name $INGT_CONTAINER -Permission Off -Context $ctx.Context
	}

    Set-AzStorageBlobContent -File $tempPath `
                             -Container $INGT_CONTAINER `
                             -Blob "$DB_PREFIX/$filename.zip" `
                             -BlobType Block `
                             -Context $ctx.Context `
                             -Properties @{ ContentType = "application/zip" } `
                             -Force

    Remove-Item $tempPath
}

function Get-IntegrationTestDatabase {
    param(
        [string]$Mdf,
        [Switch]$All,
        [Switch]$Extract,
        [string]$StorageResourceGroup = "proview_support",
        [string]$StorageAccount = "fusioncommon",
        [Switch]$Force     
    )

    $ctx = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroup -Name $StorageAccount
    
    if ([String]::IsNullOrEmpty($Mdf) -and (-not $All.IsPresent)) {
        Show-IntegrationTestDatabases -StorageResourceGroup $StorageResourceGroup -StorageAccount $StorageAccount
        return
    }

    function Get-Blob($blobPath) {
        $dlPath = [System.IO.Path]::GetFileName($blobPath)

        $blob = Get-AzureStorageBlobContent -Container $INGT_CONTAINER -Blob $blobPath -Context $ctx.Context -Destination $dlPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $blob) {
            throw "Could not download blob data from [$INGT_CONTAINER/$blobPath]"
        }

        if ($Extract.IsPresent) {
            Expand-Archive -Path $dlPath -DestinationPath ".\" -Force:$Force.ToBool()
            Remove-Item $dlPath
        } 
    }


    if ($All.IsPresent) {        
        [array]$blobs = Get-AzStorageBlob -Container $INGT_CONTAINER -Prefix $DB_PREFIX -Context $ctx.Context 

        foreach ($blob in $blobs) {
            Write-Host "Downloading $($blob.Name)..."
            Get-Blob -blobPath $blob.Name
        }
    } else {                
        $filename = [System.IO.Path]::GetFileNameWithoutExtension($Mdf)
        $blobPath = "$DB_PREFIX/$filename.zip"

        Get-Blob -blobPath $blobPath
    }
}



function Show-IntegrationTestDatabases {
    param(
        [string]$StorageResourceGroup = "proview_support",
        [string]$StorageAccount = "fusioncommon"
    )

    $ctx = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroup -Name $StorageAccount
    $container = Get-AzStorageContainer -Name $INGT_CONTAINER -Context $ctx.Context -ErrorAction SilentlyContinue

    if ($null -eq $container)
    {
        Write-Host "Container [$INGT_CONTAINER] does not exist"
    }
    else 
    {
        Get-AzStorageBlob -Container $INGT_CONTAINER -Prefix $DB_PREFIX -Context $ctx.Context | Format-List -Property Name,Length,LastModified
    }
}

Export-ModuleMember -Function *