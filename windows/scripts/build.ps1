param([switch]$Publish, [string]$PublishName = 'AUV_Win_0.16.3', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$dotnet = Join-Path $windowsRoot '.tools\dotnet\dotnet.exe'
if (!(Test-Path -LiteralPath $dotnet)) { throw 'Run scripts\bootstrap-sdk.ps1 or install the .NET 10 SDK first.' }
$env:DOTNET_ROOT = Split-Path -Parent $dotnet
$env:DOTNET_CLI_HOME = Join-Path $windowsRoot '.tools\cli-home'
$env:NUGET_PACKAGES = Join-Path $windowsRoot '.tools\nuget'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -File (Join-Path $PSScriptRoot 'generate-native-icon.ps1')
if ($LASTEXITCODE) { throw 'Native icon asset generation failed.' }
& $dotnet --info
& $dotnet restore (Join-Path $windowsRoot 'AUV.Windows.sln') --configfile (Join-Path $windowsRoot 'NuGet.Config') -m:1
if ($LASTEXITCODE) { throw 'Restore failed.' }
& $dotnet build (Join-Path $windowsRoot 'AUV.Windows.sln') -c Release --no-restore -m:1
if ($LASTEXITCODE) { throw 'Build failed.' }
if (!$SkipTests) {
    & $dotnet test (Join-Path $windowsRoot 'AUV.Windows.sln') -c Release --no-build --no-restore -m:1 --logger 'trx;LogFileName=core-tests.trx' --results-directory (Join-Path $windowsRoot 'artifacts\evidence\tests')
    if ($LASTEXITCODE) { throw 'Tests failed.' }
} else { Write-Output 'TESTS_NOT_RUN: explicitly skipped for this build.' }
if ($Publish) {
    $configPath = Join-Path $windowsRoot 'NuGet.Config'
    & $dotnet publish (Join-Path $windowsRoot 'src\AUV.Windows.App\AUV.Windows.App.csproj') -c Release -r win-x64 --self-contained true "-p:RestoreConfigFile=$configPath" -m:1 -o (Join-Path $windowsRoot "artifacts\$PublishName")
    if ($LASTEXITCODE) { throw 'Publish failed.' }
}
