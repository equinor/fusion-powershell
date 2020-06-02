<#
    .SYNOPSIS
        Register the publis fusion nuget feed as a powershell repository - Fusion
#>

if ($null -eq (Get-PSRepository -Name Fusion)) {
    Write-Host "Registering fusion repository" -ForegroundColor Yellow
    Register-PSRepository -Name Fusion -SourceLocation "https://statoil-proview.pkgs.visualstudio.com/5309109e-a734-4064-a84c-fbce45336913/_packaging/Fusion-Public/nuget/v2" -InstallationPolicy Trusted -ErrorAction Stop
    Write-Host "Ok" -ForegroundColor Green
} else {
    Write-Host "Fusion already added as a repository..." -ForegroundColor Gray
}
