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
$readme = @"
AUV Browser Companion for Claude $version (build $Build) - Chrome / Edge

Do not load this folder directly. In AUV, open Claude settings, tick "Sync Claude through the browser
companion" and choose Set Up: AUV copies the companion to
%LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion\ and registers its helper for Chrome and Edge
under your Windows account. Then load ...\browser-companion\extension on the browser's extensions page
(Developer mode -> Load unpacked). Extension ID: $extensionId

It reads only Claude's 5-hour and weekly used percentages, their reset times and when they were read,
from https://claude.ai/new#settings/usage (English or Chinese interface). Passwords, cookies, tokens,
conversations and page text are never read or sent. Remove it from Claude settings (Remove companion),
then remove the extension on the browser's extensions page. To remove the registration by hand:
  reg delete "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f
  reg delete "HKCU\Software\Microsoft\Edge\NativeMessagingHosts\com.silkrd.auv.claude_browser" /f

AUV 浏览器伴侣（Claude）：请勿直接加载本文件夹。在 AUV 的 Claude 设置中勾选“通过浏览器伴侣同步 Claude”并选择“设置”，
再在浏览器扩展页（开发者模式 -> 加载已解压的扩展程序）加载 ...\browser-companion\extension。
它只读取 claude.ai 用量页上的 5 小时与每周已用百分比、重置时间和读取时间（支持英文或中文界面），
从不读取或发送密码、Cookie、令牌、对话或页面文字。在 Claude 设置中选择“移除伴侣”，再在浏览器扩展页移除扩展即可卸载。
"@
[IO.File]::WriteAllText((Join-Path $target 'README.txt'), ($readme -replace "`r?`n", "`r`n"), (New-Object Text.UTF8Encoding $true))
[ordered]@{ BrowserCompanion = $target; ExtensionId = $extensionId; CompanionVersion = $version; CompanionBuild = $Build; RuntimeGenerationID = $RuntimeGenerationId;
    HostBytes = (Get-Item -LiteralPath (Join-Path $target 'host\AUV.BrowserHost.exe')).Length } | ConvertTo-Json
