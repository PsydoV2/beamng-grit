# Patina – FINDINGS (Phase 0)

Spielversion: **BeamNG.drive 0.40.5.0, Build 302427** (`Bin64/BeamNG.drive.x64.exe`).
Alle Funde gelten nur für diese Version. Spielordner: `F:\SteamLibrary\steamapps\common\BeamNG.drive` (= `$G`).
User-Ordner: `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current` (Mods unter `mods/unpacked/`).

Legende: ✅ belegt im Code · ⚠️ belegt, aber Konsequenz fürs Konzept · ❓ nur im Spiel prüfbar (Spike)

---

## 1. Dynamic Decals / Livery-Editor

### 1.1 Wo der Code liegt ✅
- Kern-API: `$G/lua/ge/extensions/editor/api/dynamicDecals.lua` (3081 Zeilen, Extension `editor_api_dynamicDecals`).
- Karriere-Livery-Editor (ohne World-Editor): `$G/lua/ge/extensions/ui/liveries.lua` + `ui/liveries/*.lua`.
- Der Karriere-Editor nutzt die Editor-API direkt; der World-Editor muss **nicht** offen sein.
  `ui/liveries.lua:6` → `M.dependencies = {"editor_api_dynamicDecals", ...}`

### 1.2 C++-Objekt `DecalProjection` ✅
`dynamicDecals.lua:1480`
```lua
decalProjection = DecalProjection("", Point2I(4096, 2048), 1, reconstructData.materialIdx or 0)
```
Danach pro Frame (`app.onUpdate`, `dynamicDecals.lua:1492-1503`):
```lua
veh:setTextureSet("@DynamicTexture", set)                 -- Textur-Set an DIESES Fahrzeug binden
decalProjection:setShape(veh:getDecalProjectionShape())
decalProjection:setWorldTransform(veh:getRefNodeMatrix())
decalProjection:setTransform(veh:getRefNodeMatrix():copy():setPosition(vec3(0,0,0)):inverse())
```
und `M.onUpdate_` (`dynamicDecals.lua:3028-3044`): `projectDynamicDecals(camM, projM)` (nur Live-Cursor-Vorschau) + `combineTextures(textureSet)`.

⚠️ Das Objekt ist **nicht** an den Spieler gebunden. Shape, Transform und Textur-Set werden von Lua gesetzt.
Damit sollte **eine `DecalProjection`-Instanz pro Fahrzeug** möglich sein (❓ Spike 1/3).
Die Editor-API selbst nutzt aber nur eine globale Instanz und `getPlayerVehicle(0)`.
→ Patina sollte die API **nicht** wiederverwenden, sondern eigene `DecalProjection`-Objekte halten.
Das vermeidet auch Konflikte mit dem Livery-Editor.

Bekannte Methoden (aus Aufrufen im Spielcode, `grep "decalProjection:"`):
`getDecalData(camM, projM)`, `bakeLayers(layers, jbeamName)`, `clearBakedTextures()`, `combineTextures(set)`,
`getTextureSet()`, `setShape`, `setWorldTransform`, `setTransform`, `setMirrorOffset`, `setTextureResolution`,
`setUvLayer/getUvLayer`, `setMaterialIdx/addMaterialIdx/removeMaterialIdx/clearMaterialIdx/getMaterialIdx`,
`getShapeMaterialNames()`, `getShapeMeshes()`, `setMeshEnable`, `enableAllMeshes`, `exportTextures(dir,name,ext)`,
`flushDynamicTextures`, `setDecalTexturePath(type, path)`, `getDecalWorldTransform/setDecalWorldTransform`,
`getDecalLocalPos/setDecalLocalPos`, `mirrorLayerData`, `getSettings/toggleSetting`.

### 1.3 Decal per Code platzieren ✅ (Mechanik) / ❓ (virtuelle Kamera)
`addDecal` (`dynamicDecals.lua:1098-1140`):
```lua
local decalData = decalProjection:getDecalData(app:getCameraM(), app:getProjM())
```
Die Platzierung ist ein **Strahl von einer Kamera** durch die Bildmitte (`cursorPosScreenUv` = 0.5/0.5, siehe
`dynamicDecals.lua:1790-1810`). Die Kamera-Matrix liegt im **Fahrzeug-Koordinatensystem**:
`veh:getRefNodeMatrix():fullInverse():mul(getCameraTransform())` (`dynamicDecals.lua:1484`).

→ Patina kann eine **virtuelle Kamera** bauen: Position = Kontaktpunkt + Normale·d, Blickrichtung = −Normale
(z. B. `quatFromDir(dir, up):getMatrix()` + `setPosition`). Damit liefert `getDecalData` einen fertigen Layer.
Danach setzt Patina Felder wie Größe, Rotation, Farbe und Textur und schiebt den Layer in den eigenen Stack. ❓ Spike 1

Layer-Felder eines Decals (`serializeLayer`, `dynamicDecals.lua:230-300`): `decalPos, decalNorm, camPosition,
camDirection, decalScale, decalRotation, decalSkew, color, decalColorTexturePath, decalAlphaTexturePath,
decalNormalTexturePath, decalRoughnessTexturePath, decalMetallicTexturePath, blendMode, alphaMaskIntensity,
metallicIntensity, roughnessIntensity, normalIntensity, viewToScreen, worldToViewToScreen, meshes, useSurfaceNormal, …`

