

function New-ARMTemplateConfigObject {
	<#
		.SYNOPSIS
			Helper to create the base json paramater file for ARM templates.
	#>
    param(
        $Items
    )

	$cfg = @{ 
		"```$schema" = "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#"
		"contentVersion" = "1.0.0.0" 
		"parameters" = @{ 
			
		}
	}

    if ($Items) {
        foreach ($key in $Items.Keys) {
            Add-ARMTemplateParamValue $cfg -Key $key -Value $Items[$key]
        }        
    }

    return $cfg
}

function Add-ARMTemplateParamValue {
	<#
		.SYNOPSIS
			Helper to build the paramaters used by the ARM templates. Mainly creating { "value": "..." } objects.
	#>
	param(
		$Config, 
		[String]$Key, 
		$Value
	)
	$Config.parameters[$Key] = @{value=$Value}
}

function Save-ARMTemplateConfig {
	<#
		.SYNOPSIS
			Helper to create a ARM template paramater json file.
	#>
	param(
		[Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
		$Config,
		[Parameter(Position=1, Mandatory=$true, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
		$Filename,
		$Items = $null
	)

	if ($null -ne $Items) {
		$Config = New-ARMTemplateConfigObject -Items $Items
	}

    Write-Host "Saving param file to: $filePath"
	ConvertTo-Json -InputObject $Config -Depth 20 | Out-File $filePath -Force -Encoding utf8
}

Function New-DefaultServiceARMTemplateConfig {
	<#
		.SYNOPSIS
			Creates a physical .json file with the paramater object used as input for the default web app template.
			Also outputs a VSTS param to save the build source.
		
		.PARAMETER Environment
			The shortname for the environment. CI / FQA etc. 
			Used to generate resource names.
    
		.PARAMETER WebAppName
			The name used for the web application, ex. pro-s-people-ci. 
			Should include the env shortname.
			The template deployment is only executed if the app does not already exist. This mainly to increase performance. 
			If desired to always run the template (ex update app settings if template change, or variables) use Force.			
	#>
	param(
		$Environment,
		$WebAppName,
		$Filename = "parameters.json"
	)

	$config = Get-DefaultServiceARMTemplateConfig -Environment $Environment -WebAppName $WebAppName

	Save-ARMTemplateConfig `
		-Filename "$PSScriptRoot\$Filename" `
		-Items $config
		
}

Function Get-DefaultServiceARMTemplateConfig {
	<#
		.SYNOPSIS
			Returns the paramater object used as input for the default web app template.
			Also outputs a VSTS param to save the build source.
		
		.PARAMETER Environment
			The shortname for the environment. CI / FQA etc. 
			Used to generate resource names.
    
		.PARAMETER WebAppName
			The name used for the web application, ex. pro-s-people-ci. 
			Should include the env shortname.
			The template deployment is only executed if the app does not already exist. This mainly to increase performance. 
			If desired to always run the template (ex update app settings if template change, or variables) use Force.			
	#>
	param(
		[string]$Environment,
		[string]$WebAppName
	)

	$envInfo = Get-EnvironmentParams -Environment $Environment

	# Create params file
	$CLIENT_ID = $envInfo.ClientId.Value
	$CERT_THUMBPRINT = $envInfo.CertThumbprint.Value
	$BUILD_SOURCE = Get-VSTSBuildSource
	$FUNCTION_APP_NAME = $WebAppName
	$APP_PROXY_RESOURCE = $envInfo.AppProxyResource.Value
	$AI_INSTRUMENT_KEY = $envInfo.AppInsights.Value
	$ENV_KEY_VAULT = "https://proview-$($Environment.ToLower())-keys.vault.azure.net"
	$PR_SLOT_NAME = Get-CurrentPullRequestNumber

	Write-Host "--- Environment params -----"
	Write-Host "`tEnvironment: $Environment"
	Write-Host "`tFound application insight key: $AI_INSTRUMENT_KEY"
	Write-Host "`tFound ClientID: $CLIENT_ID"
	Write-Host "`tFound Cert Thumbprint: $CERT_THUMBPRINT"
	Write-Host "`tUsing build source: $BUILD_SOURCE, saved to variable Fusion.BuildSource"
	Write-Host "`tUsing app proxy resource: $APP_PROXY_RESOURCE"
	Write-Host "##vso[task.setvariable variable=Fusion.BuildSource;]$BUILD_SOURCE"
	Write-Host "---"
	Write-Host ""
	
	return @{
		"hostingPlanName" = "ProView$($Environment.ToUpper())"
		"appName" = $FUNCTION_APP_NAME
		"env" = $Environment
		"app_insight_key" = $AI_INSTRUMENT_KEY
		"settings" = @{
			"cert_thumbprint" = $CERT_THUMBPRINT
			"client_id" = $CLIENT_ID
			"build_source" = $BUILD_SOURCE
			"pull_request_nr" = $PR_SLOT_NAME
			"app_proxy_resource" = $APP_PROXY_RESOURCE
            "key_vault" = $ENV_KEY_VAULT
		}
	}
}

function New-DefaultWebAppDeployment {
	<#
		.SYNOPSIS
			Will ensure that the web app exsists, using a standard ARM template that gives default Fusion options.
			
			- App settings
				- With app insight connection
			- Site extensions
				 - Asp.net core
				 - App insights
			- Always on
			- etc...

			Ref templates in SharedTemplates folder in module.

			Deployment outcome can be view in the portal -> Resource Group -> Deployments.
		
		.PARAMETER Environment
			The shortname for the environment. CI / FQA etc. 
			Used to generate resource names.
    
		.PARAMETER WebAppName
			The name used for the web application, ex. pro-s-people-ci. 
			Should include the env shortname.
			The template deployment is only executed if the app does not already exist. This mainly to increase performance. 
			If desired to always run the template (ex update app settings if template change, or variables) use Force.

		.PARAMETER SlotName
			Specify a slot that should also be created.
			If the main app does not exist, it is created first.

		.PARAMETER Force
			Will force the template to be deployed.
			
	#>
    param(
        [string]$Environment,
        [string]$WebAppName,
        [string]$SlotName = $null,
        [switch]$Force
    )

    $ResourceGroupName = "ProView_$Environment"

    Write-Host "Loading template parameters"
    $defaultParams = Get-DefaultServiceARMTemplateConfig -Environment $Environment -WebAppName $WebAppName

	Write-Host "Trying to get existing site [$WebAppName] in group [$ResourceGroupName]"
	$app = $null
    try { $app = Get-AzResource -ResourceType Microsoft.Web/sites -Name $WebAppName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue }
	catch { Write-Host "Could not find main web app [$WebAppName]" }

    if ($null -eq $app) { Write-Host "Existing web app could not be located" }
    else { Write-Host "Located web app $($app.Id)" }

    if ($null -eq $app -or $Force.IsPresent) {
        $templatefile = "$PSScriptRoot\SharedTemplates\main-webapp-template.json"

        Write-Host "Validating main template"

        $validationResult = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
									        -TemplateFile $templatefile `
                                            -TemplateParameterObject $defaultParams

        if ($validationResult.Count -gt 0) {
            Write-Host "Validation outcome"
            ConvertTo-Json -InputObject $validationResult -Depth 20

            throw "Template not valid"
        }

        $deploymentInfo = New-AzResourceGroupDeployment -Name (Get-DeploymentName -Name $WebAppName) `
										    -ResourceGroupName $ResourceGroupName `
										    -TemplateFile $templatefile `
                                            -TemplateParameterObject $defaultParams `
										    -Force -Verbose
		Write-Host $deploymentInfo

		if ($deploymentInfo.ProvisioningState -eq "Failed") {
			throw "Unsuccessfull deployment"
		}


    } else {
        Write-Host "Skipping main web app template deployment"
    } 

    
    if (-not [string]::IsNullOrEmpty($SlotName)) {
        $defaultParams.settings.pull_request_nr = $SlotName

        $slotApp = $null
		try { $slotApp = Get-AzResource -ResourceType Microsoft.Web/sites/slots -Name "$WebAppName/$SlotName" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue }
		catch { Write-Host "Could not find slot [$WebAppName/$SlotName]" }

        if ($null -ne $slotApp) {
            Write-Verbose "Located web app slot $($slotApp.Id)"
        }

        if ($null -eq $slotApp -or $Force.IsPresent) {
            $templatefile = "$PSScriptRoot\SharedTemplates\prx-webapp-template.json"

            Write-Host "Validating prx template"
            $validationResult = Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
									            -TemplateFile $templatefile `
                                                -TemplateParameterObject $defaultParams

            if ($validationResult.Count -gt 0) {
                Write-Host "Validation outcome"
                ConvertTo-Json -InputObject $validationResult -Depth 20

                throw "Template not valid"
            }

            Write-Host "Deploying to slot $SlotName"

            $deploymentStatus = New-AzResourceGroupDeployment -Name (Get-DeploymentName -Name "$WebAppName-prx-$SlotName") `
										    -ResourceGroupName $ResourceGroupName `
										    -TemplateFile $templatefile `
										    -TemplateParameterObject $defaultParams `
										    -Force -Verbose

			Write-Output $deploymentStatus
			
			if ($deploymentStatus.ProvisioningState -eq "Failed") {
				Write-Host "Retrying without extensions"

				$templatefile = "$PSScriptRoot\SharedTemplates\prx-webapp-template-no-extensions.json"
				$deploymentStatus = New-AzResourceGroupDeployment -Name (Get-DeploymentName -Name "$WebAppName-prx-$SlotName") `
								-ResourceGroupName $ResourceGroupName `
								-TemplateFile $templatefile `
								-TemplateParameterObject $defaultParams `
								-Force -Verbose

			}

			if ($deploymentStatus.ProvisioningState -eq "Failed") {
				throw "Unsuccessfull deployment"
			}

			try {
				Write-Host "Trying to install application insights site extension to slot"
				$PropertiesObject = @{
					#Property = value;
				}
				Set-AzResource -PropertyObject $PropertiesObject `
					-ResourceGroupName $ResourceGroupName `
					-ResourceType Microsoft.Web/sites/slots/siteextensions `
					-ResourceName "$WebAppName/$SlotName/Microsoft.ApplicationInsights.AzureWebSites" `
					-ApiVersion 2018-02-01 `
					-Force
			}
			catch {
				Write-Warning "Failed to install extension"
			}

			try {
				Write-Host "Trying to install asp.net core site extension to slot"
				$PropertiesObject = @{
					#Property = value;
				}
				Set-AzResource -PropertyObject $PropertiesObject `
					-ResourceGroupName $ResourceGroupName `
					-ResourceType Microsoft.Web/sites/slots/siteextensions `
					-ResourceName "$WebAppName/$SlotName/Microsoft.AspNetCore.AzureAppServices.SiteExtension" `
					-ApiVersion 2018-02-01 `
					-Force
			}
			catch {
				Write-Warning "Failed to install extension"
			}
        }
    }
}

function New-DefaultServiceSqlDatabase {
	<#
		.SYNOPSIS
			Will ensure that a database exists in the default environment sql server. 
			If the database already exists, a copy will not be made.
			To "Force" a new copy, the existing database should be deleted and release redeployed.
		
		.PARAMETER SlotName
			If the SlotName paramater is used, a postfix is created on the database name.
    
		.PARAMETER NoCopy
			If the NoCopy switch is used, the source database is not copied to the new database.
	#>
	param(
		[string]$Environment,
		[string]$DatabaseName,
		[string]$SlotName,
		[string]$SourceEnvironment,
		[string]$SourceDatabaseName,
		[switch]$NoCopy
	)

	$SOURCE_RESOURCE_GROUP = "ProView_$SourceEnvironment"
	$SOURCE_SQL_SERVER = "proview-sql-$($SourceEnvironment.ToLower())"
	$SOURCE_DATABASE = $SourceDatabaseName
	$DESTINATION_RESOURCE_GROUP = "ProView_$Environment"
	$DESTINATION_SQL_SERVER = "proview-sql-$($Environment.ToLower())"
	
	$IsSlot = -not [string]::IsNullOrEmpty($SlotName)

	if ($IsSlot) { $DatabaseName += "-$SlotName" }
	
	$db = Get-AzSqlDatabase -ResourceGroupName $DESTINATION_RESOURCE_GROUP -DatabaseName $DatabaseName -ServerName $DESTINATION_SQL_SERVER -ErrorAction SilentlyContinue

	if ($null -ne $db) {
		Write-Host "Found existing database [$($db.DatabaseName)] on server [$($db.ServerName)]"
		Write-Host "Not executing create/copy..."
	}

	if ($null -eq $db) {
		Write-Host "Creating new database copy"
		
		Write-Host "Looking for source database [$SourceDatabaseName] on server [$SOURCE_SQL_SERVER]"
		$srcDb = Get-AzSqlDatabase -ResourceGroupName $SOURCE_RESOURCE_GROUP -DatabaseName $SOURCE_DATABASE -ServerName $SOURCE_SQL_SERVER -ErrorAction SilentlyContinue

		if ($null -eq $srcDb -or $NoCopy.IsPresent) {
			# Create new database if source does not exist, or the NoCopy flag is used
			Write-Host "   Destination: $DESTINATION_RESOURCE_GROUP, Server: $DESTINATION_SQL_SERVER, Database: $DatabaseName"
			
			New-AzSqlDatabase -ResourceGroupName $DESTINATION_RESOURCE_GROUP -ServerName $DESTINATION_SQL_SERVER -DatabaseName $DatabaseName -Edition Standard
		} else {
			Write-Host "   Source: $SOURCE_RESOURCE_GROUP, Server: $SOURCE_SQL_SERVER, Database: $SOURCE_DATABASE"
			Write-Host "   Destination: $DESTINATION_RESOURCE_GROUP, Server: $DESTINATION_SQL_SERVER, Database: $DatabaseName"

			New-AzSqlDatabaseCopy `
				-ResourceGroupName $SOURCE_RESOURCE_GROUP `
				-ServerName $SOURCE_SQL_SERVER `
				-DatabaseName $SOURCE_DATABASE `
				-CopyResourceGroupName $DESTINATION_RESOURCE_GROUP `
				-CopyServerName $DESTINATION_SQL_SERVER `
				-CopyDatabaseName $DatabaseName
		}
	}
}


function Get-DeploymentName {
    param([string]$Name)
    return "$Name"
}

Export-ModuleMember -Function *-ARMTemplate*,New-DefaultServiceARMTemplateConfig,New-DefaultWebAppDeployment,Get-DefaultServiceARMTemplateConfig,New-DefaultServiceSqlDatabase