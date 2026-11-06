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

### Spike 2c, Lauf 4 (2026-11-06)
- Kopien vor Strg+R angelegt und wiederverwendet → trotzdem chrom/schwarz ❌; zweiter ETKI sauber ✅.
  These „Material muss vor dem Spawn existieren“ verworfen.
- Neue These: Schwarz + Chrom = Lack ohne Fahrzeugfarbe (Basisfarbe 0, Klarlack/Metallic aktiv). Die
  Fahrzeugfarbe hängt offenbar an den ursprünglichen Material-Instanzen. Lauf 5: nach dem Umschalten
  Lack neu setzen über `core_vehicle_manager.liveUpdateVehicleColors` (`core/vehicle/manager.lua:256-277`).

### Spike 2c, Lauf 5 (2026-11-06)
- Lack neu setzen (`liveUpdateVehicleColors`) und Farbwahl im Lackmenü → weiterhin chrom (vor Kameradrehung),
  dann schwarz. ❌ → per `switchMaterial` umgeschaltete Materialien bekommen keine Fahrzeugfarbe.
  (Vanilla nutzt `switchMaterial` nur für Glowmaps, `common/jbeam/materials.lua:57-78`, nie für Lack.)
- Gefunden: `vehicleObj:setSkin(slot .. "." .. skinName)` (`common/jbeam/sections/licenseplatesSkins.lua:56-58`,
  Slot `''` bei `paint_design`). Skin-Materialien heißen `<mapTo>.skin.<name>`
  (`editor/api/dynamicDecals.lua:2099,2108`; Vorlage `.skin.dynamicTextures` mit `instanceDiffuse`,
  `editor/dynamicDecals/debugSection.lua:136-150`) und werden vom Spiel lackiert.
- Bindung der Texturen ist ohnehin pro Fahrzeug: `veh:setTextureSet(prefix, set)` (`editor/api/dynamicDecals.lua:1489-1500`).
- Lauf 6: `M.skinMode`: Kopie als `<mapTo>.skin.patina<ID>` registrieren, dann `veh:setSkin(".patina<ID>")`
  zur Laufzeit. Skin pro Fahrzeug → echte Trennung gleicher Modelle. `stop()` → `setSkin(".")`.
  Offen: wirkt `setSkin` ohne Neuspawn? Verträgt es sich mit Lackierungen (Liveries)?

### Spike 2c, Lauf 6 (2026-11-06)
- `veh:setSkin(".patina<ID>")` zur Laufzeit: keine sichtbare Wirkung, beide Autos sauber. Log: die Form behält
  ihre Original-Materialien (`character_primary[2], etki_mechanicals[6], etki[7]`) → `setSkin` wirkt
  offenbar nur beim Spawn (wird ja auch nur in `licenseplatesSkins.process` während des Spawns aufgerufen).
- Lauf 7: `M.keepSkin`: Skin + Materialien über Strg+R behalten, dann `start()` erneut → greift der Skin beim Neuladen?

### Spike 2c, Lauf 7 (2026-11-06) ✅ Trennung pro Fahrzeug gelöst
- Skin `patina<ID>` + Materialien `<mapTo>.skin.patina<ID>` angelegt, `setSkin`, dann Strg+R:
  Fahrzeug behält ID (48480) und nutzt nach dem Neuladen die Skin-Materialien
  (`getMaterialNames` → `etki.skin.patina48480` usw., Form-Indizes unverändert [2],[6],[7]).
- Zwischen Neuladen und `start()`: gelbe Platzhalter-Textur mit „NO TEXTURE“ (Textur-Set `@Patina*` noch
  nicht gebunden) → beim Spawn sofort binden (`veh:setTextureSet`, leeres Set) nötig.
- Nach `start()` + `coat2(0.6)`: oliv-grau verdreckt ✅, Lack korrekt ✅; zweiter ETKI sauber ✅
  (Screenshots `screenshots/2026-11/screenshot_2026-11-06_19-35-*.png`).
- Kosten: `setSkin` wirkt nur beim Spawn → einmaliges Neuladen des Fahrzeugs beim Aktivieren.
- Bug im Spike: zweites `start()` legt eine weitere Stage obendrauf (Stage 2→3), weil die Skin-Kopie
  schon eine Patina-Stage hat → vorhandene Patina-Stage erkennen und wiederverwenden.
