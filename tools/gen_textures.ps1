# Grit – Textur-Generator (reproduzierbar, fester Zufalls-Seed). Nicht im Release-Zip.
# Erzeugt Graustufen-Masken (weiß, Form im Alphakanal) für Kratzer in drei Tiefen.
# Eingefärbt wird zur Laufzeit (Konzept: Assets). Quadratisch wie die Spiel-Decals (art/dynamicDecals/textures, 2048²).
# Aufruf:  powershell -ExecutionPolicy Bypass -File tools\gen_textures.ps1
# Ausgabe: mod/art/grit/scratch_light_1..3.png, scratch_medium_1..3.png, scratch_deep_1..3.png (Variante 1 = alter Stand),
#          dirt_splash.png, dust.png, solid.png, crack_hair.png, crack_web.png, uvcheck.png
# Linien laufen senkrecht = Länge des Decals (Decal-„oben“ = Schleifrichtung).

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"
$size = 1024
$outDir = Join-Path $PSScriptRoot "..\mod\art\grit"
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

# Variante für die Kratzer-Varianten: freier Anfang/Ende (y0, y1) und Drift (Versatz in x über die ganze Länge,
# schräge Linie). Draw-Streak bleibt unverändert, damit Variante 1 jeder Stufe pixelgleich zum alten Stand bleibt.
function Draw-StreakEx($g, $rnd, [double]$x, [double]$y0, [double]$y1, [double]$drift, [double]$width, [int]$alphaMax, [double]$wobble, [int]$segments) {
  $prevX = $x; $prevY = $y0; $off = 0.0          # $off = aufsummiertes Wackeln wie bei Draw-Streak
  for ($i = 1; $i -le $segments; $i++) {
    $t = $i / $segments
    $y = $y0 + ($y1 - $y0) * $t
    $off += ($rnd.NextDouble() - 0.5) * $wobble
    $nx = [Math]::Max($size * 0.05, [Math]::Min($size * 0.95, $x + $drift * $t + $off))
    $fade = [Math]::Sin([Math]::PI * $t)
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

# zufälliger Teilabschnitt der Länge: Linie setzt später ein und/oder bricht früher ab (mind. 35 % der Höhe)
function Get-Span($rnd) {
  $len = $size * (0.35 + 0.55 * $rnd.NextDouble())
  $y0 = $size * 0.04 + $rnd.NextDouble() * ($size * 0.92 - $len)
  return @($y0, ($y0 + $len))
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
Save $c[0] $c[1] "scratch_light_1.png"

# leicht 2: wenige Haarlinien, die mittendrin einsetzen oder abbrechen
$rnd = New-Object System.Random(1101)
$c = New-Canvas
for ($i = 0; $i -lt 9; $i++) {
  $sp = Get-Span $rnd
  Draw-StreakEx $c[1] $rnd ($size * (0.08 + 0.84 * $rnd.NextDouble())) $sp[0] $sp[1] 0 (6 + 6 * $rnd.NextDouble()) (170 + $rnd.Next(85)) 6 40
}
Save $c[0] $c[1] "scratch_light_2.png"

# leicht 3: dichtes, leicht schräges Bündel feiner Linien (Schleifspur einer Kante)
$rnd = New-Object System.Random(1201)
$c = New-Canvas
$cx = $size * (0.40 + 0.2 * $rnd.NextDouble()); $drift = $size * (0.06 + 0.08 * $rnd.NextDouble()) * $(if ($rnd.NextDouble() -lt 0.5) { -1 } else { 1 })
for ($i = 0; $i -lt 18; $i++) {
  $y0 = $rnd.NextDouble() * $size * 0.15; $y1 = $size - $rnd.NextDouble() * $size * 0.15
  Draw-StreakEx $c[1] $rnd ($cx - $drift / 2 + ($rnd.NextDouble() - 0.5) * $size * 0.3) $y0 $y1 $drift (4 + 5 * $rnd.NextDouble()) (150 + $rnd.Next(100)) 5 40
}
Save $c[0] $c[1] "scratch_light_3.png"

# mittel: weniger, kräftigere Linien (Grundierung)
$rnd = New-Object System.Random(2002)
$c = New-Canvas
for ($i = 0; $i -lt 10; $i++) {
  Draw-Streak $c[1] $rnd ($size * (0.12 + 0.76 * $rnd.NextDouble())) (14 + 12 * $rnd.NextDouble()) (210 + $rnd.Next(45)) 10 40
}
for ($i = 0; $i -lt 14; $i++) {
  Draw-Streak $c[1] $rnd ($size * (0.08 + 0.84 * $rnd.NextDouble())) (5 + 4 * $rnd.NextDouble()) (150 + $rnd.Next(80)) 6 40
}
Save $c[0] $c[1] "scratch_medium_1.png"

# mittel 2: kräftige Linien teils abgebrochen, feine Linien durchgehend
$rnd = New-Object System.Random(2102)
$c = New-Canvas
for ($i = 0; $i -lt 6; $i++) {
  $sp = Get-Span $rnd
  Draw-StreakEx $c[1] $rnd ($size * (0.12 + 0.76 * $rnd.NextDouble())) $sp[0] $sp[1] 0 (14 + 12 * $rnd.NextDouble()) (210 + $rnd.Next(45)) 10 40
}
for ($i = 0; $i -lt 12; $i++) {
  Draw-Streak $c[1] $rnd ($size * (0.08 + 0.84 * $rnd.NextDouble())) (5 + 4 * $rnd.NextDouble()) (150 + $rnd.Next(80)) 6 40
}
Save $c[0] $c[1] "scratch_medium_2.png"

# mittel 3: schräges Bündel, zwei kräftige Linien in der Mitte
$rnd = New-Object System.Random(2202)
$c = New-Canvas
$cx = $size * (0.40 + 0.2 * $rnd.NextDouble()); $drift = $size * (0.06 + 0.08 * $rnd.NextDouble()) * $(if ($rnd.NextDouble() -lt 0.5) { -1 } else { 1 })
for ($i = 0; $i -lt 2; $i++) {
  Draw-StreakEx $c[1] $rnd ($cx - $drift / 2 + ($rnd.NextDouble() - 0.5) * $size * 0.12) ($size * 0.06) ($size * 0.94) $drift (16 + 10 * $rnd.NextDouble()) (220 + $rnd.Next(35)) 10 40
}
for ($i = 0; $i -lt 14; $i++) {
  $sp = Get-Span $rnd
  Draw-StreakEx $c[1] $rnd ($cx - $drift / 2 + ($rnd.NextDouble() - 0.5) * $size * 0.4) $sp[0] $sp[1] $drift (5 + 4 * $rnd.NextDouble()) (150 + $rnd.Next(80)) 6 40
}
Save $c[0] $c[1] "scratch_medium_3.png"

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
Save $c[0] $c[1] "scratch_deep_1.png"

# tief 2: eine breite durchgehende Riefe + eine kurze daneben
$rnd = New-Object System.Random(3103)
$c = New-Canvas
$x = $size * (0.35 + 0.3 * $rnd.NextDouble())
Draw-StreakEx $c[1] $rnd $x ($size * 0.05) ($size * 0.95) 0 (34 + 14 * $rnd.NextDouble()) 255 14 60
for ($k = 0; $k -lt 8; $k++) {
  Draw-StreakEx $c[1] $rnd ($x + ($rnd.NextDouble() - 0.5) * 56) ($size * 0.06) ($size * 0.94) 0 (3 + 4 * $rnd.NextDouble()) (120 + $rnd.Next(100)) 12 50
}
$x2 = $x + $(if ($x -lt $size / 2) { 1 } else { -1 }) * $size * (0.15 + 0.1 * $rnd.NextDouble())
$sp = Get-Span $rnd
Draw-StreakEx $c[1] $rnd $x2 $sp[0] $sp[1] 0 (18 + 10 * $rnd.NextDouble()) 245 12 50
for ($k = 0; $k -lt 4; $k++) {
  Draw-StreakEx $c[1] $rnd ($x2 + ($rnd.NextDouble() - 0.5) * 36) $sp[0] $sp[1] 0 (3 + 3 * $rnd.NextDouble()) (120 + $rnd.Next(100)) 12 50
}
Save $c[0] $c[1] "scratch_deep_2.png"

# tief 3: zwei Riefen, die leicht schräg zusammenlaufen, beide nicht ganz durchgehend
$rnd = New-Object System.Random(3203)
$c = New-Canvas
$xa = $size * (0.30 + 0.1 * $rnd.NextDouble()); $xb = $size * (0.60 + 0.1 * $rnd.NextDouble())
$conv = ($xb - $xa) * (0.35 + 0.2 * $rnd.NextDouble())
foreach ($p in @(@($xa, ($conv / 2)), @($xb, (-$conv / 2)))) {   # Komma bindet stärker als „/“
  $sp = Get-Span $rnd
  Draw-StreakEx $c[1] $rnd $p[0] $sp[0] $sp[1] $p[1] (24 + 16 * $rnd.NextDouble()) 255 14 60
  for ($k = 0; $k -lt 6; $k++) {
    Draw-StreakEx $c[1] $rnd ($p[0] + ($rnd.NextDouble() - 0.5) * 40) $sp[0] $sp[1] $p[1] (3 + 4 * $rnd.NextDouble()) (120 + $rnd.Next(100)) 12 50
  }
}
Save $c[0] $c[1] "scratch_deep_3.png"

# Dreck-Spritzer: weiche Kleckse (radialer Verlauf) + kleine Tropfen, Mitte dichter (M2)
function Draw-Blob($g, [double]$cx, [double]$cy, [double]$r, [int]$alpha) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddEllipse([single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
  $br = New-Object System.Drawing.Drawing2D.PathGradientBrush($path)
  $br.CenterColor = [System.Drawing.Color]::FromArgb($alpha, 255, 255, 255)
  $br.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
  $g.FillPath($br, $path)
  $br.Dispose(); $path.Dispose()
}
$rnd = New-Object System.Random(4004)
$c = New-Canvas
for ($i = 0; $i -lt 40; $i++) {           # große weiche Kleckse, zur Mitte gehäuft
  $a = $rnd.NextDouble() * 2 * [Math]::PI; $d = [Math]::Pow($rnd.NextDouble(), 1.6) * $size * 0.33
  Draw-Blob $c[1] ($size / 2 + [Math]::Cos($a) * $d) ($size / 2 + [Math]::Sin($a) * $d) (40 + 70 * $rnd.NextDouble()) (90 + $rnd.Next(120))
}
for ($i = 0; $i -lt 260; $i++) {          # Tropfen, nach außen dünner
  $a = $rnd.NextDouble() * 2 * [Math]::PI; $d = [Math]::Sqrt($rnd.NextDouble()) * $size * 0.46
  Draw-Blob $c[1] ($size / 2 + [Math]::Cos($a) * $d) ($size / 2 + [Math]::Sin($a) * $d) (4 + 14 * $rnd.NextDouble()) (150 + $rnd.Next(105))
}
Save $c[0] $c[1] "dirt_splash.png"

# Staub: großflächiger, unregelmäßiger Schleier aus vielen sehr weichen Flecken + feinen Körnern (M2.2)
$rnd = New-Object System.Random(5005)
$c = New-Canvas
for ($i = 0; $i -lt 90; $i++) {
  # Fleck muss ganz im Bild bleiben (Abstand + Radius ≤ 0.47·size), sonst harte Kanten am Bildrand (M2.2 Lauf 2)
  $r = 70 + 90 * $rnd.NextDouble()
  $a = $rnd.NextDouble() * 2 * [Math]::PI; $d = [Math]::Sqrt($rnd.NextDouble()) * ($size * 0.47 - $r)
  Draw-Blob $c[1] ($size / 2 + [Math]::Cos($a) * $d) ($size / 2 + [Math]::Sin($a) * $d) $r (25 + $rnd.Next(45))
}
for ($i = 0; $i -lt 1400; $i++) {
  $a = $rnd.NextDouble() * 2 * [Math]::PI; $d = [Math]::Sqrt($rnd.NextDouble()) * $size * 0.45
  Draw-Blob $c[1] ($size / 2 + [Math]::Cos($a) * $d) ($size / 2 + [Math]::Sin($a) * $d) (1.5 + 3 * $rnd.NextDouble()) (60 + $rnd.Next(120))
}
Save $c[0] $c[1] "dust.png"

# Radierer (Spike 7, M3 Waschen): voll deckend weiß. Die Form gibt die Box vor, die Stärke das Alpha der
# Layer-Farbe (decal.ps.hlsl:222 alpha *= color.a)
$bmp = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 255, 255, 255))
Save $bmp $g "solid.png"

# M4 Risse (Konzept: Riss-Atlas, Haar- und Spinnennetzrisse für Kunststoff). M4.1 Lauf 3: dünne Linien gingen in der
# Grit-Textur verloren → Linien etwa so breit wie bei den Kratzern (physisch 2–5 mm). Gezackte Linie mit Verzweigungen,
# zum Ende dünner und schwächer. Alles bleibt mit Abstand im Bild (sonst harte Kanten, M2.2 Lauf 2).
function Draw-Crack($g, $rnd, [double]$x, [double]$y, [double]$ang, [double]$len, [double]$width, [int]$alpha, [int]$depth) {
  $steps = [Math]::Max(3, [int]($len / 14))
  $px = $x; $py = $y
  for ($i = 1; $i -le $steps; $i++) {
    $t = $i / $steps
    $ang += ($rnd.NextDouble() - 0.5) * 0.7                      # Zacken
    $nx = $px + [Math]::Cos($ang) * $len / $steps
    $ny = $py + [Math]::Sin($ang) * $len / $steps
    $r = [Math]::Sqrt(($nx - $size / 2) * ($nx - $size / 2) + ($ny - $size / 2) * ($ny - $size / 2))
    if ($r -gt $size * 0.47) { break }
    $w = [single]([Math]::Max(3, $width * (1 - 0.6 * $t)))
    $a = [int]([Math]::Max(30, $alpha * (1 - 0.5 * $t)))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($a, 255, 255, 255), $w)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, [single]$px, [single]$py, [single]$nx, [single]$ny)
    $pen.Dispose()
    if ($depth -gt 0 -and $rnd.NextDouble() -lt 0.18) {           # Verzweigung
      $side = if ($rnd.NextDouble() -lt 0.5) { -1 } else { 1 }
      Draw-Crack $g $rnd $nx $ny ($ang + $side * (0.4 + 0.6 * $rnd.NextDouble())) ($len * (1 - $t) * 0.6) ($w * 0.7) ([int]($a * 0.85)) ($depth - 1)
    }
    $px = $nx; $py = $ny
  }
}

