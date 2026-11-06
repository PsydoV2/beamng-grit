# Grit (Code-Name Patina) – BeamNG.drive-Mod für dynamischen Dreck und Kratzer

Name: **Grit**, Forum-Titel „Grit – Dynamic Dirt, Scratches & Cracks for every vehicle“. Intern (Dateien, `patina_main`)
heißt es noch Patina. `README.md` ist die öffentliche Beschreibung (Englisch), bei neuen Features mitpflegen.

Übergabe für neue Sessions. Stand: 2026-11-06, letzter Commit siehe `git log -1`.
Ausführliche Belege, Messwerte und jede Testrunde: **`FINDINGS.md`** (vor Änderungen den passenden Abschnitt lesen).

## Personen und Zusammenarbeit
- Sebastian, Autor. **Antworten auf Deutsch**, kurz und konkret.
- Ich schreibe den Code. Sebastian testet im Spiel, gibt Konsolenbefehle ein und meldet kurz zurück.
  Logs und Screenshots lese ich selbst.
- Testanweisungen immer als nummerierte Schritte. Konsolenbefehle **ohne `~`** davor angeben.
  Am Ende 1–3 konkrete Fragen stellen.
- Konzeptdokument (Claude Doc, Rev 17): https://claude.ai/artifact/UGZXupUS9CT57pB6WvMoP1
  Abweichungen vom Konzept kurz begründen und **vorher fragen**.

## Regeln (von Sebastian festgelegt)
- **Keine Spieldateien ändern.** Spielcode nur lesen.
- **Jede API im Spielcode belegen** und die Fundstelle (Datei:Zeile) in `FINDINGS.md` eintragen.
  Nur Funktionen benutzen, die es im Spiel-Lua gibt.
- **Kleine Schritte:** ändern → Sebastian testet → Log prüfen → Ergebnis in FINDINGS.md → git commit.
- **Optik nicht selbst beurteilen**, Screenshots anfordern.
- **Performance messen, nicht schätzen.** Die Messung ist eingebaut, siehe `status()`.
- **Keinen Code und keine Assets aus anderen Mods übernehmen.** `dynamic_scratches_mod_beta.zip` im Mod-Ordner
  nicht ansehen. Sebastian hat ihn zum Testen deaktiviert.
- Lua im Extension-Muster, kein globaler Zustand. LuaJIT/Lua 5.1. Log über `log('I', tag, msg)`.
- Commit-Nachrichten auf Deutsch, Abschluss: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Pfade
- Spiel: `F:\SteamLibrary\steamapps\common\BeamNG.drive`, Version 0.40.5.0, Lua unter `lua/`.
- User-Ordner: `C:\Users\sebfa\AppData\Local\BeamNG\BeamNG.drive\current`
  - `mods/unpacked/patina` ist eine **Junction** auf `E:\BeamNGMods\Dynamic Patina\mod`.
    Änderungen wirken nach **Strg+L** im Spiel (Lua neu laden).
  - **`patina.log`** ist unser eigenes Log, wird sofort geschrieben (`M.debugLog`). `beamng.log` puffert minutenlang.
  - Screenshots (Strg+P) liegen unter `screenshots/2026-11/`.
- Repo `E:\BeamNGMods\Dynamic Patina`:
  - `mod/scripts/patina/modScript.lua` lädt `patina_main`.
  - `mod/lua/ge/extensions/patina/main.lua`: GE-Extension, Fahrzeug-Lebenszyklus, Ereignis → Decal, Konsolenbefehle.
  - `mod/lua/ge/extensions/patina/render.lua`: Decal-Renderer pro Fahrzeug (Projektion, Synthese, Backen).
  - `mod/lua/vehicle/controller/patina/sensor.lua`: Fahrzeug-Controller, erzeugt Ereignisse aus Kollisionen und Rädern.
  - `mod/lua/vehicle/controller/patinaSpike/eventLogger.lua`: alter Spike-5-Logger, wird nicht benutzt.
  - `mod/art/patina/*.png`: Texturen, erzeugt von `tools/gen_textures.ps1` mit festen Seeds.
    Aufruf: `powershell.exe -ExecutionPolicy Bypass -File tools/gen_textures.ps1`
