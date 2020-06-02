# Fusion Powershell

The repository for common powershell modules/scripts used by the fusion framework.

Modules published to fusion-public package feed.

```
https://statoil-proview.pkgs.visualstudio.com/5309109e-a734-4064-a84c-fbce45336913/_packaging/Fusion-Public/nuget/v2
```

## FusionPS module

> To install the FusionPS module:
> ```powershell
> Register-PSRepository -Name Fusion -SourceLocation "https://statoil-proview.pkgs.visualstudio.com/ 5309109e-a734-4064-a84c-fbce45336913/_packaging/Fusion-Public/nuget/v2" -InstallationPolicy Trusted
> Install-Module FusionPS -Scope CurrentUser
> ```

A module used in the DevOps pipelines, wrapping commonly used functionalities and standardize tasks.

- Deploy pre-configured web apps / slotts
- Duplicate databases for temp environments
- Generalized environment configuration on blob storage
- Integration testing utils
- Key vault utils