Blend-Modi (`dynamicDecals.lua:752-758`): Clear 0, Normal 1, Add 2, Subtract 3, Multiply 4, Eraser 5.
Layer-Typen: decal 0, fill 1, textureFill 2, group 3, brushStroke 4, path 5, linkedSet 6.
Auflösungen: 512/1024/2048/4096.

### 1.4 Ändern, löschen, backen ✅
- Der Layer-Stack ist eine **reine Lua-Tabelle**. Ändern bzw. Löschen geschieht in der Tabelle, danach kommt `reprojectLayers()`.
- `reprojectLayers` (`dynamicDecals.lua:1647`) = `clearBakedTextures()` + `bakeLayers(ganzer Stack)`, also ein **voller Neu-Render**.
  ⚠️ Ein inkrementelles Backen (nur neue Layer, ohne `clear`) ist nicht belegt → ❓ Spike 3.
  Gelingt es, kostet ein neues Event nur einen Layer. Sonst wächst die Render-Zeit mit der Stack-Größe.
- `bakeLayers` gibt Status pro Layer zurück (`layerBakingStatusCode`, `dynamicDecals.lua:795`).
- Export als Skin: `exportSkin` (`dynamicDecals.lua:2078`) schreibt PNGs + Material + jbeam nach `mods/unpacked/…`.
  Für Patina nicht nötig.

### 1.5 Welche Materialien betroffen sind ⚠️ WICHTIG
`findPartMaterials` / `setVehicleMaterialJob` (`dynamicDecals.lua:1367-1445`):
1. `dynDecalMaterials` des gewählten Teils im Slot `paint_design`, sonst
2. das Material mit dem Namen des Fahrzeugs (`vehicleObj.jbeam`), sonst
3. ein Material, das auf `main` oder `body` endet.

Das sichtbare Ergebnis kommt aber nur über ein **handgebautes Preset-Material** aufs Auto:
`<material>.skin.dynamicTextures`. Beispiel `covet.zip: vehicles/covet/dynamicDecals/main.materials.json`:
- Stage 0: normale Basis-Texturen
- Stage 1: `baseColorMap: "@DynamicTextureBaseColor"`, `colorPaletteMap: "@DynamicTextureColorPalette"`,
  `metallicMap: "@DynamicTextureMetallic"`, `roughnessMap: "@DynamicTextureRoughness"`, alle mit `…UseUV: 1`
  und `opacityMap: covet_main_c.data.png`
- `activeLayers: 2`

Plus jbeam-Teil `covet_skin_dynamicTextures` (`slotType: paint_design`, `globalSkin: dynamicTextures`, `isAuxiliary: true`).

⚠️ Konsequenzen:
- Nur **41 Vanilla-Fahrzeuge** bringen so ein Preset mit: atv autobello barstow bastion bluebuck bolide burnside bx
  citybus covet dryvan dumptruck etk800 etkc etki fullsize hopper lansdale legran md_series midsize midtruck
  miramar moonhawk nine pessima pickup pigeon racetruck roamer rockbouncer sbr scintilla sunburst2 us_semi utv
  van vivace wendover wigeon. **Mod-Fahrzeuge** haben es in der Regel nicht.
- Das Preset **ersetzt den Lack** (Stage 1 = Dynamic Texture statt Lackfarbe). Der Livery-Editor malt den Lack
  deshalb als Fill-Layer in der Fahrzeugfarbe nach (`ui/liveries.lua:31-40`).
- Es belegt den Slot `paint_design`. Mit einer Lackierung zusammen geht es also nicht.
- Typisch ist ein **einziges** lackiertes Hauptmaterial (Covet: Material `covet` + seine Skins). Anbauteile mit
  eigenen Materialien liegen außerhalb.

→ Weg A „Vanilla-Preset nutzen“ würde **die Muss-Anforderungen „jedes Fahrzeug“, „jede Farbe“ und „jede
Lackierung“ verfehlen**. Siehe Abschnitt 6 (Vorschlag Weg A′).

### 1.6 Skin-System ✅
- Skins werden letztlich mit `vehicleObj:setSkin(slot .. '.' .. name)` gesetzt
  (`$G/lua/common/jbeam/sections/licenseplatesSkins.lua:58`), für `paint_design` ist der Slot leer: `".dynamicTextures"`.
- Materialnamen: `paint_design` → `<mat>.skin.<name>` (z. B. `pickup.skin.camo`). Andere Kanäle →
  `<mat>.<slot>.<name>` (z. B. `adcarrier_ad.skin_taxi_ad.alder` in `common.zip`).
- `core_vehicle_partmgmt.setSkin(skin)` (`$G/lua/ge/extensions/core/vehicle/partmgmt.lua:859`) ändert die
  Config und ruft `core_vehicles.replaceVehicle` auf, also einen **Respawn**. Der direkte Aufruf
  `vehicleObj:setSkin` tut das nicht (❓ ob live wirksam).