- Shell: Git Bash. `cd` in Bash springt manchmal zurück, deshalb absolute Pfade benutzen.

## Architektur (Weg A′)
- **Zwei DecalProjections pro Fahrzeug:**
  - `@PatinaTexture` (Farbe) und `@PatinaMask` (Maske).
  - Eine zusätzliche Material-Stage auf **Skin-Kopien** der lackierten Materialien.
  - Eigener Skin-Slot `patina`, Materialname `<mesh>.patina.v<ID>`.
  - Ein Neuspawn beim Aktivieren (ca. 450 ms).
  - `prepare()` läuft verzögert (`prepareLater`, 2 Frames nach dem Spawn-Hook). Direkt im Hook ging es nach
    Strg+L und beim Ersetzen nicht.
- **Decal-Raum:** Positionen relativ zum Referenzknoten, also Anfangs-Knotenposition minus `refPos`
  (`v.data.refNodes[0].ref`).
- **Ausrichtung:** über `decalRotation`, die Kamera-Rolle wird ignoriert. Formel steht in `R:request`
  (Bezugsachse z in der Fläche, auf waagerechten Flächen y, Drehsinn negativ).
- **Box-Projektion ohne Winkeltest:** `decal.ps.hlsl:116-121`. Deshalb die Tiefe klein halten, sonst entstehen
  Streifen und „geometrische Formen“.
- **Treffer prüfen:**
  - Entlang der Normalen höchstens `tolAlong`: Kratzer 0.1, Spritzer 0.35/0.5, Staub 0.5–1.2, Kontakt 0.2.
  - Seitlich höchstens 0.25 m.
  - Sonst verwerfen. Typische Fälle: Welt-Treffer bei ±8000 oder Strahl durch eine Lücke.
- **Spike 6 – Decals ohne Projektion:**
  - `projectDynamicDecals` kostet **12–15 ms CPU pro Aufruf**, das war die Ruckel-Ursache.
  - Deshalb wird pro Zelle (Region + 0,4-m-Raster) nur einmal echt projiziert. Dabei merkt sich die Zelle den
    Abstand zur Oberfläche.
  - Alle weiteren Decals der Zelle baut `R:synth` aus einer Vorlage, bis zu 4 pro Frame:
    `worldToViewToScreen = projM * camM⁻¹`, `decalPos = pos + n*off`.
  - Verfehlt eine Zelle zweimal, wird sie übersprungen.
  - Umschalten mit `patina_main.synthetic(false)`.
  - Bestätigt: X-Test sichtbar, die Arbeitsframes sind nicht mehr langsamer als der Leerlauf.
- **Ebenen-Budget** `R.MAX_LAYERS = 500`.
  - Backen ca. 0,7–1,3 ms pro Decal.
  - Ein Voll-Bake passiert nur bei leerem Stack (clear/neu).
  - `combineTextures` läuft im Leerlauf nur alle 60 Frames.
- **Deckkraft pro Region monoton:** `car.dirtLevel[key]` steigt nur. `blendMode 2` (Add) am Layer wirkte nicht.
  Ohne Monotonie kam die Lackfarbe stellenweise wieder durch.
- **Vorschau-Alpha 0** während der Projektion, sonst blitzt es weiß.

## Ereignisse (sensor.lua → `patina_main.onSensorEvents`, alle 0,1 s)
- **scrapes:**
  - Karosserie-Knoten mit `slipVel ≥ 1.5` auf hartem Untergrund.
  - Gefiltert werden: Gummi, Radknoten, weiche Untergründe (7 FOLIAGE, 8 CLOTH, 9 WATER), Unterboden (`n.z < −0.6`),
    nach innen zeigende Normalen.
  - 0,15 s Pause pro Knoten.
  - Drei Tiefen (light/medium/deep), bis zu 8 pro Knoten, Jitter entlang der Schleifrichtung.
