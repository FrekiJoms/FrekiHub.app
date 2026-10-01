Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$bitmap = New-Object System.Drawing.Bitmap 1024,1024
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$background = [System.Drawing.Color]::FromArgb(30,33,31)
$graphics.Clear($background)
$ink = [System.Drawing.Brushes]::WhiteSmoke
$dark = New-Object System.Drawing.SolidBrush $background
$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::WhiteSmoke),22
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
foreach ($point in @(@(304,304),@(720,304),@(304,720),@(720,720))) {
  $graphics.DrawLine($pen,512,512,$point[0],$point[1])
}
$graphics.FillEllipse($ink,470,470,84,84)
# The four connected nodes carry the established FrekiHub hub motif.
$graphics.FillEllipse($ink,230,230,148,148)
$clockPen = New-Object System.Drawing.Pen $background,12
$clockPen.StartCap = $pen.StartCap; $clockPen.EndCap = $pen.EndCap
$graphics.DrawLine($clockPen,304,304,304,263)
$graphics.DrawLine($clockPen,304,304,333,320)
$graphics.FillEllipse($ink,648,224,144,144)
$pin = New-Object System.Drawing.Drawing2D.GraphicsPath
$pin.AddPolygon([System.Drawing.Point[]]@([System.Drawing.Point]::new(658,320),[System.Drawing.Point]::new(782,320),[System.Drawing.Point]::new(720,420)))
$graphics.FillPath($ink,$pin)
$graphics.FillEllipse($dark,701,272,38,38)
$graphics.FillEllipse($ink,230,646,148,148)
$moneyPen = New-Object System.Drawing.Pen $background,11
$graphics.DrawArc($moneyPen,276,683,56,42,80,260)
$graphics.DrawArc($moneyPen,276,716,56,42,-100,260)
$graphics.DrawLine($moneyPen,304,673,304,767)
$graphics.FillRectangle($ink,650,650,140,140)
foreach ($line in @(690,720,750)) { $graphics.FillRectangle($dark,675,$line,90,10) }
$graphics.Dispose()
function Save-Icon([string]$path,[int]$size) {
  $output = New-Object System.Drawing.Bitmap $size,$size
  $g = [System.Drawing.Graphics]::FromImage($output)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($bitmap,0,0,$size,$size)
  $output.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $output.Dispose()
}
$iconFolder = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$catalog = Get-Content -LiteralPath (Join-Path $iconFolder 'Contents.json') -Raw | ConvertFrom-Json
foreach ($entry in $catalog.images) {
  $size = [int]([double]($entry.size.Split('x')[0]) * [int]($entry.scale.Replace('x','')))
  Save-Icon (Join-Path $iconFolder $entry.filename) $size
}
foreach ($density in @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}.GetEnumerator()) {
  Save-Icon (Join-Path $projectRoot "android/app/src/main/res/mipmap-$($density.Key)/ic_launcher.png") $density.Value
}
$bitmap.Dispose(); $pen.Dispose(); $clockPen.Dispose(); $moneyPen.Dispose(); $dark.Dispose(); $pin.Dispose()
Write-Output 'Native FrekiHub icons generated.'
