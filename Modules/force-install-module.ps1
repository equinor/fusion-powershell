<#
    .SYNOPSIS
        The script will publish a the module as a .nupkg file in the specified folder
#>

param(
    $Name,
    $PublishPath = ".\Publish"
)

if (-not (Test-Path $PublishPath)) {
    mkdir $PublishPath
}

$publishFolder = (Get-Item $PublishPath).FullName

Write-Host "Registering repo `@ $publishFolder"
Register-PSRepository -Name BuildTaskModuleRepo -SourceLocation $publishFolder -PublishLocation $publishFolder -InstallationPolicy Trusted -ErrorAction Stop

Write-Host "Publishing Fusion Service Deployment"
Publish-Module -Repository BuildTaskModuleRepo -Path (Join-Path $PSScriptRoot $Name)

Write-Host "Installing module"
Install-Module -Repository BuildTaskModuleRepo FusionPS -Scope CurrentUser -Force

Write-Host "Removing temp repo"
Unregister-PSRepository -Name BuildTaskModuleRepo

Write-Output (Get-ChildItem $publishFolder)