- Offen: Verhältnis zu Lackierungs-Skins (Slot `paint_design` wird durch unseren Skin ersetzt).

### Entscheidungen (2026-11-06, Sebastian)
- Einmaliges Neuladen des Fahrzeugs beim Aktivieren von Patina ist ok (am besten beim Spawnen).
- Lackierungsmuster (Liveries): Patina kopiert die Materialien des gewählten Skins → in Spike 4 einplanen.

### Spike 2d (2026-11-06): Skin-Ansatz automatisch
- Spawn-Ablauf geprüft: `loadBundle` ruft `jbeamLicensePlatesSkins.process` (setSkin) vor `jbeamMeshs.process`
  (`common/jbeam/loader.lua:387,411`) → Skin muss vor dem Spawn feststehen. Hooks `onJbeamLoadingPhase1/2`
  (`loader.lua:240,271`) laufen davor; `onVehicleSpawned` danach (`ge/main.lua:1161`).
- Neuspawn eines beliebigen Fahrzeugs: `veh:respawn(serialize(config))` (`core/vehicle/partmgmt.lua:935`).
- `spike2d.lua`: `start()` legt Skin-Materialien an, `setSkin`, `respawn`; `onVehicleSpawned` → Ziele neu
  finden, Texturen sofort binden, backen. Vorhandene Patina-Stage wird erkannt (kein Doppel-Stage).
  `stop()` → `setSkin(".")`, Neuspawn, danach Skin-Materialien löschen.

### Spike 2d, Lauf 1 (2026-11-06) ✅ Spike 2 abgeschlossen
- `start()`: Skin-Materialien angelegt, Neuspawn **665 ms** (gemessen, `hptimer` von `respawn` bis
  `onVehicleSpawned`), danach 3/3 Lackmaterialien auf Skin `patina77525`, Patina-Stage korrekt erkannt.
- Kein gelbes Platzhalter-Overlay ✅ (Binden in `onVehicleSpawned` reicht).
- `coat2(0.6)` → oliv-grau verdreckt ✅; zweiter ETKI sauber ✅; Bake 1–8 ms für 1–5 Layer.
- `stop()` → Neuspawn 346 ms, Fahrzeug normal ✅, Skin-Materialien gelöscht.
- Kleinigkeit: ein Auto, das schon Skin `patina<ID>` trägt (Rest aus 2c), bleibt bei `start()` in Phase
  „prepare“ hängen (Log 19:54–19:55) → im Mod: vorhandenen Patina-Skin erkennen, `start()` absichern (pcall).
- `onVehicleDestroyed` feuert beim eigenen Neuspawn nicht (kein Log-Eintrag) – Schutz trotzdem drin lassen.

### Spike 3 (2026-11-06): Lasttest – Aufbau
- Basis: Spike 2d (Skin pro Fahrzeug). `load(n, s, mode)`: 3 s Grundlinie, dann n zufällige Decals (Seite +
  Versatz, Größe 0.2–0.6, zwei Spiel-Texturen aus `/art/dynamicDecals/textures/`) gleichmäßig über s Sekunden,
  3 s Nachlauf. Gemessen: Frametime (`onUpdate(dtReal, …)`, `ge/main.lua:1006`), Bake pro Decal (`hptimer`),
  Frames pro Decal (Projektion + `getDecalData`), CPU von onUpdate und `combineTextures`.
- `inc`: `bakeLayers({neu})` ohne `clearBakedTextures` – so fügt der Editor Decals hinzu
  (`editor/api/dynamicDecals.lua:1091-1095` addDecal_Redo). `full`: clear + alle Layer
  (`reprojectLayers`, `dynamicDecals.lua:1647-1651`).

### Spike 3, Lauf 1 (2026-11-06)
- **inc** (200 Decals / 20 s, ETKI, ~90 fps): alle 200 getroffen, Laufzeit 20.0 s.
  Frametime Grundlinie Ø 11.04 / p99 11.16 ms → unter Last Ø 11.06 / p99 11.32 / max 11.49 ms ✅ (kein Ruckeln).
  Bake pro Decal Ø 0.82 / p99 1.08 / max 2.05 ms. Projektion + Auslesen konstant 3 Frames pro Decal.
  Patina-onUpdate CPU Ø 1.32 / p95 3.26 ms, einmal 31.7 ms (Ausreißer, in der Frametime nicht sichtbar).
  `combineTextures` Ø 0.05 ms.
