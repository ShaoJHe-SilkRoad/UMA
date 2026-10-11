param([string]$PublishName = 'AUV-0.16.0-win-x64-product-preview', [string]$Build = '20261010.3', [switch]$ProviderIntegration, [switch]$UiRefinement, [switch]$VisibilityRefinement, [switch]$ValidatedRefinement, [string]$ValidationPath, [switch]$Stable, [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.16.0')
$ErrorActionPreference = 'Stop'
if (@($ProviderIntegration, $UiRefinement, $VisibilityRefinement, $ValidatedRefinement, $Stable).Where({ $_ }).Count -gt 1) { throw 'Choose one candidate stage.' }
$windowsRoot = Split-Path -Parent $PSScriptRoot
$artifactRoot = Join-Path $windowsRoot 'artifacts'
$publishRoot = Join-Path $artifactRoot $PublishName
if (!(Test-Path -LiteralPath (Join-Path $publishRoot 'AUV.exe'))) { throw 'Publish the candidate first.' }
if ($Stable -and ([Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $publishRoot 'AUV.exe')).ProductVersion -ne $Version)) { throw 'Stable version does not match the published executable.' }
if ($ValidatedRefinement -or $Stable) {
    if (!$ValidationPath) { throw 'Validated packaging requires a validation receipt.' }
    $validation = Get-Content -LiteralPath $ValidationPath -Raw | ConvertFrom-Json
    foreach ($binary in $validation.Binaries) {
        if ((Get-FileHash -LiteralPath (Join-Path $publishRoot $binary.Name) -Algorithm SHA256).Hash -ne $binary.SHA256) { throw 'Tested binary differs from the published candidate.' }
    }
    if ($validation.AutomatedTests.Failed -ne 0 -or $validation.AutomatedTests.Passed -ne $validation.AutomatedTests.Total) { throw 'Automated tests did not pass.' }
    foreach ($evidence in $validation.RequiredEvidence) {
        if (!(Test-Path -LiteralPath $evidence.Path) -or (Get-FileHash -LiteralPath $evidence.Path -Algorithm SHA256).Hash -ne $evidence.SHA256) { throw 'Required verification evidence is missing or changed.' }
    }
}
$sourcePaths = & rg --files (Join-Path $windowsRoot 'src') (Join-Path $windowsRoot 'tests') $PSScriptRoot -g '!**/bin/**' -g '!**/obj/**'
$sourcePaths += @('AUV.Windows.sln','NuGet.Config','global.json') | ForEach-Object { Join-Path $windowsRoot $_ } | Where-Object { Test-Path -LiteralPath $_ }
$sourceFiles = @($sourcePaths | Sort-Object -Unique | ForEach-Object {
    $sourceFile = [IO.Path]::GetFullPath($_)
    [ordered]@{ Path = [IO.Path]::GetRelativePath($windowsRoot, $sourceFile).Replace('\','/'); SHA256 = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash }
})
$canonical = $sourceFiles | ConvertTo-Json -Depth 5 -Compress
$sourceHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)))
$manifest = [ordered]@{ Algorithm = 'SHA256 of UTF-8 compact ordered source-file manifest'; SourceIdentity = $sourceHash; Files = $sourceFiles }
$manifest | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $publishRoot 'SOURCE-MANIFEST.json') -Encoding utf8
$buildInfo = [ordered]@{ Product = $(if ($Stable) { 'AUV Windows' } else { 'AUV Windows Preview' }); Version = $Version; Build = $Build; Task = $(if ($Stable) { 'Stable promotion of validated refinement' } elseif ($ValidatedRefinement) { 'Tested visibility refinement and native UI fixes' } elseif ($VisibilityRefinement) { 'Available-quota visibility and visual refinement' } elseif ($UiRefinement) { 'Prepared connections and compact UI refinement' } elseif ($ProviderIntegration) { 'Provider integration 1 — Codex and WorkBuddy' } else { 'AUV-WIN-016-PRODUCT-SURFACES-02' }); Target = 'win-x64'; SelfContained = $true; SDK = '10.0.401'; Runtime = '10.0.12'; MacReference = '766b808f2af537af4d6edfe8606221cb78c88b79'; WindowsSourceIdentity = $sourceHash; PackagedAtUtc = [DateTime]::UtcNow.ToString('o') }
if ($UiRefinement -or $VisibilityRefinement) { $buildInfo.Validation = [ordered]@{ Compilation = 'Passed'; AutomatedTests = 'Not run by user request'; NativeUI = 'Not run by user request'; LiveProviders = 'Not run by user request' } }
if ($ValidatedRefinement -or $Stable) { $buildInfo.Validation = $validation.Summary; $buildInfo.TestedBinaries = $validation.Binaries }
if ($Stable) { $buildInfo.Channel = 'stable'; $buildInfo.PromotedFrom = '0.16.0-validated-refinement.20261010.7'; $buildInfo.Designation = 'Latest local Windows stable version, approved by the user' }
$buildInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $publishRoot 'BUILD-INFO.json') -Encoding utf8
@'
AUV 0.16.0 Windows UI Preview — build 20261010.3 — Windows 11 x64

