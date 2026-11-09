param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [ValidatePattern('^\d{1,32}$')][string]$Build = (Get-Date -Format 'yyyyMMddHHmm'),
    [string]$RuntimeGenerationId = ([guid]::NewGuid().ToString())
)
# Stages BrowserCompanion\ beside a published AUV.exe: the Chrome/Edge extension with this build's identity filled in,
# the self-contained native host and companion.json. Runs on Windows PowerShell 5.1. Nothing secret is written.
$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$dotnet = Join-Path $windowsRoot '.tools\dotnet\dotnet.exe'
if (!(Test-Path -LiteralPath $dotnet)) { throw 'Run scripts\bootstrap-sdk.ps1 or install the .NET 10 SDK first.' }
$RuntimeGenerationId = $RuntimeGenerationId.ToLowerInvariant()
if ($RuntimeGenerationId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { throw 'The runtime generation must be a UUID.' }
$target = Join-Path ([IO.Path]::GetFullPath($Destination)) 'BrowserCompanion'
if (Test-Path -LiteralPath $target) { throw "BrowserCompanion already exists in $Destination. Stage into a fresh publish folder." }
$source = Join-Path $windowsRoot 'browser-extension'
$manifest = Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw | ConvertFrom-Json
$version = $manifest.version
# Chrome's extension ID: SHA-256 of the manifest's public key, first 16 bytes, each hex digit mapped to a-p.
$sha = [Security.Cryptography.SHA256]::Create()
try { $hash = $sha.ComputeHash([Convert]::FromBase64String($manifest.key)) } finally { $sha.Dispose() }
$extensionId = -join (([BitConverter]::ToString($hash, 0, 16)).Replace('-', '').ToLowerInvariant().ToCharArray() | ForEach-Object { [char](97 + [Convert]::ToInt32([string]$_, 16)) })

$env:DOTNET_ROOT = Split-Path -Parent $dotnet
$env:DOTNET_CLI_HOME = Join-Path $windowsRoot '.tools\cli-home'
$env:NUGET_PACKAGES = Join-Path $windowsRoot '.tools\nuget'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$hostOut = Join-Path ([IO.Path]::GetTempPath()) ('auv-browserhost-' + [guid]::NewGuid().ToString('N'))
& $dotnet publish (Join-Path $windowsRoot 'src\AUV.Windows.BrowserHost\AUV.Windows.BrowserHost.csproj') -c Release "-p:RestoreConfigFile=$(Join-Path $windowsRoot 'NuGet.Config')" -m:1 -o $hostOut
if ($LASTEXITCODE) { throw 'Native host publish failed.' }

New-Item -ItemType Directory -Path (Join-Path $target 'host') | Out-Null
Copy-Item -LiteralPath (Join-Path $hostOut 'AUV.BrowserHost.exe') -Destination (Join-Path $target 'host\AUV.BrowserHost.exe')
Remove-Item -LiteralPath $hostOut -Recurse -Force
Copy-Item -LiteralPath $source -Destination (Join-Path $target 'extension') -Recurse
$loaderPath = Join-Path $target 'extension\background-loader.js'
$loader = [IO.File]::ReadAllText($loaderPath)
if (!$loader.Contains('__AUV_COMPANION_BUILD__') -or !$loader.Contains('__AUV_RUNTIME_GENERATION_ID__')) { throw 'The loader template is missing its placeholders.' }
$loader = $loader.Replace('__AUV_COMPANION_BUILD__', $Build).Replace('__AUV_RUNTIME_GENERATION_ID__', $RuntimeGenerationId)
[IO.File]::WriteAllText($loaderPath, $loader, (New-Object Text.UTF8Encoding $false))
$companion = [ordered]@{ schemaVersion = 1; extensionId = $extensionId; runtimeGenerationID = $RuntimeGenerationId; companionVersion = $version; companionBuild = $Build }
[IO.File]::WriteAllText((Join-Path $target 'companion.json'), ($companion | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
[ordered]@{ BrowserCompanion = $target; ExtensionId = $extensionId; CompanionVersion = $version; CompanionBuild = $Build; RuntimeGenerationID = $RuntimeGenerationId;
    HostBytes = (Get-Item -LiteralPath (Join-Path $target 'host\AUV.BrowserHost.exe')).Length } | ConvertTo-Json