### 1.7 Materialien zur Laufzeit ändern/anlegen ✅
- Ändern: `scenetree.findObject(name)`, `mat:setField(prop, layer, value)`, `mat:reload()`
  (`$G/lua/ge/extensions/editor/api/material.lua:55-70`, `editor/shapeEditor.lua:259-268`).
- Anlegen: `createObject('Material')`, `mat:assignFieldsFromObject(src)`, `setField('name'/'mapTo', 0, …)`,
  `mat:registerObject(name)` (`dynamicDecals.lua:2101-2140`).
- Maximal **4 Ebenen** pro Material (`editor/materialEditor.lua:143`, `maxLayers = 4`).
- Covet: alle 17 Fahrzeugmaterialien nutzen `activeLayers: 2` → Stage 3 und 4 frei. Lack = `instanceDiffuse: true`.

### 1.8 Forum-Hinweise (nicht im Code verifizierbar)
- Verzerrung an manchen Stellen: Projektion ist planar entlang der Kamera → bei Patina klein und
  normalenausgerichtet projizieren. ❓
- „Liste nicht nachträglich erweiterbar“: Die Materialliste ist in Lua nur eine Indexliste (`addMaterialIdx`);
  das Problem liegt im fehlenden Preset-Material, nicht in der Liste (siehe 1.5).

---

## 2. Kollisionen (Vehicle-Lua)

### 2.1 Callback ✅
`$G/lua/vehicle/main.lua:491`
```lua
function onNodeCollision(id1, pos, normal, nodeVel, perpendicularVel, slipVec, slipVel, slipForce,
                         normalForce, depth, materialId1, materialId2)
```
Daten liegen in `particlefilter.particleData` (`p.id1, p.pos, p.normal, p.nodeVel, p.perpendicularVel,
p.slipVec, p.slipVel, p.slipForce, p.normalForce, p.depth, p.materialID1, p.materialID2`) und gehen an
`wheels`, `fire`, **`controller`**, `particlefilter`, `bdebug`.

⚠️ Es gibt **keinen** `extensions.hook("onNodeCollision")`. Eine Vehicle-*Extension* bekommt das Event nicht.

### 2.2 Einstieg über Controller ✅
- `controller.nodeCollision(p)` ruft die `nodeCollision`-Funktion aller geladenen Controller auf
  (`$G/lua/vehicle/controller.lua:184`, Caching `:575-648`).
- **Laden zur Laufzeit ohne jbeam:** `controller.loadControllerExternal(fileName, controllerName, data)`
  (`controller.lua:297`). Lädt `lua/vehicle/controller/<fileName>.lua`, ruft `init(data)` usw. auf und cached die Funktionen neu.
  Entladen: `controller.unloadControllerExternal(name)` (`:376`).
- → Patina lädt per `veh:queueLuaCommand('controller.loadControllerExternal("patina/sensor","patina_sensor")')`
  einen Sensor-Controller. Muster für `queueLuaCommand` + Laden: `ge/extensions/util/saveDynamicData.lua:87`.
- ❓ Nach einem Vehicle-Reset (Lua wird neu initialisiert) muss Patina den Controller neu laden.

### 2.3 Funken/Kratzer im Spiel ✅
Funken = Partikel-Regeln in `$G/lua/common/particles.json` (z. B. `METAL`/`ASPHALT`, `slipVel X>2.5`, Typ 1),
ausgewertet in `$G/lua/vehicle/particlefilter.lua:25-41` mit der Bedingung `perpendicularVel > depth * depthCoef`.
Gute Vorlage für Patinas Schwellwerte (Schrammen ab `slipVel > 2.5`).

### 2.4 Material-IDs ✅ / ❓ (Index)
Feste Liste in `particles.json:2-35` („the order here defines the groundmodel ids that are hardcoded in vlua“):
METAL 2, PLASTIC 3, RUBBER 4, GLASS 5, WOOD 6, FOLIAGE 7, CLOTH 8, WATER 9, ASPHALT 10, ASPHALT_WET 11,
SLIPPERY 12, ROCK 13, DIRT_DUSTY 14, DIRT 15, SAND 16, SANDY_ROAD 17, MUD 18, GRAVEL 19, GRASS 20, ICE 21,
SNOW 22, … RUMBLE_STRIP 29, COBBLESTONE 30, FOLIAGE_THIN 31, SPIKE_STRIP 32.
Belege für die Nummerierung: `wheels.lua:384` (32 = Spike Strip), `sounds.lua:430` (4 = Gummi),
`beamstate.lua:886` (3 = Plastik). ❓ Spike 5 loggt die Werte zur Bestätigung.

### 2.5 Node-Material pro Node ✅
`v.data.nodes[cid].nodeMaterial` (numerische ID wie oben), z. B. `$G/lua/vehicle/beamstate.lua:886`
(`== 3` → Plastik). Risse: Dort reagiert das Spiel bereits auf Plastik-Nodes an brechenden Beams.

---

## 3. Untergrund & Wasser (Vehicle-Lua)

