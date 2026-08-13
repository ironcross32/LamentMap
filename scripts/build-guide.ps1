[CmdletBinding()]
param(
    [string]$InputPath = (Join-Path $PSScriptRoot "..\README.md"),
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\dist\README.html")
)

$ErrorActionPreference = "Stop"
$source = [IO.Path]::GetFullPath($InputPath)
$output = [IO.Path]::GetFullPath($OutputPath)
$body = (ConvertFrom-Markdown -Path $source).Html
$document = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LamentMapper Guide</title>
<style>
body { font: 1rem/1.55 system-ui, sans-serif; max-width: 52rem; margin: 2rem auto; padding: 0 1rem; color: #161616; }
code { background: #f2f2f2; padding: .1rem .25rem; }
table { border-collapse: collapse; } th, td { border: 1px solid #777; padding: .35rem .6rem; text-align: left; }
:focus { outline: 3px solid #075fbd; outline-offset: 2px; }
</style>
</head>
<body>
$body
</body>
</html>
"@
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($output)) | Out-Null
[IO.File]::WriteAllText($output, $document, [Text.UTF8Encoding]::new($false))
Write-Host "Generated $output"