- **full** neu backen mit 200 Layern: **2811 ms** bzw. 1252 ms für einen Bake (≈ 6–14 ms pro Layer).
  Lastlauf `full` → 1–3 fps, unbrauchbar ❌. → Laufzeit nur inkrementell; Voll-Bake nur einmalig
  (Laden/Spawn) und Layerzahl begrenzen bzw. zusammenfassen (Konsolidierung).
- Strg+R nach `veh:respawn`-Skin: Skin verloren (`attach: 0/3 … kein Skin!`). In 2c Lauf 7 blieb er über
  Strg+R erhalten → im Mod Skin bei jedem Spawn selbst setzen (Hook vor `jbeamMeshs.process`) – offen.
- Screenshot A (nach inc): `screenshots/2026-11/screenshot_2026-11-06_20-01-43.png`. Vergleich inc ↔ full steht aus.

### Spike 3, Lauf 2 (2026-11-06) ✅ Spike 3 abgeschlossen
- 50 Decals / 10 s inc: Frametime unverändert (Ø 11.03 → 11.02 ms, max 11.58), Bake Ø 0.68 ms pro Decal.
- Danach `rebakeFull()` (50 Layer): 143.7 ms. Bild inc ↔ full laut Sebastian **gleich** ✅
  (`screenshots/2026-11/screenshot_2026-11-06_20-06-19.png` vs. `…20-06-42.png`).
- Voll-Bake wächst überlinear: 50 Layer 144 ms (2.9 ms/Layer), 200 Layer 1252–2811 ms (6–14 ms/Layer).
- Wiederkehrender Ausreißer Patina-onUpdate ~31 ms (einmal pro Lauf, beide Läufe) – vermutlich erstes
  Laden der Decal-Textur; im Mod beobachten.
- Fazit für den Mod: zur Laufzeit nur inkrementell backen; Layerzahl begrenzen; Voll-Bake nur beim
  Spawn/Laden, bei vielen Layern auf mehrere Frames verteilen oder vorher zusammenfassen.

### Spike 4 (2026-11-06): Lackierungsmuster – Aufbau
- Testfahrzeug (Sebastian): ETK I-Series Rally Gravel = `etki/rally_am_gravel.pc`, `paint_design: etki_skin_rotopad`
  → Material `etki.skin.rotopad` (`etki/skin.materials.json`, 2 Stages, Muster in Stage 1 mit eigener Palette).
  Patina-Stage käme also auf Stage 2 ✅ (Platz bis 4).
- setSkin gilt pro Slot (`licenseplatesSkins.lua:56-58`; Material `<mat>.<slot>.<name>`, bei paint_design
  `<mat>.skin.<name>`, z. B. `etki_intcarpet.skin_interior.cream`). Spike 3: Strg+R verlor unseren Skin, weil
  der Spawn den paint_design-Slot neu setzt.
- Verworfen: `onJbeamLoadingPhase2` + `part.skinName` patchen – das Ergebnis wird pro Config gecacht
  (`loader.lua:470-485`, `cache[spawnHash]`) → Hook läuft nicht bei jedem Spawn, Änderung würde andere
  Fahrzeuge gleicher Config treffen.
- `spike4.lua`: eigener Slot `patina` → `veh:setSkin("patina.v<ID>")`, Materialien `<mapTo>.patina.v<ID>`
  als Kopie des aktuell genutzten Materials (also auch des Lackierungsmusters). Offen: Vorrang bei zwei Slots.

### Spike 4, Lauf 1 (2026-11-06)
- Fahrzeug trug tatsächlich Muster **dreid** (`etki.skin.dreid`, `etki_modparts.skin.dreid`), 6 Lackmaterialien
  inkl. `generic_rallyparts`, `rollcage_01a`.
- Eigener Slot `patina` hat **Vorrang** vor paint_design: nach Neuspawn 6/6 auf `<mapTo>.patina.v<ID>` ✅.
  Verdreckt mit erkennbarem Muster ✅; zweiter Rally Gravel sauber ✅; `stop()` → normal mit Muster ✅.
- Strg+R → wieder sauber, `attach: 0/6` ❌: Strg+R setzt alle Skins zurück, auch den eigenen Slot
  (anders als `veh:respawn`). Lauf 2: in `onSpawnCCallback` (feuert vor Teilen/Meshes,
  `core/vehicle/manager.lua:111-140`) den Skin erneut setzen.