### 3.1 Untergrund pro Rad ✅
`$G/lua/vehicle/wheels.lua:374`
```lua
wd.lastSlip, wd.lastSideSlip, wd.slipEnergy, wd.downForceRaw, wd.peakForce, wd.contactDepth,
wd.contactMaterialID1, wd.contactMaterialID2 = wd.obj:getSlipVelEnergyDownPeakForceDepthMats()
```
Lesen z. B. wie `sounds.lua:429` oder `extensions/gameplayStatisticModules/watchBurnout.lua:22`
(`wheels.wheels[i]`). Kein Kontakt = −1. Einer der beiden IDs ist das Reifenmaterial (4 = RUBBER).

### 3.2 Ground-Models ⚠️
- Definition: `gameengine.zip: art/groundmodels.json`, registriert in
  `$G/lua/ge/extensions/core/environment.lua:1608` (`submitGroundModel`).
- **Wichtig:** Vehicle-Lua sieht nicht den Ground-Model-Namen, sondern dessen **`collisiontype`**, also eine ID
  aus der Liste in 2.4 (`environment.lua:1635`: `particles.getOrAddMaterialIDByName(materials, v.collisiontype)`).
- Ground-Models (Basis-Spiel): ASPHALT ASPHALT_WET ASPHALT_OLD ASPHALT_PREPPED RUMBLE_STRIP ROCK COBBLESTONE
  METAL METAL_TREAD WOOD PLASTIC DIRT DIRT_DUSTY DIRT_DUSTY_LOOSE GRAVEL GRAVEL_WET GRASS MUD SAND ICE
  FRICTIONLESS SPIKE_STRIP SNOW SNOWBANK SLIPPERY KICKPLATE SHOCK_ABSORBER BRANCHES_STRONG LEAVES_STRONG
  LEAVES_THIN SOFT_COLLISION_GENERAL VOID (+ Aliase, Maps können eigene ergänzen).
- → Patinas Untergrund-Tabelle wird auf die **collisiontype-IDs** gemappt: SAND, SANDY_ROAD, DIRT, DIRT_DUSTY, MUD,
  GRAVEL, GRASS, SNOW, ICE, ASPHALT(_WET), ROCK, COBBLESTONE. Das ist endlich und funktioniert auch mit Mod-Maps.
- Dump aller geladenen Ground-Models: `core_environment.dumpGroundModels()` → `groundmodels_dump.json`
  (`environment.lua:1579`). ❓ Pro Map einmal ausführen.

### 3.3 Wasser ✅
`obj:inWater(nodeCid)` → bool (`fire.lua:87`, `playerController.lua:376`, `sounds.lua:434`).

---

## 4. Lebenszyklus-Hooks (GE) ✅
`$G/lua/ge/main.lua`: `onVehicleSpawned(vid, v)` :1161 · `onVehicleSwitched(oid, nid, player)` :1175 ·
`onVehicleResetted(vid)` :1187 · `onVehicleDestroyed(vid)` :1203.
`core/vehicles.lua:1794` `onVehicleReplaced(vehId)` (Teile-/Konfigwechsel = Respawn).
`core/vehicle/manager.lua:275` `onVehicleColorChanged(objID, index, paint)`.
Vehicle-seitig: `main.lua:190` `onInit`, `:329` `onVehicleLoaded`, `:454` `onReset`, `:373` `onBeamBroke(id, energy)`.

## 5. Mod laden ✅
- `$G/lua/ge/extensions/core/modmanager.lua:739`: alle `/scripts/**/modScript.lua` werden per `dofile`
  ausgeführt. Erwartetes Muster (sonst Warnung, `:733`):
  ```lua
  setExtensionUnloadMode("patina_main", "manual")
  extensions.load("patina_main")
  ```
- Extension-Name aus Pfad: `lua/ge/extensions/patina/main.lua` → `patina_main` (`NOTE_FOR_MODDERS.md`).
- Vehicle-Extension in Fahrzeug laden: `veh:queueLuaCommand("extensions.load('…')")`
  (`ge/extensions/util/saveDynamicData.lua:87`).
- Hinweise aus `NOTE_FOR_MODDERS.md`: eindeutige Namen (`*_username`), PNG-Benennung `*.color.png/*.data.png`,
  Log mit `log('I', 'patina', …)`, LuaJIT/Lua 5.1.

---

## 6. Vorschlag: Weg A′ (statt Vanilla-Preset)

Aus 1.2, 1.5 und 1.7 ergibt sich ein Weg, der die Muss-Anforderungen erfüllen kann:

1. Pro Fahrzeuginstanz eine eigene `DecalProjection` (Shape = `veh:getDecalProjectionShape()`), nur als
   **Renderer** genutzt, mit Patinas eigenem Layer-Stack.
2. Ihr Textur-Set unter eigenem Namen binden, z. B. `veh:setTextureSet("@PatinaTexture", set)`. ❓
3. Für jedes lackierte Material (und dessen aktive Skin-Variante) eine **zusätzliche Stage 3/4** einfügen, die
   `@PatinaTextureBaseColor` usw. über UV1 verwendet. Der Lack bzw. die Lackierung darunter bleibt
   unverändert. Das geht für **jedes** Fahrzeug, auch ohne Preset. ❓ Alpha-Blending der Stage
4. Kein `paint_design`-Slot, also keine Kollision mit Lackierungen oder anderen Mods.

