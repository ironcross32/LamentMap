<#
.SYNOPSIS
Creates and pushes the next annotated release tag.

.DESCRIPTION
Reads local and origin tags matching vMAJOR.MINOR.PATCH, suggests the next patch
version, and prompts for the version to release. The entered version must be a
stable three-part version greater than every existing release tag.

.PARAMETER RequestedVersion
Uses this version instead of prompting. An empty or whitespace value accepts the
suggested version.

.EXAMPLE
git config alias.release "!powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/tag-release.ps1"
git release
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$RequestedVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Git {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
        throw "git $($Arguments -join ' ') failed:$([Environment]::NewLine)$details"
    }

    return $output | ForEach-Object { $_.ToString() }
}

function ConvertTo-ReleaseVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    if ($Text -notmatch '^(?<major>0|[1-9][0-9]*)\.(?<minor>0|[1-9][0-9]*)\.(?<patch>0|[1-9][0-9]*)$') {
        return $null
    }

    return [PSCustomObject]@{
        Text = $Text
        Major = [Numerics.BigInteger]::Parse($Matches.major)
        Minor = [Numerics.BigInteger]::Parse($Matches.minor)
        Patch = [Numerics.BigInteger]::Parse($Matches.patch)
    }
}

function Compare-ReleaseVersion {
    param(
        [Parameter(Mandatory)]$Left,
        [Parameter(Mandatory)]$Right
    )

    foreach ($part in @("Major", "Minor", "Patch")) {
        if ($Left.$part -lt $Right.$part) {
            return -1
        }
        if ($Left.$part -gt $Right.$part) {
            return 1
        }
    }

    return 0
}

$insideWorkTree = (Invoke-Git -Arguments @("rev-parse", "--is-inside-work-tree")) -join ""
if ($insideWorkTree -ne "true") {
    throw "Run this command from a Git working tree."
}

Invoke-Git -Arguments @("rev-parse", "--verify", "HEAD") | Out-Null
Invoke-Git -Arguments @("remote", "get-url", "origin") | Out-Null

$tagNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($tag in @(Invoke-Git -Arguments @("tag", "--list"))) {
    [void]$tagNames.Add($tag)
}

foreach ($line in @(Invoke-Git -Arguments @("ls-remote", "--tags", "--refs", "origin"))) {
    if ($line -match '\srefs/tags/(?<tag>.+)$') {
        [void]$tagNames.Add($Matches.tag)
    }
}

$releaseVersions = @()
foreach ($tag in $tagNames) {
    if ($tag -match '^v(?<version>.+)$') {
        $version = ConvertTo-ReleaseVersion -Text $Matches.version
        if ($null -ne $version) {
            $releaseVersions += $version
        }
    }
}

$highest = $null
foreach ($version in $releaseVersions) {
    if ($null -eq $highest -or (Compare-ReleaseVersion -Left $version -Right $highest) -gt 0) {
        $highest = $version
    }
}

if ($null -eq $highest) {
    $suggestedVersion = "0.1.0"
    Write-Host "No existing release tags were found."
} else {
    $suggestedVersion = "$($highest.Major).$($highest.Minor).$($highest.Patch + 1)"
    Write-Host "Highest existing release tag: v$($highest.Text)"
}

$enteredVersion = if ($PSBoundParameters.ContainsKey('RequestedVersion')) {
    $RequestedVersion
} else {
    Read-Host "Version [$suggestedVersion]"
}
if ([string]::IsNullOrWhiteSpace($enteredVersion)) {
    $enteredVersion = $suggestedVersion
} else {
    $enteredVersion = $enteredVersion.Trim()
}

$candidate = ConvertTo-ReleaseVersion -Text $enteredVersion
if ($null -eq $candidate) {
    throw "Version must contain exactly three non-negative numbers without leading zeroes, for example 1.2.3."
}

$tagName = "v$($candidate.Text)"
if ($tagNames.Contains($tagName)) {
    throw "Release tag $tagName already exists."
}
if ($null -ne $highest -and (Compare-ReleaseVersion -Left $candidate -Right $highest) -le 0) {
    throw "Version $($candidate.Text) must be greater than the highest existing version, $($highest.Text)."
}

Write-Host "Creating annotated tag $tagName at HEAD..."
Invoke-Git -Arguments @("tag", "-a", $tagName, "-m", $candidate.Text) | Out-Null

try {
    Invoke-Git -Arguments @("push", "origin", $tagName) | ForEach-Object { Write-Host $_ }
} catch {
    Write-Warning "Tag $tagName was created locally, but it was not pushed."
    throw
}

Write-Host "Created and pushed $tagName to origin."