### Spike 4, Lauf 2 (2026-11-06) ✅ Spike 4 abgeschlossen
- Strg+R: `onSpawnCCallback` setzt `patina.v<ID>` erneut → nach dem Spawn 6/6 auf Skin, 5 Layer neu gebacken
  (4.3 ms), Dreck bleibt ✅ (Sebastian bestätigt).
- Ergebnis Skin-Weg komplett: eigener Slot `patina` (Vorrang vor paint_design), Kopie des aktuell genutzten
  Materials (Lackierungsmuster bleibt sichtbar), Skin bei jedem Spawn in `onSpawnCCallback` setzen,
  einmaliger `veh:respawn` beim Aktivieren, Texturen in `onVehicleSpawned` binden.

### Spike 5 (2026-11-06): Ereignis-Logger – Aufbau
- Fahrzeug-Controller zur Laufzeit: `controller.loadControllerExternal(fileName, name, data)`
  (`vehicle/controller.lua:297-374`), Datei `lua/vehicle/controller/<fileName>.lua` → bei uns
  `mod/lua/vehicle/controller/patinaSpike/eventLogger.lua`; `unloadControllerExternal` (`:376`).
  Controller-Hooks: `init`, `reset`, `updateGFX`, `nodeCollision` (`controllerTemplate.lua`, `controller.lua:186,584,605`).
- `nodeCollision(p)`: jeder Knotenkontakt mit `id1, pos, normal, nodeVel, perpendicularVel, slipVec, slipVel,
  slipForce, normalForce, depth, materialID1, materialID2` (`vehicle/main.lua:491-501`) → Quelle für Spritzer
  (Material + Rutschen) und Stöße (Senkrechtgeschwindigkeit, Knoten).
- Räder: `wheels.wheels[i]` mit `contactMaterialID1/2` (4 = RUBBER → anderes nehmen, `sounds.lua:429-432`),
  `lastSlip`, `wheelSpeed`, `contactDepth`. Wasser: `obj:inWater(cid)` (`playerController.lua:376`).
  Schaden `beamstate.damage` (`ai.lua:4379`). g: `sensors.gx/gy/gz` (`sensors.lua:7-29`).
- Material-IDs (`lua/common/particles.json`, Reihenfolge = ID): 2 METAL … 9 WATER, 10 ASPHALT, 11 ASPHALT_WET,
  13 ROCK, 14 DIRT_DUSTY, 15 DIRT, 16 SAND, 17 SANDY_ROAD, 18 MUD, 19 GRAVEL, 20 GRASS, 21 ICE, 22 SNOW, 30 COBBLESTONE.
  Namen im Fahrzeug-Lua über `particles.getMaterialsParticlesTable()` (`particles` global, `vehicle/main.lua:239`).
- An GE: `obj:queueGameEngineLua("patinaSpike_spike5.onVehicleEvents(id, serialize(msg))")` alle 0.2 s
  (Muster `bdebugImpl.lua:2565`). CPU mit `HighPerfTimer()` (`beamstate.lua:1542`).

### Spike 5, Lauf 1 (2026-11-06, Testmap v2, Rally Gravel) ✅ Spike 5 abgeschlossen
- Controller lädt per `loadControllerExternal`, Meldungen kommen 5×/s in GE an (898 Meldungen, 15344 Frames). Kein Ruckeln.
- CPU im Fahrzeug-Lua: nodeCollision Ø 0.004 ms/Frame, updateGFX Ø 0.008 ms/Frame (inkl. Timer-Overhead) → vernachlässigbar.
- Material-IDs stimmen (ID 10 = ASPHALT, 15 = DIRT); gesehen: ASPHALT, DIRT, SAND (16), MUD (18).
  Kontaktpaar = `materialID1` Untergrund / `materialID2` Knotenmaterial (4 RUBBER = Reifen, 3 PLASTIC, 2 METAL = Karosserie).
