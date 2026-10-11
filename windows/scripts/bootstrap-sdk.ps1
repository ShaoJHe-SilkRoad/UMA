$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$toolsRoot = Join-Path $windowsRoot '.tools'
New-Item -ItemType Directory -Force -Path $toolsRoot | Out-Null
$installer = Join-Path $toolsRoot 'dotnet-install.ps1'
Invoke-WebRequest 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer
& $installer -Version '10.0.401' -Architecture x64 -InstallDir (Join-Path $toolsRoot 'dotnet') -NoPath
if ($LASTEXITCODE) { throw 'SDK installation failed.' }
