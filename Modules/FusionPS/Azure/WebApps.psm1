

function Set-FusionAzWebAppSettings {
    [OutputType([hashtable])]
    param(
        $Name,
        $Slot = $null,
        [hashtable]$AppSettings,
        [switch]$Replace
    )

    $webAppResource = Get-AzResource -ResourceType Microsoft.Web/sites | Where-Object -Property Name -eq $Name | Select-Object -First 1

    if ($null -eq $webAppResource) { throw "Could not locate app [$Name]" }

    $isSlot = -not [string]::IsNullOrEmpty($Slot) 
    if ($isSlot -eq $false) {
        $webApp = Get-AzWebApp -Name $webAppResource.Name -ResourceGroupName $webAppResource.ResourceGroupName
    } else {
        $webApp = Get-AzWebAppSlot -Name $webAppResource.Name -ResourceGroupName $webAppResource.ResourceGroupName -Slot $Slot
    }

    $hash = @{}
    if (-not $Replace.IsPresent) {
        ForEach ($kvp in $webApp.SiteConfig.AppSettings) {
            $hash[$kvp.Name] = $kvp.Value
        }
    }

    Foreach ($key in $AppSettings.Keys) {
        $hash[$key] = $AppSettings[$key]
    }

    if ($isSlot -eq $false) {
        Set-AzWebApp -Name $webAppResource.Name -AppSettings $hash -ResourceGroupName $webAppResource.ResourceGroupName | Out-Null
    } else {
        Set-AzWebAppSlot -Name $webAppResource.Name -Slot $Slot -AppSettings $hash -ResourceGroupName $webAppResource.ResourceGroupName | Out-Null
    }

    return $hash
}

function Get-FusionAzWebAppSettings {
    [OutputType([hashtable])]
    param(
        $Name,
        $Slot = $null
    )

    $webAppResource = Get-AzResource -ResourceType Microsoft.Web/sites | Where-Object -Property Name -eq $Name | Select-Object -First 1

    if ($null -eq $webAppResource) { throw "Could not locate app [$Name]" }

    $isSlot = -not [string]::IsNullOrEmpty($Slot) 
    if ($isSlot -eq $false) {
        $webApp = Get-AzWebApp -Name $webAppResource.Name -ResourceGroupName $webAppResource.ResourceGroupName
    } else {
        $webApp = Get-AzWebAppSlot -Name $webAppResource.Name -ResourceGroupName $webAppResource.ResourceGroupName -Slot $Slot
    }

    $hash = @{}
    ForEach ($kvp in $webApp.SiteConfig.AppSettings) {
        $hash[$kvp.Name] = $kvp.Value
    }

   return $hash
}