# Haarriss: ein langer Riss durch die Mitte (Decal-„oben“ = Länge), wenige Äste
$rnd = New-Object System.Random(6006)
$c = New-Canvas
Draw-Crack $c[1] $rnd ($size / 2) ($size / 2) (-[Math]::PI / 2) ($size * 0.44) 14 245 2
Draw-Crack $c[1] $rnd ($size / 2) ($size / 2) ([Math]::PI / 2) ($size * 0.44) 14 245 2
Save $c[0] $c[1] "crack_hair.png"

# Spinnennetz: Strahlen vom Einschlagpunkt + gezackte Querrisse zwischen Nachbarstrahlen
$rnd = New-Object System.Random(6007)
$c = New-Canvas
$rays = 9
$angs = @()
for ($i = 0; $i -lt $rays; $i++) { $angs += ($i / $rays) * 2 * [Math]::PI + ($rnd.NextDouble() - 0.5) * 0.4 }
foreach ($a in $angs) { Draw-Crack $c[1] $rnd ($size / 2) ($size / 2) $a ($size * (0.30 + 0.15 * $rnd.NextDouble())) 16 250 1 }
foreach ($ring in @(0.10, 0.19, 0.28)) {
  for ($i = 0; $i -lt $rays; $i++) {
    if ($rnd.NextDouble() -lt 0.75) {
      $a0 = $angs[$i]; $a1 = $angs[($i + 1) % $rays]; if ($a1 -lt $a0) { $a1 += 2 * [Math]::PI }
      $r0 = $size * $ring * (0.85 + 0.3 * $rnd.NextDouble()); $r1 = $size * $ring * (0.85 + 0.3 * $rnd.NextDouble())
      $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(225, 255, 255, 255), [single](11 - 14 * $ring))
      $mid = ($a0 + $a1) / 2; $rm = ($r0 + $r1) / 2 * (0.92 + 0.1 * $rnd.NextDouble())
      $pts = @(
        (New-Object System.Drawing.PointF([single]($size / 2 + [Math]::Cos($a0) * $r0), [single]($size / 2 + [Math]::Sin($a0) * $r0))),
        (New-Object System.Drawing.PointF([single]($size / 2 + [Math]::Cos($mid) * $rm), [single]($size / 2 + [Math]::Sin($mid) * $rm))),
        (New-Object System.Drawing.PointF([single]($size / 2 + [Math]::Cos($a1) * $r1), [single]($size / 2 + [Math]::Sin($a1) * $r1))))
      $g = $c[1]; $g.DrawLines($pen, [System.Drawing.PointF[]]$pts); $pen.Dispose()
    }
  }
}
Draw-Blob $c[1] ($size / 2) ($size / 2) 34 235                       # Einschlagpunkt
Save $c[0] $c[1] "crack_web.png"

# Diagnose M5.3 (Covet weiße Stoßstange): UV-Karte. Rot = u, Grün = v, Blau = Schachbrett 8×8. Als Textur-Füllung über
# das ganze Auto gebacken zeigt sie, welche Teile dieselbe UV-Fläche nutzen (gleiche Farbe = gleiche Stelle).
$n = 256
$bmp = New-Object System.Drawing.Bitmap($n, $n, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $n; $y++) {
  for ($x = 0; $x -lt $n; $x++) {
    $b = if (((([int]($x / 32)) + ([int]($y / 32))) % 2) -eq 0) { 0 } else { 255 }
    $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $x, $y, $b))
  }
}
$g = [System.Drawing.Graphics]::FromImage($bmp)
Save $bmp $g "uvcheck.png"
