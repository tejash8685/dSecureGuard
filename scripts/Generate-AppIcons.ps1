$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$project = Split-Path -Parent $PSScriptRoot
$source = Join-Path $project 'assets/branding/d-secureguard-logo.png'
$image = [Drawing.Image]::FromFile($source)
function Write-Icon([string]$Path, [int]$Size) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $bitmap = [Drawing.Bitmap]::new($Size, $Size, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.DrawImage($image, 0, 0, $Size, $Size)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
try {
    foreach ($entry in @{'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192}.GetEnumerator()) {
        Write-Icon (Join-Path $project "android/app/src/main/res/mipmap-$($entry.Key)/ic_launcher.png") $entry.Value
    }
    $iconSet = Join-Path $project 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    $manifest = Get-Content -LiteralPath (Join-Path $iconSet 'Contents.json') -Raw | ConvertFrom-Json
    foreach ($icon in $manifest.images) {
        $size = [double]::Parse(($icon.size -split 'x')[0], [Globalization.CultureInfo]::InvariantCulture)
        $scale = [double]::Parse($icon.scale.TrimEnd('x'), [Globalization.CultureInfo]::InvariantCulture)
        Write-Icon (Join-Path $iconSet $icon.filename) ([int]($size * $scale))
    }
    foreach ($size in @(192, 512)) {
        Write-Icon (Join-Path $project "web/icons/Icon-$size.png") $size
        Write-Icon (Join-Path $project "web/icons/Icon-maskable-$size.png") $size
    }
    Write-Icon (Join-Path $project 'web/favicon.png') 32
    Write-Host 'Updated Android, iOS and web icons from the D SecureGuard logo.'
} finally { $image.Dispose() }