Extract the complete folder and launch AUV.exe. Keep the supporting files together.
Normal mode has unavailable provider allowances; it never silently loads fixture data.
Optional: AUV.exe --show-widget
Explicit development fixture: AUV.exe --demo --show-widget
Demo preferences are separate from normal preferences.

Desktop Wizard is a separate nonactivating floating allowance stack above other apps.
Click a card to open its provider. Drag to move. Right click for pin/density/hide options.
Tray usage popup contains shared allowance cards and read-only CPU/RAM counters.
Global Settings contains Wizard settings; provider settings contain only that provider.

Keyboard equivalents in the main window:
Ctrl+Shift+W: show/hide Wizard
Ctrl+Shift+U: open/close Quick Panel
Ctrl+Comma: global settings
Ctrl+Shift+Q: Quit (closes main, Wizard and tray)
Alt+A / Alt+T / Alt+S: module navigation
Closing the main window retains the tray only when it is available and that preference is enabled.

This is a local UI preview. Provider connections and Windows storage mutation are unavailable.
No installer, login startup, service, public release or code signing is included.
SOURCE-MANIFEST.json and BUILD-INFO.json identify this candidate's exact local source.
'@ | Set-Content -LiteralPath (Join-Path $publishRoot 'README.txt') -Encoding utf8
if ($ProviderIntegration) {
@"
AUV 0.16.0 Windows Provider Preview — build $Build — Windows 11 x64

Extract the complete folder and run AUV.exe. Keep all supporting files together.
Normal mode reads real Codex data using your installed codex.exe and its existing ChatGPT login.
Codex refreshes on launch and once per minute; F5 or Refresh usage refreshes the selected provider.
Provider settings can choose codex.exe, refresh, and disable reading without signing out of Codex.
AUV never starts inference tasks. Account token buckets are distinct from local session data and costs.
Missing metrics remain unavailable; seven-day totals require all seven current daily buckets.

WorkBuddy: select WorkBuddy > Agent settings > Connect with official website.
Sign in yourself in AUV's separate WebView2 browser session. The official Plan and Usage page
attempts a Credit sync after loading; use Sync Credits to retry after figures and all pools are visible.
Page sync is experimental. Incomplete, changed or inconsistent pools withdraw the balance.
Credits remain native units. No cookies are imported from installed clients or other browsers.
Disconnect clears only AUV's owned WorkBuddy browser session. Microsoft Edge WebView2 Runtime
is required for this optional connection. The SDK/loader are bundled; no runtime installer is run.

Codex and WorkBuddy use locally bundled official-source vector marks in main, Wizard and Quick Panel.
Wizard is an independent floating window: drag to move, click a card to open its provider,
right click for pin/density/hide. Quick Panel also contains read-only CPU/RAM utilization counters.
Ctrl+Shift+W: Wizard; Ctrl+Shift+U: Quick Panel; Ctrl+Comma: settings; Ctrl+Shift+Q: Quit.
Alt+A / Alt+T / Alt+S: module navigation. Explicit --demo uses separate fixture preferences,
has no live connections, and never silently replaces normal account data.

Claude/Antigravity connection and Windows storage mutation are still unavailable.
This is a local feature preview, not a full release. No installer, startup service or code signing.
SOURCE-MANIFEST.json and BUILD-INFO.json identify this candidate. No login sessions or
account snapshots are packaged. ZIP SHA-256 is supplied alongside the ZIP.
"@ | Set-Content -LiteralPath (Join-Path $publishRoot 'README.txt') -Encoding utf8
}
if ($UiRefinement) {
@"
AUV 0.16.0 Windows UI Refinement Preview — build $Build — Windows 11 x64

This candidate was compiled and packaged only. Automated tests, native UI checks and live
provider checks were deliberately NOT RUN at the user's request. Do not treat prior-build
test reports as acceptance of this candidate. No updated application was launched during delivery.

Extract the complete folder and run AUV.exe when ready to inspect it. Keep all supporting files.
Desktop Wizard is separate from the tray usage panel. Both Regular and Minimalist Wizard
widths are 50% of the previous layout and heights/gaps are 80%, at the same text scale and data.
Regular rows are 105 x 48 DIPs before accessibility text scaling or native-Credit width sizing.
Wizard values use 10.5 DIP in Minimalist and 12 DIP in Regular, fitting down to 8.5 when needed.
Full values remain in tooltips and accessibility text. No rounded Credit abbreviations are used.
The main footer is one thin status/icon strip; More actions contains Hide to tray and Quit.

The native AUV icon is a transparent simplified gauge. Window title ink follows the app theme;
running taskbar/tray ink follows the Windows system theme. High contrast uses system colors.
The static EXE/Explorer icon is transparent blue; Windows file icons are fixed resources.
Codex and WorkBuddy retain their locally bundled official-source vector marks.

Claude and Antigravity have prepared connector interfaces and pure packet decoders only.
Their live reading remains disabled. No new login, CLI process, network request or local history
reader is enabled by this groundwork. Local usage and account quota remain separate sources.
The Windows storage interface reports unavailable inventory and mutation; no disk operation exists.

Existing Codex/WorkBuddy connections are retained. Normal launch can read Codex through your
installed codex.exe and its existing login, unless disabled in provider settings.
WorkBuddy uses its separate official-site WebView2 session and experimental Credit sync.
Microsoft Edge WebView2 Runtime is required for the optional WorkBuddy connection.
For later offline visual inspection use AUV.exe --offline --show-widget;
explicit fixtures require --demo --offline --show-widget and use separate preferences.

Ctrl+Shift+W: Wizard; Ctrl+Shift+U: Quick Panel; Ctrl+Comma: settings; Ctrl+Shift+Q: Quit.
F5: refresh selected provider. Alt+A / Alt+T / Alt+S: module navigation.
Wizard supports drag, click-to-provider and right-click pin/density/hide.

Local preview only. No installer, startup service, code signing or public release.
No account snapshots or browser sessions are packaged. SOURCE-MANIFEST.json and BUILD-INFO.json
identify this candidate; ZIP SHA-256 is supplied alongside the ZIP.
"@ | Set-Content -LiteralPath (Join-Path $publishRoot 'README.txt') -Encoding utf8
}
if ($VisibilityRefinement) {
@"
AUV 0.16.0 Windows Visibility Refinement Preview — build $Build — Windows 11 x64

Compiled and packaged only. Automated tests, native UI inspection, application launch and live
provider checks were NOT RUN, following the user's continuing request to postpone testing.
Previous candidate test reports do not validate this build.

Extract the complete folder and run AUV.exe when ready; keep supporting files together.
Quota cards appear in the Wizard and tray panel only when the existing connector has fetched
a valid, connected, non-stale allowance. Unavailable, failed, disconnected and stale quotas
are hidden. Real zero balances remain visible. A running app alone does not establish a quota.
Providers remain selectable as compact identity rows in the main app for connection setup.
Unavailable quota values, account metrics, charts and local estimates have no placeholder blocks.
The requested Wizard stays enabled when it has no cards and reappears after data is admitted.

Both Wizard modes are 20% wider than build 20261010.5. Regular base rows are 126 x 48 DIPs;
Minimalist uses its previous content-based width x 1.20. Heights, row gaps and fonts are unchanged.
WorkBuddy Minimalist shows compact Credits only: 999, 1.5k, 9.9k, 10k, 14k, 99k, 1.3M.
Standard compact labels have at most four characters including the dot and unit. They round
down and never overstate the balance; the exact Credit balance stays in the tooltip and other views.
Quota fills are stronger; charts use a prominent blue independent of the Windows accent color.
Redundant descriptions and normal-mode banners are removed. Data-source detail is collapsible.
The tray panel sizes to available content. Native app icons retain their adaptive appearance.

Existing Codex auto-refresh and WorkBuddy official-site connection are retained. No new process
discovery, account login, transport or local history reader is enabled. A local app is shown only
after a supported connection can actually fetch quota. Claude/Antigravity remain prepared only.
Windows storage inventory and mutation remain unavailable.

For later offline inspection: AUV.exe --offline --show-widget
For explicit fixtures: AUV.exe --demo --offline --show-widget (separate preferences).
Normal launch can refresh Codex through your installed codex.exe and its existing ChatGPT login.
WorkBuddy requires the optional Microsoft Edge WebView2 Runtime and its separate official-site session.
Ctrl+Shift+W: Wizard; Ctrl+Shift+U: Quick Panel; Ctrl+Comma: settings; Ctrl+Shift+Q: Quit.
F5: refresh selected provider. Alt+A / Alt+T / Alt+S: module navigation.

Local preview only: no installer, startup registration, signing, storage operations or public release.
No account snapshots or browser sessions are packaged. SOURCE-MANIFEST.json and BUILD-INFO.json
identify the candidate. ZIP SHA-256 is supplied alongside the archive.
"@ | Set-Content -LiteralPath (Join-Path $publishRoot 'README.txt') -Encoding utf8
}
if ($ValidatedRefinement) {
@"
AUV 0.16.0 Windows Validated Refinement Preview — build $Build — Windows 11 x64

Extract the complete folder and run AUV.exe. Keep all supporting files together.
This local candidate passed automated tests and opt-in native WPF checks; BUILD-INFO.json
records this build's validation summary. Reports are local evidence, not independent QA.

Unavailable, disconnected, failed and stale quotas are hidden from Wizard and tray cards.
Verified zero remains visible. Unavailable providers retain compact 36 DIP settings rows.
Regular Wizard base rows are 126 x 48 DIPs. Both modes are 20% wider than build .5;
heights, row gaps and fonts are unchanged. Minimalist WorkBuddy Credits use at most four
characters including dot/unit, rounded down; hover shows the exact native Credit balance.
Quota bars and token charts are more prominent. Empty metrics and redundant text are removed.
The title icon follows app appearance; taskbar/tray icons follow Windows Shell appearance.

Codex reads the installed client's existing login through its read-only usage interface.
No inference is started. WorkBuddy retains experimental official-site WebView2 Credit sync;
its optional connection needs Microsoft Edge WebView2 Runtime and manual sign-in.
Claude/Antigravity have prepared interfaces only. Windows storage mutation is unavailable.

Desktop Wizard is a separate floating window above apps. Drag to move, click a provider
to open its details, right click for pin/density/hide. Tray popup includes read-only CPU/RAM.
Ctrl+Shift+W: Wizard; Ctrl+Shift+U: tray popup; Ctrl+Comma: settings; Ctrl+Shift+Q: Quit.
F5: refresh selected provider. Alt+A / Alt+T / Alt+S: module navigation.
For offline launch: AUV.exe --offline --show-widget
For explicit sample data: AUV.exe --demo --offline --show-widget (separate preferences).

Local portable preview only: no installer, startup service, signing or public release.
No account snapshots or browser profiles are packaged. Source/build manifests identify
the candidate. ZIP SHA-256 is supplied alongside the archive.
"@ | Set-Content -LiteralPath (Join-Path $publishRoot 'README.txt') -Encoding utf8
}
if ($Stable) {
@"
AUV $Version — Windows 11 x64 — Stable — build $Build

The user-designated latest local Windows stable version, promoted from validated build .7.
Extract the complete folder and run AUV.exe. Keep all supporting files together.
The executable, native window title, account client identity and package metadata use $Version.
Existing Windows settings and owned connection sessions retain their current locations.

Includes AUV, ThreadOS, Desktop Wizard and the tray usage/performance popup.
Only fetched, connected, non-stale quota cards appear; verified zero remains visible.
Regular Wizard base rows are 126 x 48 DIPs. Minimalist WorkBuddy Credits use compact
labels of at most four characters; hover shows the exact balance. Native icons adapt to appearance.

Codex reads the installed client's existing login using its read-only usage interface.
WorkBuddy retains experimental official-page Credit sync through its separate WebView2 session;
the optional connection requires Microsoft Edge WebView2 Runtime and manual sign-in.
Claude and Antigravity remain prepared connectors without enabled live transports.
Sectorium remains an interface with storage mutation disabled.

Ctrl+Shift+W: Wizard; Ctrl+Shift+U: usage popup; Ctrl+Comma: settings; Ctrl+Shift+Q: Quit.
F5: refresh selected provider. Alt+A / Alt+T / Alt+S: module navigation.
Offline: AUV.exe --offline --show-widget
Explicit sample data: AUV.exe --demo --offline --show-widget (separate preferences).

Portable local package. No installer, startup service, signing or public upload is included.
Account snapshots and browser profiles are not packaged. BUILD-INFO.json records verification;
SOURCE-MANIFEST.json identifies source. ZIP SHA-256 is supplied alongside the archive.
"@ | Set-Content -LiteralPath (Join-Path $publishRoot 'README.txt') -Encoding utf8
}
$zipPath = Join-Path $artifactRoot ($PublishName + '.zip')
if (Test-Path -LiteralPath $zipPath) { [IO.File]::Delete($zipPath) }
[IO.Compression.ZipFile]::CreateFromDirectory($publishRoot, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
$zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $checked = 0
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $stream = $entry.Open()
        try { $entryHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
        $original = Join-Path $publishRoot $entry.FullName.Replace('/','\')
        if ($entryHash -ne (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash) { throw "Archive verification failed: $($entry.FullName)" }
        $checked++
    }
} finally { $archive.Dispose() }
$publishedCount = @(Get-ChildItem -LiteralPath $publishRoot -Recurse -File).Count
if ($checked -ne $publishedCount) { throw 'Archive file count mismatch.' }
"$zipHash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ascii
[ordered]@{ Zip = $zipPath; SHA256 = $zipHash; Bytes = (Get-Item -LiteralPath $zipPath).Length; SourceIdentity = $sourceHash; FilesVerified = $checked; AllPublishedFilesMatched = $true } |
    ConvertTo-Json | Tee-Object -FilePath (Join-Path $artifactRoot $(if ($Stable) { "evidence\stable-$Version-package.json" } elseif ($ValidatedRefinement) { 'evidence\validated-refinement-package.json' } elseif ($VisibilityRefinement) { 'evidence\visibility-refinement-package.json' } elseif ($UiRefinement) { 'evidence\ui-refinement-package.json' } elseif ($ProviderIntegration) { 'evidence\provider-package-verification.json' } else { 'evidence\product-package-verification.json' }))