Offene Risiken dafür (alle Spike-Fragen): Wird ein frei benannter Textur-Set-Name akzeptiert? Blendet eine
Stage mit Dynamic-Texture-Alpha korrekt über den Lack? Haben Mod-Fahrzeuge UV1? Wie stark ändern
Material-Änderungen die Darstellung anderer Instanzen desselben Modells (Material ist geteilt, Textur-Set
ist pro Fahrzeug)?

**Fallback:** Spike 1 zuerst mit dem Vanilla-Preset (`covet`), um die Projektion per virtueller Kamera
isoliert zu beweisen. Danach Spike 2 = Weg A′ auf einem Fahrzeug **ohne** Preset.

---

## 7. Spike-Ergebnisse

### Spike 1, Lauf 1 (2026-11-06, ETKI)
- `DecalProjection(...)` eigene Instanz, `bakeLayers` → `status.code = 0`, Fill 1,4 ms, Decal 2–33 ms. ✅
- `getDecalData(virtCamM, projM)` **ohne** vorheriges `projectDynamicDecals` liefert Müll
  (`decalPos = vec3(-9e999, 0, 2.8e-45)`). Kein sichtbares Decal. ⚠️
- Ursache laut Code: Der Treffer entsteht im GPU-Durchlauf `projectDynamicDecals(camM, projM)`, den der Editor
  jedes Frame ausführt (`dynamicDecals.lua:3036`). Außerdem fehlte `setEnabled(true)` (`ui/liveries.lua:85`).
- Fix: Platzierung asynchron (N Frames projizieren, dann auslesen, prüfen, `flushDynamicTextures`, backen).

### Spike 1, Lauf 2 (2026-11-06, ETKI)
- `paint()` → Auto wird grün: eigene `DecalProjection` → Textur-Set → Preset-Material → sichtbar. ✅
- Decal weiter unsichtbar. Dump zeigt `camDirection = (1,0,0)` (Kamera korrekt), aber
  `cursorPosScreenUv = (0.086, 0.981)`: Der Strahl geht durch die **Mausposition**.
- Fix: Flag `UseMousePos` (`1<<2`) per `toggleSetting` aus, `proj.cursorPosition = Point2F(0.5, 0.5)`
  (Vorbild `ui/liveries/decal.lua:604-613`).

### Spike 1, Lauf 3 (2026-11-06, ETKI) – BESTANDEN ✅
- Mit zentriertem Cursor: Treffer nach 3 Frames, Abstand zum Kamerastrahl 0,001 m. Rote „1“ sichtbar auf
  Dach, Front und Tür.
- **Achsen** im Fahrzeug-Koordinatensystem: −x = rechte Seite, −y = vorne, +z = oben.
- **Projektionstiefe** = `decalScale.y` (1 m im Test) → „front“ färbte Stoßstange UND Haube. Für Patina
  kleine Tiefe (≈ 0,05–0,1 m), sonst schmieren Kratzer über Kanten.
- Kosten: Fill-Bake ≈ 1,4 ms, erster Decal-Bake ≈ 30 ms (Textur-Laden?), danach 2–4 ms bei 2–4 Layern.

### Vorbereitung Spike 2 (Weg A′)
- Vanilla-Presets steuern die Deckkraft der Dynamic-Texture-Stage über eine **feste** `opacityMap`.
- Vanilla-Vorbild für eine Dreck-Ebene: `common.zip: vehicles/common/eu_truck/eu_tanker/main.materials.json`,
  `eu_tanker_stainless` Stage 2 mit `opacityMap: …_skin_stainless_dirt.data.png`, `opacityMapUseUV: 1`,
  `activeLayers: 3`.
- Frage für Spike 2: Lässt sich `opacityMap` auf einen Kanal des Dynamic-Texture-Sets legen
  (`@<prefix>BaseColor | Metallic | Roughness`), und wird ein eigener Prefix akzeptiert?

### Spike 2, Lauf 1 (2026-11-06, ETKI) – nichts sichtbar ⚠️
- Platzierung und Bake funktionieren (Treffer nach 3 Frames, 1 mm, Code 0), aber keine Wirkung, auch nicht bei
  `opacity("none")`.
- Ursache: `scenetree.findObject("etki")` liefert ein **Legacy-Material** `etki` mit `mapTo: "etki_old"`
  (`etki.zip: vehicles/etki/main.materials.json`). Das echte Lack-Material ist **`etki_main`** mit
  `mapTo: "etki"` und `activeLayers: 2` (Covet: `covet_main`).
- **Regel:** Namen aus `getShapeMaterialNames()` sind `mapTo`-Namen. Das Materialobjekt wird über
  `mapTo` aufgelöst (`veh:getMaterialNames()` → `scenetree.findObject(n):getField("mapTo", 0)`).
- Zusätzlich `respawn()`, falls `mat:reload()` laufende Fahrzeuge nicht aktualisiert.

### Spike 2, Lauf 2 (2026-11-06, ETKI) – SICHTBAR ✅ (schwach)
- Material über `mapTo` gefunden: `etki_main`. Zusatz-Stage mit `baseColorMap = @PatinaTextureBaseColor`,
  `opacityMap = @PatinaTextureBaseColor`, UV1 → schwache dunkle „1“ am **linken** Türgriff.
  → Eigener Textur-Set-Prefix `@PatinaTexture` wird akzeptiert, Zusatz-Stage über dem Lack funktioniert,
  kein Preset und kein Skin nötig. Weg A′ trägt grundsätzlich.
