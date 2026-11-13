# Grit – BeamNG.drive-Mod für dynamischen Dreck und Kratzer (früher Patina)

Name: **Grit**, Forum-Titel „Grit – Dynamic Dirt, Scratches & Cracks for every vehicle“. Code, Pfade und Konsolenbefehle heißen seit 2026-11-06 `grit` (vorher Patina; Repo-Ordner seit 2026-11-13 `E:\BeamNGMods\Grit`, vorher „Dynamic Patina“).
Autor im Release: **Psydo** (nicht Sebastian). Lizenz: CC BY-NC-SA 4.0 (`LICENSE`). `README.md` ist die öffentliche Beschreibung (Englisch), bei neuen Features mitpflegen.

Übergabe für neue Sessions. Stand: 2026-11-13 (Release 0.6.0), letzter Commit siehe `git log -1`.
Ausführliche Belege, Messwerte und jede Testrunde: **`FINDINGS.md`** (vor Änderungen den passenden Abschnitt lesen).

## Personen und Zusammenarbeit
- Sebastian (öffentlich: Psydo), Autor. **Antworten auf Deutsch**, kurz und konkret.
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
  - `mods/unpacked/grit` ist eine **Junction** auf `E:\BeamNGMods\Grit\mod` (seit 2026-11-13). Eine
    `.lnk`-Verknüpfung funktioniert nicht, neu anlegen mit
    `New-Item -ItemType Junction -Path <User>\mods\unpacked\grit -Target E:\BeamNGMods\Grit\mod`.
    Änderungen wirken nach **Strg+L** im Spiel (Lua neu laden).
  - **`grit.log`** ist unser eigenes Log, wird sofort geschrieben (`M.debugLog`). `beamng.log` puffert minutenlang.
  - Screenshots (Strg+P) liegen unter `screenshots/2026-11/`.
- Repo `E:\BeamNGMods\Grit`:
  - `mod/scripts/grit/modScript.lua` lädt `grit_main`.
  - `mod/lua/ge/extensions/grit/main.lua`: GE-Extension, Fahrzeug-Lebenszyklus, Ereignis → Decal, Konsolenbefehle.
  - `mod/lua/ge/extensions/grit/render.lua`: Decal-Renderer pro Fahrzeug (Projektion, Synthese, Backen).
  - `mod/lua/vehicle/controller/grit/sensor.lua`: Fahrzeug-Controller, erzeugt Ereignisse aus Kollisionen und Rädern.
  - `spikes/`: alte Spike-Skripte (Spike 1–5), außerhalb des Mods, nicht im Release.
  - `branding/src/render.html` + `tools/render_branding.ps1` erzeugen Logo, Banner, Vorschaubild und Abschnittsköpfe
    nach `branding/out/` (prozedural, Seed 7, Schrift Bahnschrift). Optik beurteilt Sebastian.
  - `tools/build_release.ps1 -Version X.Y.Z` baut `build/grit_vX.Y.Z.zip` (Inhalt von `mod/` + README + LICENSE,
    schaltet `M.debugLog` und Sensor-`DIAG` aus, prüft das ZIP). Version auch in README.md eintragen.
  - `web/`: Landingpage (Next.js 16, statischer Export nach `web/out/`). `npm run dev` bzw. `npm run build`;
    `scripts/prepare-assets.mjs` erzeugt `public/img/` aus `branding/out` und `screenshots/` (nicht im Git).
    Download-Link zeigt auf den Forum-Eintrag (`app/site.ts`), Version dort mitpflegen.
  - `mod/art/grit/*.png`: Texturen, erzeugt von `tools/gen_textures.ps1` mit festen Seeds.
    Aufruf: `powershell.exe -ExecutionPolicy Bypass -File tools/gen_textures.ps1`
- Shell: Git Bash. `cd` in Bash springt manchmal zurück, deshalb absolute Pfade benutzen.
- Syntax-Check vor jedem Test: `/c/Users/sebfa/scoop/shims/luajit.exe -b <datei.lua> /dev/null` (nicht im Bash-PATH).

