# Build asset generation only. Does not launch AUV, access accounts or run tests.
param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$taskAssets = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\AUV.Windows.App\Assets'
if (!$OutputPath) { $OutputPath = Join-Path $taskAssets 'AppIcon.ico' }
[xml]$taskSvg = Get-Content -LiteralPath (Join-Path $taskAssets 'AppMark.svg') -Raw
$taskInk = [Windows.Media.BrushConverter]::new().ConvertFromInvariantString('#2467D5')
$taskDrawing = [Windows.Media.DrawingGroup]::new()
foreach ($taskNode in $taskSvg.DocumentElement.ChildNodes) {
    if ($taskNode.NodeType -ne [Xml.XmlNodeType]::Element) { continue }
    if ($taskNode.LocalName -eq 'circle') {
        $taskGeometry = [Windows.Media.EllipseGeometry]::new([Windows.Point]::new([double]$taskNode.cx, [double]$taskNode.cy), [double]$taskNode.r, [double]$taskNode.r)
    } else { $taskGeometry = [Windows.Media.Geometry]::Parse($taskNode.d) }
    $taskFill = if ($taskNode.fill -eq 'none') { $null } else { $taskInk }
    $taskPen = $null
    if ($taskNode.HasAttribute('stroke')) {
        $taskPen = [Windows.Media.Pen]::new($taskInk, [double]$taskNode.GetAttribute('stroke-width'))
        $taskPen.StartLineCap = [Windows.Media.PenLineCap]::Round
        $taskPen.EndLineCap = [Windows.Media.PenLineCap]::Round
        $taskPen.LineJoin = [Windows.Media.PenLineJoin]::Round
    }
    $taskDrawing.Children.Add([Windows.Media.GeometryDrawing]::new($taskFill, $taskPen, $taskGeometry))
}
$taskSizes = @(16,20,24,32,40,48,64,256)
$taskFrames = [Collections.Generic.List[byte[]]]::new()
foreach ($taskSize in $taskSizes) {
    $taskVisual = [Windows.Media.DrawingVisual]::new()
    $taskContext = $taskVisual.RenderOpen()
    $taskContext.PushTransform([Windows.Media.ScaleTransform]::new($taskSize / 16.0, $taskSize / 16.0))
    $taskContext.DrawDrawing($taskDrawing); $taskContext.Pop(); $taskContext.Close()
    $taskBitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new($taskSize,$taskSize,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $taskBitmap.Render($taskVisual)
    $taskEncoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
    $taskEncoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($taskBitmap))
    $taskStream = [IO.MemoryStream]::new()
    try { $taskEncoder.Save($taskStream); $taskFrames.Add($taskStream.ToArray()) } finally { $taskStream.Dispose() }
}
$taskFile = [IO.File]::Create([IO.Path]::GetFullPath($OutputPath))
$taskWriter = [IO.BinaryWriter]::new($taskFile)
try {
    $taskWriter.Write([uint16]0); $taskWriter.Write([uint16]1); $taskWriter.Write([uint16]$taskSizes.Count)
    $taskOffset = 6 + 16 * $taskSizes.Count
    for ($taskIndex = 0; $taskIndex -lt $taskSizes.Count; $taskIndex++) {
        $taskDimension = if ($taskSizes[$taskIndex] -eq 256) { 0 } else { $taskSizes[$taskIndex] }
        $taskWriter.Write([byte]$taskDimension); $taskWriter.Write([byte]$taskDimension)
        $taskWriter.Write([byte]0); $taskWriter.Write([byte]0); $taskWriter.Write([uint16]1); $taskWriter.Write([uint16]32)
        $taskWriter.Write([uint32]$taskFrames[$taskIndex].Length); $taskWriter.Write([uint32]$taskOffset)
        $taskOffset += $taskFrames[$taskIndex].Length
    }
    foreach ($taskFrame in $taskFrames) { $taskWriter.Write([byte[]]$taskFrame) }
} finally { $taskWriter.Dispose(); $taskFile.Dispose() }
Write-Output "Generated native vector icon: $OutputPath"