- Hypothese „schwach“: `opacityMap` liest R/Helligkeit statt Alpha (Decal-Rot = 0,35). Test mit `color()`/`intensity()`.

### Spike 2, Lauf 3 (2026-11-06, ETKI)
- `color()` und `opacity("Metallic")` liefen nicht: In der Eingabe stand ein `~` vorne
  (`unexpected symbol near '~'`). Ergebnis A = wie Lauf 2 (schwache „1“ auf dem Dach).
- Direkt nach `start()` (0 Layer gebacken) war „gefühlt die ganze rechte Seite rot“ → **frische Dynamic
  Textures enthalten Datenreste**. Fix: immer zuerst eine schwarze, transparente Fill-Ebene backen.

### Spike 2, Lauf 4 (2026-11-06, ETKI)
- Grundebene beseitigt die Datenreste ✅.
- `opacity("BaseColor")`: weiße „1“ kräftig, braune schwach → Deckkraft = **Helligkeit** der Farbe. Für Dreck ungeeignet.
- `opacity("Metallic")` + `intensity(1,1)`: braune „1“ **voll deckend** ✅ → Deckkraft über den Metallic-Kanal,
  getrennt von der Farbe. Aber das ganze Auto wurde matt schwarz: Die Grundebene (Fill, Normal) schreibt Metallic = 1.
- Nächster Test: Grundebene `clear` (blendMode 0) bzw. `zero` (metallic/roughnessIntensity 0).

### Spike 2, Lauf 5 (2026-11-06, ETKI)
- Grundebene `clear` und `zero` ändern nichts: Auto bleibt matt schwarz mit kräftiger brauner „1“.
  → `@PatinaTextureMetallic` wirkt als `opacityMap` offenbar **gar nicht** (Ebene überall voll deckend,
  wie `opacity("none")`). Metallic/Roughness sind als Masken-Quelle verworfen.
- Belegt bleibt: **Helligkeit** einer Dynamic-Texture-BaseColor wirkt als Deckkraft (schwarz = unsichtbar).
- Neuer Ansatz: **zweite DecalProjection pro Fahrzeug als Maske** (`@PatinaMask`, dieselben Layer in
  Weiß × Stärke auf schwarzem Grund). Stage: `baseColorMap = @PatinaTextureBaseColor`,
  `opacityMap = @PatinaMaskBaseColor`.

### Spike 2, Lauf 6 (2026-11-06, ETKI) – KERN BESTANDEN ✅
- Zwei Projektionen (Farbe `@PatinaTexture`, Maske `@PatinaMask`), Zusatz-Stage auf `etki_main`:
  Auto sieht normal aus, dunkelbraune „1“ vorne voll deckend; `strength(0.4)` → „1“ links halb durchsichtig,
  Lack scheint durch.
- **Weg A′ ist belegt:** Dreck in beliebiger Farbe und stufenloser Deckkraft über dem unveränderten Lack,
  ohne Preset-Material, ohne Skin, ohne `paint_design`-Slot.
- Offen für Spike 2: alle lackierten Materialien (Anbauteile/Bodykit), Mod-Fahrzeug, zweites Fahrzeug
  desselben Modells (Material ist geteilt), aktive Lackierung (Skin-Material statt `*_main`).

### Spike 2b, Lauf 1 (2026-11-06, ETKI)
- Erkennung „lackiert = instanceDiffuse“ falsch: gefunden wurden `etki_mechanicals` und `glass_invisible`,
  nicht `etki_main`. Auto nicht überzogen.
- **Regel:** Lack bei Material v1.5 = Stage mit `colorPaletteMap` (`etki_main`/`covet_main` Stage 0:
  `/vehicles/common/nullcolormaskR.color.png`; Skins: eigene `*_palette_uv1.color.png`).
  `instanceDiffuse` nur bei Legacy v1.0. Durchsichtige Materialien (`translucent`) ausschließen.

### Spike 2b, Lauf 2 (2026-11-06, ETKI) – eigenes Log `patina_spike.log` im User-Ordner
- Erkennung über `colorPaletteMap`: `character_primary` [2], `etki_mechanicals` [6], `etki_main` → Mesh `etki` [7]. ✅
- `full()` (Stage ohne Maske): **ganzes Auto braun** → Zusatz-Stage liegt auf allen Lackflächen. ✅
  Rechts weißes Rautenmuster, Heckscheibe unten rechts orange Ecken → vermutlich Datenreste in Textur-
  bereichen, die der Fill nicht überschreibt. ❓
- `coat()` (Fill-Layer) mit Maske: nur schwache Streifen. Fill-Layer kommen in der Maske nicht wie Decals an.
  Hypothese: Fill läuft über die Paletten-Logik (`colorPaletteMapId`). Test: grüner Fill bzw. `coat2()`
  (5 große Decals mit `_one.png`).