## Architektur (Weg A′)
- **Zwei DecalProjections pro Fahrzeug:**
  - `@GritTexture` (Farbe) und `@GritMask` (Maske).
  - Eine zusätzliche Material-Stage auf **Skin-Kopien** der lackierten Materialien.
  - Eigener Skin-Slot `grit`, Materialname `<mesh>.grit.v<ID>`.
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
  - Umschalten mit `grit_main.synthetic(false)`.
  - Bestätigt: X-Test sichtbar, die Arbeitsframes sind nicht mehr langsamer als der Leerlauf.
- **Ebenen-Budget** `R.MAX_LAYERS = 500`.
  - Backen ca. 0,7–1,3 ms pro Decal.
  - Ein Voll-Bake passiert nur bei leerem Stack (clear/neu).
  - `combineTextures` läuft im Leerlauf nur alle 60 Frames.
- **Deckkraft pro Region monoton:** `car.dirtLevel[key]` steigt nur. `blendMode 2` (Add) am Layer wirkte nicht.
  Ohne Monotonie kam die Lackfarbe stellenweise wieder durch.
- **Vorschau-Alpha 0** während der Projektion, sonst blitzt es weiß.

## Ereignisse (sensor.lua → `grit_main.onSensorEvents`, alle 0,1 s)
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
- `grit_main.status()`: schreibt ins Log
  - Ebenen, Warteschlange und Zähler (Schrammen, Spritzer, Staub, verworfen, ohne Treffer)
  - Spike-6-Zähler und Kontakt-Dreck
  - Bake Ø/max
  - Frametime getrennt nach „arbeitet“ und Leerlauf, dazu die CPU-Zeit von `render:update`

  Danach werden die Messwerte zurückgesetzt.
- `grit_main.testScratch("left"|"right"|"top", level 1–3, tiltGrad, along 0–1, variante 1–3)`: Test-Kratzer.
- `grit_main.testWash(höhe_m, stärke 0–1)`: Spike 7, Radierer bis höhe m über der Unterkante.
- `grit_main.settings()`, `grit_main.set("dirtStrength", 1.5)`, `grit_main.resetSettings()`: Einstellungen (M5.1),
  gespeichert in `<User>/settings/grit.json`.
- `grit_main.clear()`: Dreck und Kratzer am aktuellen Auto löschen. Ein Fahrzeug-Reset löscht ebenfalls.
- `grit_main.report()`: Diagnose für Bug-Meldungen nach `<User>/grit_report.txt` (auch im Release): Fahrzeug,
  Lackmaterialien mit Erkennungsgrund, Zähler. Version aus `grit/version.lua` („dev“, Release setzt sie).
- `grit_main.exportTex("tag")`: die vier Texturen als PNG nach `<User>/grit_export/tag/` (Diagnose).
- `grit_main.synthetic(true|false)`
- Log lesen: `grep … "$USER/AppData/Local/BeamNG/BeamNG.drive/current/grit.log"`, ab der letzten Zeile
  „Grit geladen“.

## Stand der Meilensteine
- **M0 Spikes 1–6 ✅**
- **M1 Kratzer-MVP ✅** (Tag `m1-kratzer-mvp`). Getestet auf ETKI, D-Serie, Covet und dem Mod-Auto Gavril Vertex NA2.
- **M2 Dreck ✅** (Tag `m2-dreck`), alles von Sebastian bestätigt:
  - M2.1 Radspritzer
  - M2.2 Staub (ruckelfrei dank Spike 6)
  - M2.3 Kontakt-Dreck (Größe passt)
- **M3 Zustand ✅** (Tag `m3-zustand`, 2026-11-07), von Sebastian bestätigt:
  - Spike 7 Radierer: große synthetische Box nur in die Maske (schwarz, Alpha = Stärke), Kratzer danach neu darüber.
  - M3.1 Waschen im Wasser: Sensor `obj:inWater` → Wasserlinie, 1 Schritt/s à 40 %, 4 Schritte pro Höhe.
  - M3.2 Nässe dunkler (ohne Glanz), Trocknen in zwei Stufen (45/90 s Spielzeit, Fahrtwind bis 4×), nur Farbe neu.
  - Staub auf Asphalt bleibt (Sebastian), nur Wasser wäscht. Reset löscht alles.
