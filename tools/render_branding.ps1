# Grit – Marken-Grafiken rendern (branding/src/render.html → branding/out/*.png) mit Chrome/Edge headless.
# Aufruf: powershell -ExecutionPolicy Bypass -File tools\render_branding.ps1 [-Seed 7] [-Only banner]
param([int]$Seed = 7, [string]$Only = "")
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$src = Join-Path $root "branding\src\render.html"
$out = Join-Path $root "branding\out"
New-Item -ItemType Directory -Force $out | Out-Null

$browser = @("C:\Program Files\Google\Chrome\Application\chrome.exe",
             "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw "Weder Chrome noch Edge gefunden" }

$assets = [ordered]@{
  "logo" = "1024,1024"; "logo-transparent" = "1024,1024"; "wordmark" = "2000,760"
  "banner" = "1920,640"; "thumbnail" = "1280,720"
  "header-scratches" = "1600,360"; "header-dirt" = "1600,360"; "header-dust" = "1600,360"
}
$profile = Join-Path $env:TEMP "grit-render-profile"
$url0 = "file:///" + $src.Replace("\", "/")
foreach ($name in $assets.Keys) {
  if ($Only -and $name -ne $Only) { continue }
  $png = Join-Path $out "grit-$name.png"
  if (Test-Path $png) { Remove-Item $png -Force }
  $cargs = @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
            "--default-background-color=00000000", "--user-data-dir=$profile", "--virtual-time-budget=4000",
            "--window-size=$($assets[$name])", "--screenshot=$png", "$url0`?asset=$name&seed=$Seed")
  $cargs = $cargs | ForEach-Object { if ($_ -match " ") { "`"$_`"" } else { $_ } }
  Start-Process -FilePath $browser -ArgumentList $cargs -Wait -WindowStyle Hidden
  $t = 0; while (-not (Test-Path $png) -and $t -lt 40) { Start-Sleep -Milliseconds 250; $t++ }
  if (Test-Path $png) { Write-Output ("{0,-18} {1,10} {2:N0} KB" -f $name, $assets[$name], ((Get-Item $png).Length / 1KB)) }
  else { Write-Output "$name FEHLT" }
}