- Wasser: Anteil Prüfknoten im Wasser bis 0.75; dabei keine Bodenkontakte gemeldet ✅.
- Crash: Schaden pro Fenster bis 14081, g bis 19.3, Karosserie-Kontakte (10/3, 10/2) ✅.
- Korrekturen für den Mod:
  - Stöße nur von Nicht-Reifen-Knoten werten (`materialID2 ~= 4`): 2958 von 3070 „Stößen“ waren Reifenknoten
    beim normalen Fahren (perp 2–8 m/s auf Schotter).
  - g-Formel falsch (Ruhe = 2.0 statt 1.0): `sensors.gz` enthält die Schwerkraft schon mit anderem Vorzeichen → Betrag ohne Abzug.
  - Fahrzeug-Fahrzeug-Stöße kommen vermutlich nicht über `nodeCollision` → über Schadenszuwachs (`beamstate.damage`) + Knoten mit Verformung (`beamDeformed`-Hook) lösen; prüfen in M1+.

## M1 Kratzer-MVP

### M1.1 (2026-11-06): Mod-Gerüst + Schrammen-Pipeline (Platzhalter-Strich)
- Start: `scripts/patina/modScript.lua` → `setExtensionUnloadMode("patina_main","manual")` + `extensions.load`
  (Muster `core/modmanager.lua:719-746`).
- `lua/ge/extensions/patina/main.lua` (Extension `patina_main`): Spielerfahrzeug beim Spawn/Wechsel aktivieren
  (Skin-Weg aus Spike 4), Sensor laden, Ereignisse → `render.lua` (Modul pro Fahrzeug, kein globaler Zustand).
  Hooks: `onVehicleSpawned`, `onSpawnCCallback`, `onVehicleSwitched(old,new)`, `onVehicleResetted` (`ge/main.lua:1187`),
  `onVehicleDestroyed`. Reset/Strg+R → Patina leer (Konzept).
- `lua/vehicle/controller/patina/sensor.lua`: Schramme = Knoten mit `materialID2 ~= 4` und `slipVel > 1.5 m/s`,
  pro Knoten alle 60 ms, gesendet alle 0.1 s (max. 12). Ort = Ausgangsposition des Knotens `v.data.nodes[cid].pos`
  (Fahrzeugraum, `bdebugImpl.lua:648`); Normale/Schleifrichtung von Welt in Fahrzeugraum über
  `obj:getDirectionVector/Up` (`ai.lua:41`), Achsen +x links, −y vorne, +z oben (Spike 1).
- Decal: virtuelle Kamera auf `pos + n·d`, Blick `−n`, „oben“ = Schleifrichtung → gestreckter Strich
  (`decalScale = (Breite, Tiefe, Länge)`), Platzhalter-Textur `_one.png`, Farbe hellgrau. Budget 100 Ebenen.

### M1.1, Lauf 1 (2026-11-06)
- Aktivierung klappt (6/6 Materialien, Neuspawn 1418 ms beim ersten Mal). 300 Schrammen erkannt, 100 Decals
  gesetzt (Budget voll, 280 verworfen) – aber **nichts sichtbar** ❌. Vermutung: `p.normal` ist die Normale der
  getroffenen Fläche und zeigt ins Auto → Kamera saß innen. Fix: Normale am Auto = −p.normal. Knoten-Cooldown 0.15 s.
- **Muster-Übertrag** ❌: Neues Fahrzeug über den Fahrzeug-Wähler behält die Objekt-ID (47478) → alte Kopien
  samt Muster + Skin wurden übernommen. Fix: in `onSpawnCCallback` nur beim eigenen Neuspawn den Skin setzen,
  sonst Skin-Slot leeren und nach dem Spawn frisch vorbereiten (kostet bei Strg+R einen zweiten Spawn).
  Alte Kopien derselben ID werden gelöscht.
- Diagnose: erste 15 Schrammen + Decal-Treffer ins Log, `patina_main.testScratch("left")`.

### M1.1, Lauf 2 (2026-11-06)
- Muster-Übertrag behoben ✅ (zweiter ETKI ohne Muster sieht richtig aus).
- Nach Strg+L: Aktivierung in `onExtensionLoaded` scheitert, `core_vehicle_manager.getVehicleData` noch leer
  („Neuspawn nicht möglich“), danach kein neuer Versuch. Ersetzen über den Fahrzeug-Wähler behält die ID
  (`core/vehicles.lua:1780-1794`, `onVehicleReplaced`) und löste keine Aktivierung aus.