- **M4 Risse ✅** (Tag `m4-risse`, 2026-11-07), nur Kunststoff (Sebastian), Glas bleibt Vanilla:
  - Auslöser: Delle an Kunststoff-Knoten (`nodeMaterial 3`), je 3 cm Eindrückung gegen die Ausgangslage, oder
    Beam-Bruch an einem Kunststoff-Knoten. `perpendicularVel` ist dort immer 0, also unbrauchbar.
  - Haarriss bzw. ab 8 cm / Bruch Spinnennetz, mittelgrau, bleibt beim Waschen/Trocknen (`render.isDamage`).
  - Nur auf lackierten Teilen (z. B. ETK-Stoßstange), nicht auf unlackiertem Kunststoff (Covet-Stoßstange).
- **M5 Einstellungen/UI ✅:** M5.1 Einstellungen ✅ (`settings.lua`, `settings/grit.json`), M5.2 UI-App ✅
  (`mod/ui/modules/apps/Grit/`, klappbar, offenes Fenster `position: fixed` wegen `overflow: hidden` am App-Rahmen).
  M5.3: trockener Dreck nur noch in der Textur (`R:retire`) ✅; Qualitätsstufen gestrichen (Sebastian, high kaum besser,
  Bake 7 ms statt 1 ms); KI-Verkehr später. Schäden im eigenen Paar `@GritDamage`/`@GritDamageMask` unter dem Dreck
  (Stage s, Dreck s+1), Waschschritt 0.5 ms statt 120 ms ✅. Grundebene deckend schwarz gegen Datenreste. Dellen über
  0.4 m (abgerissen) und in den ersten 2 s ignoriert. Diagnose `grit_main.uvCheck()` zeigt die UV1-Belegung.
- **M6 Release:** 0.5.0 (2026-11-08), 0.6.0 (2026-11-13): Kratzer-Varianten (3 je Stufe), `scratchSensitivity`
  0.5–2, Liveries ohne Farbpalette (`<basis>.skin_<name>` über mapTo-Grundmaterial, z. B. Polizei), `report()`.
- Aufgaben/Bugs/Features in Notion (Coding / Grit: Grit Bugs, Grit Funktionsanfragen, Grit Aufgaben).

## Offene Punkte
- Chrom- und helle Teile: helle Kratzer und heller Staub auf hellem Lack kaum sichtbar.
  Sebastian: „mit dem Chrom erstmal weglassen“. Auf schwarzem Lack gut sichtbar.
- Die D-Serie hat Kontaktknoten nur tief (Schweller und Stoßstangen-Ecken), deshalb Leitplanken-Kratzer nur unten.
  Möglicher Ausbau: bei Dauerkontakt größere oder tiefere Kratzer. Mit Sebastian noch nicht entschieden.
- Zierleiste der D-Serie verschmiert im UV (optional mit dem Vanilla-Decal-Editor prüfen).
- Später: Layer zusammenführen und Persistenz. **Budget beobachten** (Sebastian 2026-11-07): nach einer Sitzung mit
  Waschen 337/500 Ebenen (jeder Waschschritt = 1 Layer, Waschen setzt Mengen-Grenzen zurück).
- Später (Sebastian 2026-11-07): **Livery-Editor (Karriere, Skin „Dynamic Textures“)** prüfen, nicht in M5.
- Später (optional, Sebastian 2026-11-07): **Regen wäscht Dreck langsam ab** (`core_environment.getPrecipitation()`).
  Erst nach M3.1–M3.3, jetzt keine Arbeit hinein.
- Covet: Stoßstangen teilen sich eine gestreckte UV1-Fläche (uvCheck, M5.3 Lauf 6) → Kratzer dort erscheinen auf beiden
  als große Fläche. Als Einschränkung in README (Sebastian 2026-11-07).
- Später: neuer Kratzer auf Dreck kratzt den Dreck weg (Radierer an der Stelle), Sebastian „merken“.
- Strg+L: selten kurz halb matt/halb metallisch bis zum Losfahren (M6 Lauf 4), Sebastian: nicht weiter verfolgen.
- Meshes mit „mechanical“ im Namen bekommen kein Grit (ETK teilt dort UVs mit der Karosserie, M5.1 Lauf 5).
- Ungetestet:
  - Ausrichtung an Front und Heck
  - Fahrzeug-gegen-Fahrzeug
  - Spike-5-Reste (g-Formel)