### Spike 2b, Lauf 3 (2026-11-06, ETKI)
- `coat2(0.7)`: alle 5 großen Decals (`_one.png`, 6 m, Tiefe 4 m) treffen, Bake 1–9 ms, Code 0 – aber
  **nichts sichtbar** (nur Flackern der Live-Vorschau).
- `clear()` → `coat(1,0,1,0)` → `full()`: Inneres braun, Ränder grün. Das Braun stammt vermutlich noch von
  den coat2-Decals, obwohl mit 0 Layern neu gebacken wurde → `clearBakedTextures` löscht evtl. nicht alles,
  oder Fill schreibt nur in leere Bereiche. ❓
- `colorPaletteMapId = 0` = Layer rendert seine eigene Farbe (`ui/liveries/paint.lua:8-10`). Paletten-These verworfen.
- Nächster Schritt: Texturen per `exportTextures` als PNG ausgeben und direkt ansehen.

### Spike 2b, Lauf 4 (2026-11-06, ETKI, Lack 0.24/0.48/0.48) – Texturen per `exportTextures` geprüft
- Export `a` (nur Basis-Fill): RGBA 0,0,0,0 überall. `b` (ein „1“-Decal): nur die 1 in der Maske. ✅
- Export `c` (coat2 0.7): **Maske deckt alle UV-Inseln des Lacks gleichmäßig** (116/255), Farbe (18,7,2). ✅ Abdeckung.
- **Bake wandelt Layer-Farben sRGB → linear:** 0.7 → 116 (= 0.7^2.2), Dreckfarbe 0.3/0.2/0.1 → 18/7/2.
  Folge: Maske deckt nur ~45 % statt 70 %, Dreck fast schwarz → auf dem Auto kaum sichtbar.
  Abhilfe: Werte vor dem Bake mit ^(1/2.2) kodieren (`M.gammaFix`).

### Spike 2b, Lauf 5 (2026-11-06, ETKI) – mit Gamma-Ausgleich
- Gegencheck `coat2(1, 1,0,0)`: **ganzes Auto knallrot** (Sebastian). ✅
- `coat2(0.6)`: Export Maske 153/255 = 0.6, Farbe 76/51/25 = 0.3/0.2/0.1 → Werte stimmen jetzt. ✅
- Optik laut Sebastian „eher grau-oliv, Spiegel braun“. Screenshots: `screenshots/2026-11/screenshot_2026-11-06_15-16-45.png`
  (sauber) und `…15-17-21.png` (Dreck). Gleichmäßige Fläche auf allen Lackteilen.
  Grau-oliv ist die rechnerische Mischung 60 % Braun + 40 % Mint. Glanz wirkt weg (Stage-Roughness 1).
  Spiegel brauner als der Rest: Ursache noch offen (anderes Material/UV?). ❓
- **Damit deckt Weg A′ alle lackierten Teile des ETKI flächig ab.** Realistischer Look (Texturen, Verteilung, Glanz)
  ist Gestaltungsarbeit für M1+, nicht Teil des Spikes.

### Spike 2b, Lauf 6 (2026-11-06) – zweites Auto, Mod-Fahrzeug, Lackierung
- **K, zweiter ETKI (gleiches Modell):** alter behält Dreck ✅, **neuer gelb** mit Lackresten ❌.
  Ursache: Zusatz-Stage sitzt im geteilten Material, der neue hat kein Texture-Set an `@Patina*` gebunden → Datenreste.
  Fix (ungetestet): jedes andere Fahrzeug bekommt pro Frame über `veh:setTextureSet` ein leeres schwarzes Set
  (`getAllVehicles()`, `ge/ge_utils.lua:503`). Später: jedes Fahrzeug eigenes Set.
- **L, Mod-Fahrzeug `gavril_vertex`:** 2 lackierte Materialien erkannt, `coat2(1,1,0,0)` → ganzes Auto rot. ✅
- **M, Lackierung (Legran mit Renn-Lackierung):** 4 lackierte Materialien, Lackierung unter `coat2(0.6)` erkennbar. ✅
  Screenshot `screenshots/2026-11/screenshot_2026-11-06_15-26-14.png`.

### Spike 2b, Lauf 7 (2026-11-06) – K′
- Gemeinsames leeres Set (gebacken mit der Form des Patina-Autos) an alle anderen gebunden → zweiter ETKI
  **deckend lavendelblau** statt Seafoam Green (Screenshot `…15-32-16.png`). Lavendel ≈ (0.5,0.5,1) =
  typischer Platzhalter → das Set wirkt am anderen Fahrzeug nicht. Texture-Sets hängen offenbar an der
  Form-Instanz der Projektion. Neuer Versuch: eigene leere Projektion pro Fahrzeug mit dessen Form.

### Spike 2b, Lauf 8 (2026-11-06) – K″
- Eigene leere Projektion pro Fahrzeug: **bereits vorhandener zweiter ETKI behält Originalfarbe** ✅,
  Patina-Auto verdreckt ✅. **Danach neu gespawnter ETKI wieder lavendelblau** ❌, obwohl seine Projektion
  erzeugt wurde (Log 15:37:01, code=0). Vermutung: im Spawn-Frame ist die Form noch nicht fertig.
  Neuer Versuch: Projektion erst nach 30 Frames anlegen.

