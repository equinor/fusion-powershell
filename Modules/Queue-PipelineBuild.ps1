param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("FusionPS")]
    $Module,
    [Switch] $Open,
    [Switch]$Force
)


$branch = git branch --show-current

Write-Host -ForegroundColor Yellow "Queueing build on: $branch"

if ((-not $Force.IsPresent) -and $branch -ne "master") {
    throw "Cannot build on branch other than master. To override, use -Force switch"
}

switch ($Module) {
    "FusionPS" { $definitionId = 226 }
    default { Write-Host -ForegroundColor Red "Not supported"; return }
}

$ErrorActionPreference = "Stop"

if ($Open) {
    [string]$buildJson = az pipelines build queue --branch $branch --definition-id $definitionId --open --project 'Fusion - Packages'
} else {
    [string]$buildJson = az pipelines build queue --branch $branch --definition-id $definitionId --project 'Fusion - Packages'
}

$build = ConvertFrom-Json $buildJson

Write-Host -ForegroundColor Green "Build '$($build.buildNumber)' queued"
Write-Host -ForegroundColor Cyan $build.url

## Seems like when you capture the output of az cli, the color on the terminal is stuck...
[Console]::ResetColor()