- **sprays (M2.1):**
  - Radspritzer auf losem Untergrund (14–20, 22), ab 3 m/s.
  - Landen seitlich hinter dem Rad (breit gezogen) oder zu 30 % hinten am Heck (nur Hinterrad).
- **dusts (M2.2):**
  - Ab 8 m/s, wenn mindestens 2 Räder auf staubigem Untergrund sind (14, 15, 16, 17, 19).
  - Großflächig auf Heck, Seiten (untere Hälfte) und Oberseite.
  - Die Seiten hat Sebastian gewünscht, das ist eine Abweichung vom Konzept.
- **contacts (M2.3):**
  - Karosserie-Knoten auf SMEAR-Untergrund (14–18, 20, 22) erzeugt einen Dreckfleck an der Kontaktstelle statt
    eines Kratzers.
  - 0,6–1,0 m groß, max. 6 pro Knoten, 150 insgesamt.
- **Diagnose:** alle 2 s `onSensorDiag`, Log „Kontakte …“ nach Grund und Untergrund-ID, die ersten 40 Meldungen.
- **Material-IDs:** 2 METAL, 4 RUBBER, 7 FOLIAGE, 8 CLOTH, 9 WATER, 13 ROCK, 14 DIRT_DUSTY, 15 DIRT, 16 SAND,
  17 SANDY_ROAD, 18 MUD, 19 GRAVEL, 20 GRASS, 22 SNOW.

## Konsolenbefehle (GE-Konsole, ohne `~`)
- `patina_main.status()`: schreibt ins Log
  - Ebenen, Warteschlange und Zähler (Schrammen, Spritzer, Staub, verworfen, ohne Treffer)
  - Spike-6-Zähler und Kontakt-Dreck
  - Bake Ø/max
  - Frametime getrennt nach „arbeitet“ und Leerlauf, dazu die CPU-Zeit von `render:update`

  Danach werden die Messwerte zurückgesetzt.
- `patina_main.testScratch("left"|"right"|"top", level 1–3, tiltGrad)`: Test-Kratzer.
- `patina_main.clear()`: Patina am aktuellen Auto löschen. Ein Fahrzeug-Reset löscht ebenfalls.
- `patina_main.synthetic(true|false)`
- Log lesen: `grep … "$USER/AppData/Local/BeamNG/BeamNG.drive/current/patina.log"`, ab der letzten Zeile
  „Patina geladen“.

## Stand der Meilensteine
- **M0 Spikes 1–6 ✅**
- **M1 Kratzer-MVP ✅** (Tag `m1-kratzer-mvp`). Getestet auf ETKI, D-Serie, Covet und dem Mod-Auto Gavril Vertex NA2.
- **M2 Dreck ✅** (Tag `m2-dreck`), alles von Sebastian bestätigt:
  - M2.1 Radspritzer
  - M2.2 Staub (ruckelfrei dank Spike 6)
  - M2.3 Kontakt-Dreck (Größe passt)
- **Nächster Schritt: M3**
  - Nässe, Trocknen, Waschen, Reset.
  - Vorher den M2-Status ins Konzeptdokument eintragen, falls noch nicht geschehen.
  - Den M3-Abschnitt im Konzeptdokument lesen.
- **Danach:** M4 Risse, M5 Einstellungen/UI, M6 Release.

## Offene Punkte
- Chrom- und helle Teile: helle Kratzer und heller Staub auf hellem Lack kaum sichtbar.
  Sebastian: „mit dem Chrom erstmal weglassen“. Auf schwarzem Lack gut sichtbar.
- Die D-Serie hat Kontaktknoten nur tief (Schweller und Stoßstangen-Ecken), deshalb Leitplanken-Kratzer nur unten.
  Möglicher Ausbau: bei Dauerkontakt größere oder tiefere Kratzer. Mit Sebastian noch nicht entschieden.
- Zierleiste der D-Serie verschmiert im UV (optional mit dem Vanilla-Decal-Editor prüfen).
- Später: Layer zusammenführen und Persistenz.
- Ungetestet:
  - Ausrichtung an Front und Heck
  - Fahrzeug-gegen-Fahrzeug
  - Spike-5-Reste (g-Formel)
