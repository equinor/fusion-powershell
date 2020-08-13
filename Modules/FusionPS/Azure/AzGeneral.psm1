
function Get-FusionAzAccessToken
{
    <#
    .SYNOPSIS
    Get access token to specific resource
    
    .PARAMETER Resource
    Ex. "https://database.windows.net/"
    #>
    param(
        [string]$Resource
    )

    ## Use access token to access database - the service principal should be located in the sql server admin group.
    $context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
    $tenantId = $context.Tenant.Id.ToString()
    $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $tenantId, $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, $Resource)

    return $token.AccessToken
}

Export-ModuleMember -Function *