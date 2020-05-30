

function Get-VSTSBuildSource {	
	$buildsource = "$($env:BUILD_BUILDNUMBER)"

	if (![string]::IsNullOrEmpty($PR_SLOT_NAME)) {
		$buildsource += "-PR-$PR_SLOT_NAME"
	}

	return $buildsource
}

function Get-VSTSIsPullRequest {
	if ($env:BUILD_SOURCEBRANCH -match "/pull/(\d+)/merge") {
		return $true
	}
	return $false
}

function Get-VSTSPullRequestNumber {
	$sourceBranch = $env:BUILD_SOURCEBRANCH

	if ($sourceBranch -match "/pull/(\d+)/merge") {
		return $matches[1]
	}

	return $null
}

Export-ModuleMember -Function *-VSTS*