[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot "..\deps\prism"),
    [string]$ArchivePath
)

$ErrorActionPreference = "Stop"
$version = "0.17.3"
$expectedSha256 = "9a44e81f2caa8f1bf804c182f39a7a415f8b82d6032f4fe686e145a3d09dbb2f"
$assetName = "prism-windows-x64.zip"
$uri = "https://github.com/ethindp/prism/releases/download/v$version/$assetName"
$destinationPath = [IO.Path]::GetFullPath($Destination)
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("lamentmapper-prism-" + [guid]::NewGuid())
$downloadedArchive = Join-Path $temporaryRoot $assetName
$expanded = Join-Path $temporaryRoot "expanded"

try {
    New-Item -ItemType Directory -Force -Path $temporaryRoot, $expanded | Out-Null

    if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        Write-Host "Downloading Prism $version Windows x64 runtime..."
        Invoke-WebRequest -Uri $uri -OutFile $downloadedArchive
        $archive = $downloadedArchive
    }
    else {
        $archive = [IO.Path]::GetFullPath($ArchivePath)
        if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
            throw "The supplied Prism archive does not exist: $archive"
        }
    }

    $actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "Prism Windows x64 checksum mismatch. Expected $expectedSha256; got $actualSha256."
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $expanded

    $dll = Join-Path $expanded "dynamic\release\bin\prism.dll"
    $notice = Join-Path $expanded "NOTICE"
    $license = Join-Path $expanded "LICENSES\prism\mpl-2.0.txt"
    foreach ($requiredFile in @($dll, $notice, $license)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "The Prism Windows x64 archive did not contain the expected file: $requiredFile"
        }
    }

    New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
    Copy-Item -LiteralPath $dll -Destination (Join-Path $destinationPath "prism.dll") -Force
    Copy-Item -LiteralPath $license -Destination (Join-Path $destinationPath "PRISM-LICENSE.txt") -Force
    Copy-Item -LiteralPath $notice -Destination (Join-Path $destinationPath "PRISM-NOTICE.txt") -Force

    Write-Host "Staged Prism $version Windows x64 release runtime in $destinationPath"
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}