- Fix: `onUpdate` prüft das Spielerfahrzeug und aktiviert es (Wiederholung alle 30 Frames). Trägt es einen
  Patina-Skin aus unbekanntem Zustand → Skin aus, Neuspawn, dann frisch kopieren.

### M1.1, Lauf 3 (2026-11-06)
- Aktivierung nach Strg+L und beim Ersetzen klappt ✅, Muster stimmt ✅, `testScratch("left")` sichtbar ✅
  (angefragt x=1.28, Treffer x=1.148 = Oberfläche).
- Schrammen rechts: Striche nur vorne, etwas auf Motorhaube und links ❌. Log: Knoten rechts bei x≈−0.83,
  Oberfläche rechts aber bei x≈−0.51 (Spike 2: decal(right) x=−0.5077, links +1.148) → Decal-Raum ist
  relativ zum **Referenzknoten** (Versatz ≈ 0.32 m in x), nicht jbeam-Ursprung. Viele Strahlen verfehlten das
  Auto und lieferten Welt-Koordinaten (z. B. (12711, 1490, −30)) → Striche an falschen Stellen.
- Fix: Sensor zieht Ausgangsposition des Referenzknotens ab (`v.data.refNodes[0].ref`, wie `bdebugImpl.lua:648`);
  Render verwirft Treffer > 0.6 m von der Anfrage sofort.

### M1.1, Lauf 4 (2026-11-06)
- Nach Strg+L im Auto: „alter Skin → aus, Neuspawn“ → `prepare` im `onVehicleSpawned` ruft `veh:respawn` →
  dieser Neuspawn kam erst 37 s später beim Ersetzen an (halbes Auto weiß). → Nie im Spawn-Hook neu spawnen,
  sondern 2 Frames später in `onUpdate` (Phase `prepareLater`).
- Nach zweitem Ersetzen: Schrammen an den richtigen Stellen ✅ (Treffer ≤ 0.17 m von der Anfrage, rechts vorne).
  Ferne Treffer (Welt-Koordinaten, Gegenseite x=+0.57) werden verworfen ✅.
- ~1 % Striche auf der Gegenseite: Decal-Spiegeln (`mirrored`, `editor/api/dynamicDecals.lua:520,929,2484`,
  Spiegelebene x = Mitte + Offset) → Layer `mirrored = false`, Projektion `mirrored = false`.

### M1.1, Lauf 5 (2026-11-06) ✅ Pipeline steht
- Strg+L im Auto → sofort Schrammen ✅; Ersetzen → normal ✅, Schrammen ✅. Neuspawn 420–460 ms.
- Treffer meist ≤ 0.1 m neben der Anfrage. Rest auf der „Gegenseite“: Anfragen bei x=−0.495, y=−1.1…−1.25,
  z=0.13–0.3 = Felge vorne rechts (Metall, am Reifenfilter vorbei) → Treffer ~0.4 m innen. Fix: alle Rad-Knoten
  (`wheels.wheels[i].nodes/.treadNodes`, `vehicle/wheels.lua:183,200,1091`) ausnehmen.

### M1.2 (2026-11-06): Kratzer-Texturen + Tiefen
- `tools/gen_textures.ps1` (PowerShell + System.Drawing, kein Python installiert; fester Seed → reproduzierbar)
  erzeugt `mod/art/patina/scratch_light|medium|deep.png` (1024², weiß, Form im Alpha). Vanilla-Decals: RGBA PNG
  2048² + optionale Sidecar `*.dynDecalTexture.json` für den Editor (`type 0` = Graustufen,
  `editor/api/dynamicDecals/textures.lua:19`) – für die Projektion nicht nötig.
- Tiefe pro Knoten: 1. Treffer leicht (hell, 0.55), 2. mittel (Grundierung grau, 0.85), ab 3. tief (silbern, 1.0);
  ≥ 8 m/s mindestens mittel; max. 3 Ebenen pro Knoten. Reset leert auch die Zählung.
- `patina_main.testScratch(side, level)` zum Ansehen der Texturen.

### M1.2, Lauf 1 (2026-11-06)
- Sebastian: leicht unsichtbar, mittel nur aus der Nähe, tief deutlich; Spuren sollen in Fahrtrichtung laufen;
  bei 80 km/h hunderte Meter an der Wand kaum Kratzer.