### Spike 2b, Lauf 9 (2026-11-06)
- Leere Projektion des neuen ETKI mehrfach gebacken (Frame 1/60/180/600, je 55 Form-Materialien, code 0).
  `exportOthers`: Textur komplett 0 = korrekt. Trotzdem: Dach/Heck/Kotflügel lavendelblau, Seiten grün mit
  feinen UV-Linien (Screenshot `…15-43-54.png`). → **Das Auto liest die gebundene Textur nicht.**
- Vermutung: Fahrzeuge, die NACH dem Einbau der Stage spawnen, lösen `@Patina*` beim Spawn zu einem
  Platzhalter auf und behalten ihn. Vorhandene Fahrzeuge wurden durch `mat:reload()` neu aufgelöst.
  Test: nach dem Binden `mat:reload()`.

### Spike 2b, Lauf 10 (2026-11-06)
- Mit `mat:reload()` nach dem Binden: **neu gespawnter ETKI in Originalfarbe** ✅ (Screenshot `…15-47-09.png`).
  Bestätigt: Fahrzeuge lösen `@Patina*` beim Spawn bzw. beim Material-Reload auf, nicht pro Frame.
  Offen: bleibt das Patina-Auto nach dem Reload verdreckt? (am Bildrand wirkt es grün) ❓

### Spike 2b, Lauf 11 (2026-11-06)
- Nach dem Reload für den neuen ETKI waren **alle** Autos auf Originallack, auch das Patina-Auto. ❌
- Zwei Möglichkeiten: (a) Bindung pro Fahrzeug, Reload löst mit dem Stand im Moment auf;
  (b) Bindung praktisch pro Material, das zuletzt gebundene Set gewinnt.
  Test: direkt vor dem Reload zuerst andere leer, dann Patina-Auto mit echten Sets binden.
  (a) → Patina-Auto dreckig, andere sauber. (b) → alle dreckig.

### Spike 2b, Lauf 12 (2026-11-06) → Kurswechsel zu Spike 2c
- Patina-Sets vor Reload binden: nach `start()` weiße/graue Flecken auf **beiden** Autos, nach `coat2` nur das
  aktive dreckig, nach neuem Spawn alle wieder Originallack. ❌ Bindung des geteilten Materials ist nicht
  beherrschbar (wird bei Spawn/Reload zu unklaren Zeitpunkten aufgelöst).
- Vanilla bindet Dynamic Textures nur ans Spielerfahrzeug (`editor/api/dynamicDecals.lua:1489-1500`),
  mehrere Fahrzeuge gleichzeitig sind dort kein Fall.
- **Spike 2c:** geteiltes Material NICHT ändern. Pro Patina-Fahrzeug Material-**Kopie** mit Zusatz-Stage,
  nur dessen Meshes umschalten: `veh:getMeshesContainingMaterial(mat)`, `veh:getSwitchableMaterial(org, off, mesh)`,
  `veh:switchMaterial(msc, name)`, `veh:resetMaterials(msc)` – wie Lichter/Glowmap
  (`common/jbeam/materials.lua:67-78`, `vehicle/material.lua:19-28`).

### Spike 2c, Lauf 1 (2026-11-06, ETKI)
- `switchMaterial` funktioniert: 8 + 35 + 22 Meshes auf Kopien umgeschaltet, **zweiter ETKI bleibt sauber** ✅,
  Projektion findet die Kopien in der Form (`patina_<id>_*` [84–86]).
- Aber: Patina-Auto **komplett chrom** statt verdreckt ❌ → Kopie unvollständig. Kopiert war mit
  `assignFieldsFromObject` (gibt es, `editor/api/dynamicDecals.lua:2105`) + `c.mapTo`.
- Lauf 2: kopieren wie der Material-Editor (`editor/api/material.lua:265-279`, jedes Feld × 4 Stages +
  dynamische Felder; `name`/`mapTo` per `setField`), Kopie gegen Original vergleichen und loggen.

### Spike 2c, Lauf 2 (2026-11-06)
- Kopie wie Material-Editor: **keine einzige Feldabweichung** zum Original, trotzdem chrom sofort nach `start()`. ❌
  → Ursache liegt im Umschalten auf ein zur Laufzeit erzeugtes Material, nicht in den Feldern.
- Lauf 3: Diagnose-Schalter `noStage` (Kopie ohne Stage) und `switchToOrig` (auf Originalnamen schalten).

### Spike 2c, Lauf 3 (2026-11-06)
- P1 `noStage` (Kopie ohne Stage): chrom, außerhalb der Konsole schwarz mit Chrom-Flackern. ❌
- P2 `switchToOrig` (Umschalten auf Originalnamen): normal. ✅ → `switchMaterial` selbst ok.
- P3 `stop()` → `resetMaterials`: Auto wieder normal. ✅
- → Ein zur Laufzeit (nach dem Spawn) erzeugtes Material wird vom Fahrzeug nicht korrekt genutzt.
  Glowmap-Zielmaterialien existieren immer schon beim Spawn. Lauf 4: Kopien anlegen, Fahrzeug neu laden
  (Strg+R), dann umschalten (`prepClones`, `keepClones`). Zusätzlich `setFilename` vom Original.
