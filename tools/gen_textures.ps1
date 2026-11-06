# Patina – Textur-Generator (reproduzierbar, fester Zufalls-Seed). Nicht im Release-Zip.
# Erzeugt Graustufen-Masken (weiß, Form im Alphakanal) für Kratzer in drei Tiefen.
# Eingefärbt wird zur Laufzeit (Konzept: Assets). Quadratisch wie die Spiel-Decals (art/dynamicDecals/textures, 2048²).
# Aufruf:  powershell -ExecutionPolicy Bypass -File tools\gen_textures.ps1
# Ausgabe: mod/art/patina/scratch_light.png, scratch_medium.png, scratch_deep.png
# Linien laufen senkrecht = Länge des Decals (Decal-„oben“ = Schleifrichtung).

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"
$size = 1024
$outDir = Join-Path $PSScriptRoot "..\mod\art\patina"
New-Item -ItemType Directory -Force $outDir | Out-Null

function New-Canvas {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
  return @($bmp, $g)
}

# eine leicht wackelnde, an den Enden ausgeblendete Linie von oben nach unten
function Draw-Streak($g, $rnd, [double]$x, [double]$width, [int]$alphaMax, [double]$wobble, [int]$segments) {
  $y0 = $rnd.NextDouble() * $size * 0.15
  $y1 = $size - $rnd.NextDouble() * $size * 0.15
  $prevX = $x; $prevY = $y0
  for ($i = 1; $i -le $segments; $i++) {
    $t = $i / $segments
    $y = $y0 + ($y1 - $y0) * $t
    $nx = $prevX + ($rnd.NextDouble() - 0.5) * $wobble
    $fade = [Math]::Sin([Math]::PI * $t)                      # Enden auslaufen lassen
    $a = [int]([Math]::Max(0, [Math]::Min(255, $alphaMax * (0.55 + 0.45 * $fade) * (0.8 + 0.2 * $rnd.NextDouble()))))
    $w = [single]([Math]::Max(0.6, $width * (0.6 + 0.4 * $fade) * (0.85 + 0.3 * $rnd.NextDouble())))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($a, 255, 255, 255), $w)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, [single]$prevX, [single]$prevY, [single]$nx, [single]$y)
    $pen.Dispose()
    $prevX = $nx; $prevY = $y
  }
}

function Save($bmp, $g, $name) {
  $g.Dispose()
  $path = Join-Path $outDir $name
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "geschrieben: $path"
}

# leicht: viele Haarlinien (Klarlack)
$rnd = New-Object System.Random(1001)
$c = New-Canvas
for ($i = 0; $i -lt 14; $i++) {
  Draw-Streak $c[1] $rnd ($size * (0.08 + 0.84 * $rnd.NextDouble())) (6 + 6 * $rnd.NextDouble()) (170 + $rnd.Next(85)) 6 40
}
Save $c[0] $c[1] "scratch_light.png"

# mittel: weniger, kräftigere Linien (Grundierung)
$rnd = New-Object System.Random(2002)
$c = New-Canvas
for ($i = 0; $i -lt 10; $i++) {
  Draw-Streak $c[1] $rnd ($size * (0.12 + 0.76 * $rnd.NextDouble())) (14 + 12 * $rnd.NextDouble()) (210 + $rnd.Next(45)) 10 40
}
for ($i = 0; $i -lt 14; $i++) {
  Draw-Streak $c[1] $rnd ($size * (0.08 + 0.84 * $rnd.NextDouble())) (5 + 4 * $rnd.NextDouble()) (150 + $rnd.Next(80)) 6 40
}
Save $c[0] $c[1] "scratch_medium.png"

# tief: wenige breite Riefen mit ausgefransten Rändern (blankes Metall)
$rnd = New-Object System.Random(3003)
$c = New-Canvas
for ($i = 0; $i -lt 3; $i++) {
  $x = $size * (0.25 + 0.5 * $rnd.NextDouble())
  Draw-Streak $c[1] $rnd $x (22 + 18 * $rnd.NextDouble()) 255 14 60
  for ($k = 0; $k -lt 6; $k++) {   # Fransen
    Draw-Streak $c[1] $rnd ($x + ($rnd.NextDouble() - 0.5) * 40) (3 + 4 * $rnd.NextDouble()) (120 + $rnd.Next(100)) 12 50
  }
}
Save $c[0] $c[1] "scratch_deep.png"