- Log: nur 5 Knoten berühren die Wand (n274/276/278/382/384) → mit max. 3 Ebenen pro Knoten genau übereinander
  höchstens 15 kleine Flecken (0.08 × ≤ 0.4 m), tief nach 0.45 s erreicht und deckt leicht/mittel zu.
  Linien in der Textur 1.5–4 px auf 1024 px bei 7–8 cm Breite ≈ 0.1–0.3 mm → unsichtbar.
- Änderung: Linien 3–4× dicker und deckender, Decals 10–12 cm breit, 0.3–1.0 m lang (mit Gleitgeschwindigkeit),
  Stufe nach Treffer 1/3/5, bis 8 Ebenen pro Knoten, ab dem 2. Treffer ±25 % der Länge entlang der
  Schleifrichtung versetzt → durchgehende Spur.

### M1.2, Lauf 2 (2026-11-06)
- Sebastian: Kratzer sehen sehr gut aus ✅, deutlich mehr beim Wandfahren ✅, aber senkrecht statt längs ❌.
- Screenshot `20-58-37`: testScratch Seite (n=+x, up=−y, 0.2 × 0.6 m) liegt senkrecht → Länge entlang n × up
  (= −z); passt auch zu Lauf 1 (Dach quer). `quatFromDir(-n, up)` + `QuatF:getMatrix()` dreht für die
  Decal-Projektion offenbar um 90° um die Blickachse. Fix: `up = up × n` vor dem Bau der Kameramatrix.

### M1.2, Lauf 3 (2026-11-06)
- `up = up × n` änderte an den Seiten nichts (weiter senkrecht), Dach-Test verfehlt (Treffer −9e999) ❌
  → Kamera-Rolle bestimmt die Decal-Ausrichtung **nicht**. Ausrichtung kommt aus `decalRotation` (Layer-Feld,
  `editor/api/dynamicDecals.lua:905`, Radiant) relativ zu einer festen Bezugsachse.
- Aus Lauf 1/2 bei Rotation 0: Seite → Länge entlang z, Dach → entlang x ⇒ Bezugsachse = n × (0,1,0) (Annahme).
  Jetzt: Kamera wieder mit Schleifrichtung als up, `decalRotation` = Winkel Bezugsachse → Schleifrichtung um n.
  Vorzeichen offen → `testScratch(side, level, tilt)` mit Neigung prüfen. Front/Heck (n ∥ y) noch Rotation 0.

### M1.2, Lauf 4 (2026-11-06)
- Seiten jetzt längs ✅. `testScratch("right",3,30)` (vorne höher erwartet) → hinten höher ❌ → Drehsinn negativ.
- Dach unsichtbar, obwohl Treffer auf dem Dach (z 1.162) mit Drehung 90°. In Lauf 1 (Rotation 0) lag der
  Dach-Kratzer schon längs (Screenshot 20-52-12) → Annahme „Bezugsachse x auf dem Dach“ war falsch.
  Neu: Bezugsachse = z in die Fläche projiziert, auf waagerechten Flächen y; Drehung negativ.

### M1.2, Lauf 5 (2026-11-06) ✅ Ausrichtung
- Dach sichtbar und längs ✅, rechts 30° geneigt vorne höher ✅, Seiten längs ✅.
- Bestätigt: Decal-Ausrichtung = `decalRotation` (negativer Drehsinn) ab Bezugsachse „z in die Fläche
  projiziert, auf waagerechten Flächen y“. Kamera-Rolle egal.

### M1.3 Fahrzeugtest, Lauf 1 (2026-11-06)
- Gavril D-Serie (`pickup`, 2 Lackmat., Neuspawn 499 ms), Ibishu Covet (`covet`, 2, 517 ms), Gavril Vertex
  (`gavril_vertex`, 2, 737 ms): Lack normal, Kratzer an der Schrammstelle und längs ✅. Noch kein Mod-Fahrzeug.
- Chromstoßstange D-Serie: Kratzer unsichtbar (hell auf hell) → offen, Farbwahl.
- Weiße Flecken D-Serie Motorhaube hinten links: Frontaufprall, Unterboden-Knoten (n ≈ −z); Strahl geht durch
  die Lücke und trifft die Motorhaube von innen (z. B. angefragt z 0.03 → Treffer z 0.91, 0.6-m-Grenze ließ
  Ähnliches durch). Vertex: seitliche Anfrage → Treffer 0.43 m weiter innen.
