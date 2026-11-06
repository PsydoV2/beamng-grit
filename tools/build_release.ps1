# Grit – Release-ZIP bauen.
# Aufruf:  powershell -ExecutionPolicy Bypass -File tools\build_release.ps1 -Version 0.2.0
# Ergebnis: build\grit_v<Version>.zip
#   Inhalt: art/, lua/, scripts/ aus mod\ (ohne Zwischenordner) + README.md + LICENSE
#   Release-Schalter: Entwickler-Log (M.debugLog) und Sensor-Diagnose (DIAG) aus.
# Zip-Einträge mit "/" als Trenner (Compress-Archive von PowerShell 5.1 schreibt "\").

param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$src = Join-Path $root "mod"
$outDir = Join-Path $root "build"
$zipPath = Join-Path $outDir ("grit_v{0}.zip" -f $Version)
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Dateien, die fürs Release umgeschaltet werden: relativer Pfad → (gesucht, ersetzt). Fehlt der Text → Abbruch.
$patches = @{
  "lua/ge/extensions/grit/main.lua"         = @("M.debugLog = true", "M.debugLog = false")
  "lua/vehicle/controller/grit/sensor.lua"  = @("local DIAG = true", "local DIAG = false")
}

New-Item -ItemType Directory -Force $outDir | Out-Null
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
$found = @{}
try {
  $files = Get-ChildItem -Path $src -Recurse -File
  foreach ($f in $files) {
    $rel = $f.FullName.Substring($src.Length + 1).Replace("\", "/")
    $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try {
      if ($patches.ContainsKey($rel)) {
        $text = [System.IO.File]::ReadAllText($f.FullName, $utf8)
        $p = $patches[$rel]
        $count = ([regex]::Matches($text, [regex]::Escape($p[0]))).Count
        if ($count -ne 1) { throw "Release-Schalter '$($p[0])' in $rel gefunden: $count-mal (erwartet 1)" }
        $bytes = $utf8.GetBytes($text.Replace($p[0], $p[1]))
        $stream.Write($bytes, 0, $bytes.Length)
        $found[$rel] = $true
      } else {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $stream.Write($bytes, 0, $bytes.Length)
      }
    } finally { $stream.Dispose() }
  }
  foreach ($doc in @("README.md", "LICENSE")) {
    [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root $doc), $doc)
  }
} finally { $zip.Dispose() }

foreach ($k in $patches.Keys) { if (-not $found[$k]) { Remove-Item $zipPath -Force; throw "Datei fehlt: $k" } }

# Prüfen: Pflichtdateien da, keine Backslashes, Schalter aus
$check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
  $names = $check.Entries | ForEach-Object { $_.FullName }
  foreach ($need in @("scripts/grit/modScript.lua", "lua/ge/extensions/grit/main.lua", "lua/ge/extensions/grit/render.lua",
                      "lua/vehicle/controller/grit/sensor.lua", "README.md", "LICENSE")) {
    if ($names -notcontains $need) { throw "Pflichtdatei fehlt im ZIP: $need" }
  }
  if ($names | Where-Object { $_ -like "*\*" }) { throw "ZIP enthält Backslash-Pfade" }
  foreach ($k in $patches.Keys) {
    $r = New-Object System.IO.StreamReader($check.GetEntry($k).Open(), $utf8)
    $t = $r.ReadToEnd(); $r.Dispose()
    if (-not $t.Contains($patches[$k][1])) { throw "Release-Schalter nicht gesetzt in $k" }
  }
  $size = (Get-Item $zipPath).Length / 1KB
  Write-Output ("Fertig: {0} ({1} Dateien, {2:N0} KB)" -f $zipPath, $names.Count, $size)
  Write-Output "Release-Schalter: Entwickler-Log aus, Sensor-Diagnose aus."
} finally { $check.Dispose() }