- Fix: Treffer getrennt prüfen, entlang n ≤ 0.2 m und seitlich ≤ 0.25 m.
- Vertex testScratch("top") verworfen (Treffer z 0.11): AABB-Oberkante 1.36 liegt über einer Nicht-Lack-Fläche,
  Strahl geht durch → Verwerfen funktioniert.

### M1.3 Fahrzeugtest, Lauf 2 (2026-11-06)
- Flecken weniger, nicht weg; entstehen beim Schleifen der Spiegel. D-Serie Spiegel-Knoten bei x −0.52…−0.60,
  y 0.12–0.26, z 0.85–0.90 stehen vor dem Lack → Strahl trifft innen Motorhaube/Kotflügel. Abweichungen entlang n:
  gute Schramm-Treffer meist ≤ 0.07 m, verworfene 0.2–0.6 m → für Sensor-Kratzer Grenze 0.1 m (`tolAlong`),
  testScratch bleibt 0.2 m (startet an der AABB).
- **Gavril Vertex NA2 ist ein Mod** (`mods/repo/innocent_gavril_vertex.zip`, nicht in content/vehicles) →
  Mod-Fahrzeug-Test ✅. Damit 3 Vanilla (ETKI, D-Serie, Covet) + 1 Mod.
- Chrom: erst einmal weglassen (Sebastian).
- Achtung: `mods/repo/dynamic_scratches_mod_beta.zip` ist **aktiv** (db.json) – fremder Kratzer-Mod, kann Tests
  verfälschen. Nicht angesehen (keine fremde Logik übernehmen).

### M1 Kratzer-MVP abgeschlossen ✅ (2026-11-06)
- Flecken durch Spiegel weg ✅, fremder Kratzer-Mod deaktiviert, Screenshot-Freigabe Sebastian ✅.
- Erfüllt: Schrammen → Kratzer an der richtigen Stelle, längs der Schleifrichtung, 3 Tiefen, auf ETKI, D-Serie,
  Covet (Vanilla) und Gavril Vertex NA2 (Mod).
- Offen/vertagt: Chrom-Teile (Kratzer hell auf hell); „Kontakte zu Strichen verbinden“ vorerst durch versetzte
  Ebenen ersetzt – Budget 100 Ebenen ist bei langem Schrammen schnell voll (später: Zusammenfassen/Atlas);
  Spike-5-Reste (g-Formel, Fahrzeug-gegen-Fahrzeug über nodeCollision?); Front/Heck-Ausrichtung ungetestet.

## M2 Dreck

### M2.1 Radspritzer (2026-11-06)
- Konzept: Radspritzer pro Rad, Stärke aus Tempo/Schlupf, Ziele Radkasten/Schweller/hinter dem Rad/Heck; Farbe
  nach Untergrund (Konzept-Frage Tabelle vs. Terrain-Textur → MVP feste Tabelle pro collisiontype-ID).
- Sensor: pro Rad Strecke + Schlupf auf losem Untergrund (IDs 14–20, 22) sammeln, je 12 m ein Ereignis.
  Felder geprüft: `wd.wheelSpeed` vorzeichenbehaftet (`vehicle/wheels.lua:653-658`), `wd.contactMaterialID1/2`,
  `wd.downForceRaw`, `wd.lastSlip` (`wheels.lua:374`), `wd.node1/.node2/.radius/.isBroken` (`wheels.lua:247,251,292`).
  Radmitte = Mitte der Achs-Knoten (Ausgangsposition − Referenzknoten), äußere Seite = Achs-Knoten weiter von der
  Fahrzeugmitte.
- GE: Spritzer seitlich hinter dem Rad (1.0–1.8 r), Hinterrad 30 % aufs Heck; 0.3–0.55 m, zufällige Drehung,
  Deckkraft 0.3–0.75, max. 30 pro Rad. Maske additiv (`blendMode 2`, `editor/api/dynamicDecals.lua:755`), damit
  Dreck sich aufbaut; Farbe normal darüber.
- Textur `dirt_splash.png` (Generator, Seed 4004).
- Budget 100 → 300 Ebenen: Voll-Bake (überlinear) passiert nur bei clear/Neuanlage mit leerer Liste; inkrementell
  konstant 0.8 ms/Decal (Spike 3). Für spätere Persistenz (Neuspawn mit Zustand) muss zusammengefasst werden.
