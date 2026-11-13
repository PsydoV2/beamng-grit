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

### M2.1, Lauf 1 (2026-11-06)
- Sebastian: Dreck sieht gut aus, Farbe passt zum Untergrund (GRASS), Positionen grob ✅; soll großflächiger sein.
  Auf der Chrom-Zierleiste der D-Serie läuft der Dreck weit über den runden Fleck hinaus nach hinten (Screenshot
  `21-28-32`).
- Log: seitliche Spritzer bei z = Achse − 0.1 m → 10 von 10 Strahlen verfehlten die Karosserie (Welt-Treffer);
  nur Heck-Spritzer kamen an. Fix: Höhe Achse +0.1…+1.0 r, Breite entlang des Autos 0.7–1.3 m, Höhe 0.45–0.7 m,
  Mitte 1.3–2.5 r hinter dem Rad; Heck 0.45–0.8 m rund.
- Zierleiste: Verdacht UV1-Layout der Leiste (gestreckt/überlappend → ein Fleck in der Textur erscheint entlang
  der ganzen Leiste). Kein Patina-Fehler der Platzierung; Prüfung offen (Vanilla-Decal-Editor auf der Leiste).

### M2.1, Lauf 2 (2026-11-06)
- Sebastian: deutlich besser, großflächiger ✅; aber beim Weiterfahren kommt mal mehr, mal weniger Lackfarbe durch ❌.
- Deutung: Deckkraft nimmt ab, wenn ein schwacher Spritzer über einen starken kommt → additive Maske
  (`blendMode = 2` am Layer) greift nicht, es wird normal überblendet. (Vermutung, nicht einzeln gemessen.)
- Fix unabhängig vom Blend-Modus: Deckkraft je Bereich (Seite je Rad, Heck gemeinsam) monoton, max(vorher, Tempo),
  +0.02 pro Spritzer, höchstens 0.9. Additiv-Code entfernt.

### M2.1, Lauf 3 (2026-11-06)
- Sebastian: Dreck deutlich besser ✅, aber es flackert weiß beim Fahren im Dreck ❌.
- Deutung: Während der 3 Projektions-Frames zeigt die Farb-Projektion eine Vorschau mit `decalColor` (1,1,1,1)
  in der Live-Textur (`combineTextures` jeden Frame) → weißer Blitz, wo die Maske schon Dreck hat. Bei Kratzern
  (hell) fiel das nicht auf. Fix: Vorschau-Alpha 0; die Layer-Farbe kommt ohnehin aus `variants()`.

### M2.1, Lauf 4 (2026-11-06) ✅ Radspritzer
- Flackern weg ✅, Kratzer weiter sichtbar ✅. Reihenfolge stimmt: erst Kratzer, dann Dreck → Dreck deckt zu ✅;
  erst Dreck, dann Schrammen → Kratzer liegen oben (gewollt: Schrammen reibt den Dreck ab).

### M2.2 Staub (2026-11-06)
- Sensor: mind. 2 Räder auf trockenem losem Untergrund (DIRT_DUSTY 14, DIRT 15, SAND 16, SANDY_ROAD 17,
  GRAVEL 19), Tempo ≥ 8 m/s (`obj:getVelocity()`, `vehicle/controller/dragTimer.lua:60`) → je 35 m ein Ereignis.
- GE: 70 % Heck (+y, 0.9–1.4 m, Deckkraft 0.12 → max 0.5), 30 % Oberseite von oben (1.0–1.6 m, hinten dichter,
  0.08 → max 0.28); monoton je Bereich; max. 80 Ereignisse. Farbe aus der Dreck-Tabelle.
- Textur `dust.png` (Seed 5005): sehr weiche große Flecken + feine Körner.

### M2.2, Lauf 1 (2026-11-06)
- Sebastian: Staub-Deckkraft gut ✅, aber „sehr geometrische Formen“ ❌; am Anfang brechen die Frames deutlich ein ❌.
- Screenshot `21-53-58` (D-Serie, Utah): Dreiecke/Rechtecke auf Tür und Bordwand.
- Ursache Formen: `decal.ps.hlsl:116-121` prüft nur, ob der Pixel in der Box liegt – kein Winkeltest zur Fläche.
  Staub-Box 0.6 m tief von oben/hinten → senkrechte Flächen darunter/daneben gestreckt eingefärbt.
  Fix: Staub-Tiefe 0.15 m, Flecken kleiner (Heck 0.6–1.0 m, oben 0.7–1.1 m).
- Frames: noch nicht gemessen → Messung eingebaut: `status()` loggt Frametime „Patina arbeitet“ vs. Leerlauf,
  CPU von `render:update` und Bake-Zeit pro Decal (Ø/max).

### M2.2, Lauf 2 (2026-11-06) – Messung
- Formen noch da (Screenshots `22-05-09/14/19`): senkrechte graue Streifen an der Bordwand der D-Serie.
  Log 22:03:13: Aufsetzen auf Schotter mit 24 m/s → 121 Schrammen von Unterboden-Knoten (n ≈ −z) → Projektion
  von unten färbt die senkrechte Bordwand in der Box. Außerdem lagen große Staub-Flecken über den Bildrand
  (Abstand 0.36·size + Radius bis 200 px > 512) → harte gerade Kanten.
- Messwerte `status()` (D-Serie, Utah):
  - Leerlauf Ø 11.5 ms / max 21.6 ms; „Patina arbeitet“ (Warteschlange nicht leer) Ø 15.2 ms / max 21.9 ms
    → ≈ +3.7 ms je Frame, solange Decals abgearbeitet werden. Später (wenig Arbeit) Ø 12.9 vs. 11.2 ms.
  - `render:update` CPU Ø 1.7 ms, **max 30.2 ms**; im Leerlauf Ø 0.6 ms (refresh + combineTextures jeden Frame).
  - Bake 188 Decals Ø 0.75 ms, max 1.77 ms (wie Spike 3).
  - Einbruch am Anfang = 240 Decals auf einmal (121 Schrammen + 120 Spritzer) → lange Arbeitsphase.
- Fixes: Unterboden-Schrammen (n.z < −0.6) ignorieren; Staub-Flecken ganz im Bild; Textur nur bei Wechsel setzen
  (Verdacht für die 30-ms-Spitze); combineTextures im Leerlauf nur alle 60 Frames.

### M2.2, Lauf 3 (2026-11-06)
- Formen weg ✅, Lack beim Kameradrehen normal ✅ (combineTextures im Leerlauf nur alle 60 Frames reicht).
- „Zu wenig Dreck, feiner Staub nimmt viel größere Flächen ein“ → Staub auch an den Seiten (untere Hälfte),
  größer (1.0–1.6 m), Tiefe 0.3 m, alle 15 m statt 35 m, max. 220; Budget 300 → 500 Ebenen.
  Abweichung vom Konzept (Staub nur Heck + Oberseiten) auf Sebastians Wunsch.
- Messung: „Patina arbeitet“ Ø 12.7 vs. Leerlauf 11.5 ms (vorher +3.7, jetzt +1.2 ms) ✅. Bake Ø 0.72–0.77 ms.
  `render:update` CPU weiterhin Einzelspitze 35.9 ms; Leerlauf-CPU Ø 0.6 ms kommt aus `refresh()`.
  → Abschnitts-Zeiten eingebaut: `render:update` > 8 ms loggt refresh/setup/project/getDecalData/bake/combine.

### M2.2, Lauf 4 (2026-11-06) – Ruckler-Ursache gefunden
- Sebastian: nach Strg+L wieder große geometrische Formen (Screenshot `22-17-49`: große schwarze/weiße Flächen
  auf der Motorhaube), nach Reparatur nicht; Staub sehr klein; Zahlen besser, ruckelt aber spürbar.
- Formen: 22:17:37 Fahrt durch Büsche (Untergrund 7 FOLIAGE, 13.7 m/s) → ~64 Schrammen vorne links mit Normale
  (−0.53, −0.79, 0.30), also ins Auto/quer → Projektion streift schräg über die Haube, Kratzer 1.1 m lang, Stufe
  „mittel“ dunkelgrau. Kein Strg+L-Effekt. Fix: FOLIAGE/CLOTH/WATER kratzen nicht; Normale, die zur Fahrzeugmitte
  zeigt (n·Richtung-nach-außen < −0.3), wird verworfen.
- **Ruckler: `projectDynamicDecals` kostet 8–16 ms CPU je Aufruf** (Aufschlüsselung `render:update`: refresh
  0.5–0.7, project 8.4–15.9, getDecalData 0–0.7, bake 1.2–1.5, combine ≤ 0.5). Bisher 3 Aufrufe je Decal.
  Fix-Versuch: nur jeden 3. Frame projizieren (1 Aufruf je Decal, getDecalData danach); `setShape` nur bei
  Neuanlage/Rebake/clear statt jeden Frame (Verdacht: stößt Mesh-Aufbereitung neu an).
- Staub: Oben-Strahlen trafen die Ladefläche ~1 m unter der AABB-Oberkante → verworfen; tol oben 1.2 m.
  Start-Deckkraft Staub höher (Heck 0.18, Seite 0.15, oben 0.12).

### M2.2, Lauf 5 (2026-11-06)
- Sebastian: ruckelt weniger ✅, keine Formen mehr, auch im Gebüsch ✅; Dreck hinter den Rädern, aber nicht
  autodeckend.
- Messung: `projectDynamicDecals` weiterhin 11.6–15.4 ms je Aufruf, jetzt 1× statt 3× je Decal. `setShape` war
  nicht die Ursache. → Jedes Decal kostet einen Frame-Hänger von ~12–15 ms. Autodeckender Dreck braucht viele
  Decals → so nicht tragfähig.
- Nächster Schritt **Spike 6: Decals ohne Projektion** – Layer-Daten selbst bauen (Vorlage aus einem echten
  `getDecalData`, eigene Kamera/Normale/Position). Felder laut Editor (`editor/api/dynamicDecals.lua:1787-1796`):
  camPosition, camDirection, decalPos, decalNorm, viewToScreen, worldToViewToScreen, useZBufferDepth,
  zBufferDepth, useLockedSurfaceNormal, surfaceNormal, cursorPosScreenUv, decalScale, decalSkew, decalRotation,
  useSurfaceNormal, mirrored. Dafür Dump der ersten 3 Treffer samt eigener camM/projM ins Log eingebaut.

### Spike 6: Decals ohne Projektion (2026-11-06)
- Dump von 3 echten `getDecalData`-Ergebnissen (testScratch links/oben/rechts 30°), Felder u. a.:
  `camPosition` = unsere Kameraposition, `camDirection` = `decalNorm` = `surfaceNormal` = −n,
  `decalPos` = Oberflächenpunkt (z. B. angefragt x −0.60 → −0.416), `decalScale` = (Breite, Tiefe, Länge),
  `decalRotation` = unser Wert, `viewToScreen` = unsere projM, `worldToViewToScreen` = projM · camM⁻¹
  (Zeile 1 und 2 von Hand nachgerechnet, stimmt), `useZBufferDepth` false, `cursorPosScreenUv` (0.5, 0.5).
- Umsetzung: erste echte Projektion liefert die Vorlage. Pro Zelle (Bereich + 0.4-m-Raster) einmal echt projizieren,
  Abstand Anfrage→Oberfläche entlang n merken; weitere Decals der Zelle synthetisch, bis 4 je Frame, ohne
  `projectDynamicDecals`. Zelle mit 2 Fehlschüssen und ohne Treffer wird übersprungen.
  Matrix-Produkt `MatrixF * MatrixF` wie `core/vehicle/partmgmt.lua:437`. Umschalter `patina_main.synthetic(false)`.

### Spike 6, Lauf 1 (2026-11-06) ✅
- X aus projiziertem + synthetischem Kratzer sichtbar ✅ → synthetische Layer-Daten werden korrekt gebacken.
- Fahrt: 151 Ebenen, davon 114 synthetisch, 10 Zellen übersprungen, 59 Zellen. Frametime „arbeitet“ Ø 11.4 ms vs.
  Leerlauf 11.1 ms (vorher +1.2 bis +3.7 ms) – Sebastian: ruckelt nicht mehr merkbar ✅. Bake jetzt Ø 1.29 ms
  (größere Decals). Schmutz an sinnvollen Stellen ✅.
- Offen: an der Leitplanke kein Kratzer; Log nur 3 Schrammen (Untergrund 13 ROCK). → Diagnose eingebaut:
  Sensor zählt Karosserie-Kontakte je Grund (langsam/weich/pause/unten/innen/ok) und Untergrund-ID, alle 2 s
  `patina_main.onSensorDiag` → Log „Kontakte …“.

### M2.2, Lauf 6 (2026-11-06) ✅ Staub, Leitplanke geklärt
- Diagnose: Leitplanke meldet Untergrund 2 METAL, ok-Kontakte 6–27 je 2 s, Kratzer kommen an (15 Decals,
  6 synthetisch) – liegen bei der D-Serie aber tief (z 0.09–0.34, Schweller/Stoßstangenecken).
- Sebastian mit schwarzem Mod-Auto: Kratzer und Staub deutlich sichtbar ✅. Auf weißem Lack ist hell auf hell
  schwer zu sehen (wie Chrom, vertagt).

### M2.3 Kontakt-Dreck (2026-11-06)
- Sensor: Karosserie-Knoten (keine Räder) mit Kontakt auf SMEAR-Untergrund (14 DIRT_DUSTY, 15 DIRT, 16 SAND,
  17 SANDY_ROAD, 18 MUD, 20 GRASS, 22 SNOW) → Ereignis `contacts` statt Schramme, unabhängig vom Schlupf,
  0.3 s Pause je Knoten; Unterboden und nach innen zeigende Normalen wie bei Schrammen verworfen.
  Schotter (19) und harte Untergründe kratzen weiter.
- GE: Dreckfleck 0.35–0.6 m an der Kontaktstelle, Farbe nach Untergrund, Deckkraft je Knoten 0.45 → 0.9 monoton,
  max. 6 je Knoten, 150 gesamt. Zähler „Kontakt-Dreck“ in `status()`.

### M2.3, Lauf 1 (2026-11-06) ✅
- Schlamm (18 MUD) an der linken Seite: Kontakt-Dreck sitzt an der Berührstelle ✅. Sebastian: „könnte größere
  Flecken haben“ → Größe 0.6–1.0 m (vorher 0.35–0.6).

### M2.3, Lauf 2 (2026-11-06) ✅ M2 Dreck abgeschlossen
- Kontakt-Flecken 0.6–1.0 m: Größe passt (Sebastian). M2.1 Spritzer, M2.2 Staub, M2.3 Kontakt-Dreck bestätigt.
  Tag `m2-dreck`. Übergabe für neue Sessions in `CLAUDE.md`.

### Umbenennung Patina → Grit (2026-11-06)
- Öffentlicher Name **Grit** („Grit – Dynamic Dirt, Scratches & Cracks for every vehicle“), Autor Psydo,
  Lizenz CC BY-NC-SA 4.0. Code umbenannt: `grit_main`, `lua/ge/extensions/grit/`, `lua/vehicle/controller/grit/`
  (`gritSensor`), `art/grit/`, `scripts/grit/`, Textur-Sets `@GritTexture`/`@GritMask`, Skin-Slot `grit`,
  Log `<User>/grit.log`. Junction `mods/unpacked/grit` → `E:\BeamNGMods\Dynamic Patina\mod` (alte `patina` entfernt).
  Spike-Skripte nach `spikes/` verschoben (nicht im Release). Ältere Einträge oben nennen noch die Patina-Namen.
- Test nach Neustart (2026-11-06): grit aktiv, Kratzer und Dreck wie vorher ✅ (Sebastian), Log `grit.log`.

### Mod-Icon im Mod-/Repo-Manager (2026-11-07)
- Mod-Manager liest Icon und Bilder nur aus `mod_info/<ID>/info.json` im ZIP (`core/modmanager.lua:126`, `:323-337`:
  `modData.icon` und `attachments[].thumb_filename` relativ zu `/mod_info/<ID>/`). Felder wie `resource_id`,
  `tagid`, `resource_version_id` (`:131-144`) vergibt das offizielle Repository beim Upload.
- `tagid` wird zur Update-Prüfung an den Server geschickt (`:1350-1351`) → **kein eigenes `mod_info` erfinden**.
  Icon/Bilder beim Upload ins Repository hochladen (dann fügt das Repo `mod_info` selbst ein). Ein privat
  weitergegebenes ZIP zeigt im Mod-Manager kein Bild.

## M3 Zustand

### M3-Plan (2026-11-07, mit Sebastian abgestimmt)
- Problem: Waschen/Trocknen ändern bestehende Decals → Voll-Bake (Spike 3: 200 Layer 1,2–2,8 s) unbrauchbar.
- **Radierer** (Sebastian: ja): große synthetische Box (Spike 6), schwarz nur in die Maske, Alpha = Stärke.
  Belege: `shaders/common/dynamicDecals/decal.ps.hlsl:222` (`alpha *= color.a`, Layer-Farbe skaliert die Deckung),
  Box ohne Winkeltest `:116-121` → Box von der Seite mit Tiefe = Fahrzeugbreite trifft beide Seiten.
  Kratzer liegen in derselben Maske → in der Box danach neu darüber backen (inkrementell).
- **Nässe = dunkler, ohne Glanz** (Sebastian: ja). Abweichung vom Konzept (dort „dunkel und glänzend“):
  die Grit-Stage hat feste `roughnessFactor 1` (`main.lua` ensureSkinMaterial).
- **Regen wäscht ab**: Sebastian ja, aber optional/später, jetzt keine Arbeit hinein.
- Gefundene APIs: Knoten im Wasser `obj:inWater(cid)` (`lua/vehicle/fire.lua:87`,
  `lua/vehicle/controller/playerController.lua:376`); Regen `core_environment.getPrecipitation()` → `numDrops`
  des Objekts „Precipitation“ (`lua/ge/extensions/core/environment.lua:1241-1248`, nil ohne Regen-Objekt).
- Schritte: Spike 7 Radierer (`testWash`) → M3.1 Waschen im Wasser → M3.2 Nässe/Trocknen → M3.3 Staub auf Asphalt.

### Spike 7: Radierer (2026-11-07) – Aufbau
- `render.lua` `R:erase(veh, box)`: Layer per `R:synth` (Vorlage nötig, d. h. erst ein echtes Decal), Textur
  `art/grit/solid.png` (64², voll weiß, `tools/gen_textures.ps1`), Masken-Farbe `(0,0,0,Stärke)`, keine Farb-Variante.
  Layer bleibt in `self.layers` (Feld `gritErase`), Voll-Bake spielt ihn mit. Kratzer in der Box werden ans
  Listenende verschoben und neu gebacken.
- Konsole `grit_main.testWash(höhe, stärke)`: Box von der Seite (n = +x), alles bis `höhe` m über der
  AABB-Unterkante. Log: Linie, Zeit, Anzahl Kratzer neu.
- Offen: Ist `decalPos` die Box-Mitte (Tiefe beidseitig)? Annahme aus `R:request` (Kamera bei pos + n·(depth/2+0.2)).

### Spike 7, Lauf 1 (2026-11-07, Gavril Vertex NA2, schwarz) ✅ Radierer funktioniert
- `testWash(0.6, 0.5)` und `(0.6, 1)`: Dreck bis zur Linie auf allen Seiten weg (Sebastian), Kratzer im sauberen
  Bereich bleiben, keine Formen/Streifen. Screenshots 09-10-45 (vorher), 09-11-08, 09-11-29.
- Kante ist hart (waagerechte Linie an der Tür). Linie z = 0.40 bei Unterkante −0.20 → Box-Mitte = `decalPos`,
  Tiefe beidseitig (Annahme bestätigt, beide Seiten getroffen).
- Kosten: 26.2 ms / 18.9 ms einmalig je Radierer (inkl. 7 Kratzer neu). → beim echten Waschen höchstens etwa 1×/s.
- 140 Ebenen nach dem Test, Bake Ø 0.98 ms.

### M3.1 Waschen im Wasser (2026-11-07) – Aufbau
- Sensor: alle 0.5 s `obj:inWater(cid)` für alle Knoten; Wasserlinie = höchste Ausgangsposition (relativ zu
  `refPos`) eines Knotens im Wasser; Kosten mit `HighPerfTimer()`/`:stop()` gemessen (`vehicle/jbeam/stage2.lua:592,610`).
  Feld `water = { z, n, v, ms }` im Ereignis-Paket.
- GE `handleWater`: Linie = z + 0.05; höchstens 1 Radierer/s, je 40 %, 4 Schritte pro Höhe (≈ 87 % weg).
  Steigendes Wasser oder neuer Dreck → neu. > 2 s ohne Wasser → alte Linie verfällt. Uhr aus `dtReal`.
- Nach jedem Waschschritt: `dirtLevel` × (1 − Stärke), Mengen-Grenzen (Spritzer/Kontakt/Staub) zurück, damit
  danach wieder Dreck entsteht (Vereinfachung: ganzes Auto).
- Bekannt: jeder Schritt ist ein Layer im Budget (500). Waschkante hart (Spike 7).

### M3.1, Lauf 1 (2026-11-07, Gavril Vertex NA2 + Moonhawk) ✅ Waschen
- Sebastian: keine Ruckler, Waschkante gut, kurze Durchfahrt wäscht nur wenig, „funktioniert wie es soll“.
- Log: Wasser-Messung 0.08–0.20 ms je 0.5 s; Waschschritt 6–46 ms (meist 8–20, 7–12 Kratzer neu darüber),
  höchstens 1/s. Durchfahrt mit 12–16 m/s → 1 Schritt. 38 Waschschritte in der Sitzung.
- **Budget wird knapp:** 337 Ebenen nach einer Sitzung (549 Spritzer, weil Waschen die Mengen-Grenzen zurücksetzt;
  jeder Waschschritt ist selbst ein Layer). → „Layer zusammenführen“ rückt näher (offener Punkt).

### M3.2 Nässe und Trocknen (2026-11-07) – Aufbau
- Nass = Farbe × (1 − 0.45·Nässe), ohne Glanz (Sebastian ja). Nass: Schlamm (18) immer; Spritzer und Kontakt-Dreck
  bis 60 s Spielzeit nach dem letzten Wasserkontakt (`car.wetUntil`, jedes Wasser-Ereignis frischt auf).
  Staub bleibt trocken.
- Trocknen in `R:dry`: Alter += dtSim · rate, rate = min(4, 1 + 0.1·Tempo m/s) (Fahrtwind). Ab 45 s halb (0.5), ab 90 s
  trocken. Dann **nur die Farb-Variante** neu backen (Maske bleibt → Gewaschenes bleibt weg, kein neuer Layer),
  höchstens 4 Layer pro Frame; Kratzer im Umkreis (0.7·max(Breite, Länge) + 0.3 m) bekommen ihre Farbe neu darüber.
- Belege: `onUpdate(dtReal, dtSim, dtRaw)` (`lua/ge/main.lua:1006`), `veh:getVelocity()` im GE
  (`lua/ge/extensions/career/modules/fuel.lua:317`).
- `status()` zeigt „Nässe: n nass, n halb, Auto nass noch s; Trocknen: Bakes Ø/max“.

### M3.2, Lauf 1 (2026-11-07, Moonhawk) ✅ Nässe und Trocknen
- Sebastian: nass sichtbar dunkler, wird in Stufen heller, kein Aufblitzen/Ruckler, Kratzer bleiben beim Trocknen.
- Log: 102 Spritzer nass → 18 nass / 83 halb → 0/0; 106 Trocknungs-Bakes Ø 0.60 ms, max 1.35 ms;
  render:update CPU max 2.0 ms im zweiten Abschnitt.

### M3.3 Staub auf Asphalt – gestrichen (2026-11-07) ✅ M3 Zustand abgeschlossen
- Sebastian: Staub soll auf Asphalt **nicht** verschwinden, „erst Wasser wäscht es weg“. Abweichung vom Konzept,
  dort und im Zustandsmodell eingetragen.
- M3 = M3.1 Waschen + M3.2 Nässe/Trocknen + Reset (seit M1) → abgeschlossen, Tag `m3-zustand`.

## M4 Risse

### M4.1 Riss-Erkennung und -Decals (2026-11-07) – Aufbau
- Sebastian: erst nur Kunststoff, kein Glas.
- Belege: Kunststoff-Knoten = `nodeMaterial == 3` (`lua/vehicle/beamstate.lua:886`, Plastiksplitter beim Bruch);
  Einschlag = `p.perpendicularVel` (`lua/vehicle/main.lua:491`, Verwendung `particlefilter.lua:29`);
  Bruch = Controller-Feld `beamBroken(id, energy)` (`lua/vehicle/controller.lua:596`, Aufruf `main.lua:371`),
  Beam über `v.data.beams[id]` (`beamstate.lua:820`). `beamDeformed` nur bei Beams mit Deform-Triggern (`main.lua:376`) → nicht genutzt.
- Sensor: Stoß ab 5 m/s auf Kunststoff-Knoten (Normale wie Schrammen) oder Bruch eines Beams an einem
  Kunststoff-Knoten (Normale geschätzt: Hauptachse von der Fahrzeugmitte). 1 s Pause pro Knoten. Diagnose
  `riss:stoss`, `riss:bruch`, `riss-pause`, `riss-unten`, `plastikKnoten:<Anzahl>`.
- GE: Stoß ≥ 10 m/s oder Bruch → Spinnennetz 0.3–0.5 m, sonst Haarriss 0.25–0.45 × 0.16 m quer zur Richtung.
  Mittelgrau (0.5), Stärke 0.9, Tiefe 0.15, tol 0.15 (Stoß) / 0.3 (Bruch); max 2 pro Knoten, 80 gesamt.
- Risse bleiben beim Waschen und Trocknen obenauf (`render.isDamage`, gemeinsam mit Kratzern).
- Texturen `crack_hair.png` (Seed 6006), `crack_web.png` (Seed 6007) in `tools/gen_textures.ps1`.
- Einschränkung: Risse erscheinen nur auf lackierten Materialien (Grit-Stage). Unlackierter schwarzer Kunststoff
  bekommt keine.

### M4.1, Lauf 1 (2026-11-07, Ibishu Covet, schwarz)
- Sebastian: erst bei 50 km/h ein paar Risse an der Aufprallstelle, Optik „erstmal ok“.
- Log: 109 Kunststoff-Knoten. **Nur Bruch-Risse** (`riss:bruch` 6/3/29, Energie immer 0.0), **kein einziger
  Stoß-Riss** (`riss:stoss` fehlt). 38 Risse angefragt, 13 ohne Treffer: vorne Strahl ~1 m tiefer getroffen
  (angefragt y −1.76, Treffer y −0.4 … −0.67), Verdacht: Covet-Stoßstange ist unlackierter Kunststoff (Screenshot
  09-51-54) → keine Grit-Ebene, Strahl geht durch.
- Nächster Lauf: Diagnose `plastikKoll:<Tempo-Eimer>` und `plastikMax:<Höchstwert>`; Log der lackierten Meshes und
  unlackierten Materialien beim Aktivieren.

### M4.1, Lauf 2 (2026-11-07, Covet + ETK I-Series)
- **`p.perpendicularVel` ist an Kunststoff-Knoten immer 0:** 546 Kollisionen alle im Eimer 0–1, `plastikMax:0.0`.
  → kein Aufprall-Tempo; Stoß-Weg entfernt.
- Covet: Stoßstange schwarz und unlackiert (Sebastian) → Risse dort unmöglich (keine Grit-Ebene).
- ETKI: lackierte Meshes `character_primary, etki_mechanicals, etki`. Bruch-Risse an der Front (y −1.67 … −1.79),
  wenige verworfen; Sebastian: „sieht man kaum etwas auf der Stoßstange“. Energie beim Bruch immer 0.0.
- Neu: **Dellen-Erkennung** wie die Debug-Ansicht „displacement“: `obj:getNodePositionRelative(cid)` −
  `obj:getOriginalNodePositionRelative(cid)` (`lua/vehicle/bdebugImpl.lua:1057-1058`), alle 0.25 s für alle
  Kunststoff-Knoten, je 3 cm weiterer Eindrückung ein Riss (Normale = −Verschiebung auf Hauptachse); ab 8 cm Netz.
  Diagnose `delleMax:<m> <ms>`. Offen: Ist die relative Lage fahrzeugfest? (Sonst würde Drehen als Delle zählen.)

### M4.1, Lauf 3 (2026-11-07, ETK I-Series, schwarz) ✅ Dellen-Erkennung
- 30 s Fahrt ohne Unfall: `delleMax 0.01 m`, keine Risse (Sebastian) → relative Lage ist fahrzeugfest.
- 25 km/h frontal: Risse an der Stoßstange (Sebastian „ja“). Log: `riss:delle=44`, `riss:bruch=3`,
  `riss-unten:delle=9`, Delle bis 0.24 m, Messung 0.35 ms je 0.25 s. 8 ohne Treffer (u. a. Heck-Knoten y 2.08,
  Strahl traf y −0.6 → verworfen).
- Screenshot 10-01-11: nur kleine graue Punkte sichtbar, die feinen Linien gehen in der Grit-Textur
  (2048×1024 fürs ganze Auto) verloren → Linien in `crack_*.png` dicker.

### M4.1, Lauf 4 (2026-11-07, ETK I-Series) ✅ M4 Risse abgeschlossen
- Dickere Linien: Risse als Linien klar sichtbar (Screenshot 10-04-30), Sebastian: „Alles passt“ (Sichtbarkeit,
  Mittelgrau, Menge). Log: `riss:delle=8`, Delle bis 0.47 m.
- M4 = Kunststoff-Risse; Glas bleibt Vanilla (Konzept, Sebastian). Tag `m4-risse`.

## M5 Einstellungen / UI

### M5-Umfang (2026-11-07, mit Sebastian)
- M5.1 Einstellungen → M5.2 UI-App (Schalter, Regler, Buttons Waschen / Sofort dreckig / Alles zurücksetzen,
  Warnung bei anderen Dreck-/Kratzer-Mods) → M5.3 Qualitätsstufen (Budget, Zusammenführen, KI-Verkehr).
- **Livery-Editor (Karriere, Skin „Dynamic Textures“): später**, jetzt ignorieren (Sebastian).
- KI-Verkehr: Einstellung, Standard aus (Konzept). Zustand speichern: später, nicht in M5.

### M5.1 Einstellungen (2026-11-07) – Aufbau
- `lua/ge/extensions/grit/settings.lua` (per require, wie render.lua). Datei `<User>/settings/grit.json` mit
  `jsonReadFile`/`jsonWriteFile` (`lua/common/utils.lua:466,484`), Vorbild `core/vehicle/mirror.lua:33-37`.
- Schlüssel: `dirt`, `scratches`, `cracks` (an/aus), `dirtStrength` 0.25–2 (× Deckkraft, max 1), `dryingSpeed`
  0.25–4 (× Trocknungsrate), `aiVehicles`, `quality` low/medium/high (beide erst ab M5.3 wirksam).
  Ungültige Werte werden abgelehnt, Zahlen auf den Bereich begrenzt.
- Dreck aus → keine neuen Spritzer/Staub/Kontakt-Dreck; Waschen läuft weiter. Bestehendes bleibt.
- Konsole: `grit_main.settings()`, `grit_main.set(key, wert)`, `grit_main.get(key)`, `grit_main.resetSettings()`.

### M5.1, Lauf 1 (2026-11-07)
- Speichern/Laden ✅ (Neustart: Werte da, `settings/grit.json`), `scratches=false` ✅ keine Kratzer,
  `quality="ultra"` abgelehnt ✅.
- `dirtStrength=2`: **kein sichtbarer Unterschied** (Sebastian). Ursache: nur Deckkraft × 2; Staub 0.12–0.2,
  Maske gamma-kodiert (enc), Spritzer nahe der Grenze 1.
- Änderung: Stärke skaliert jetzt auch die **Menge** (jedes Dreck-Ereignis zählt k-mal, Bruchteil per Zufall) und
  die Obergrenzen (maxPerWheel, Staub/Kontakt maxEvents/maxPerNode × k). Log zeigt die wirksame Deckkraft.
  Achtung Budget: bei 2 füllt sich das Ebenen-Budget doppelt so schnell.

### M5.1, Lauf 2 (2026-11-07, Gavril Grand Marshal, schwarz) ✅ Dreck-Stärke
- 0.5 vs. 2: klarer Unterschied, Menge bei 2 ok (Sebastian). M5.1 Einstellungen bestätigt.
- ❌ Bei 2 auf einer Seite Streifen „vom Vorderreifen zum Fenster zum Hinterreifen“ (Screenshot 10-24-19:
  schräges Band über die Vordertür, gerade Kante am B-Holm). Verdacht: Seiten-Staub 1.0–1.6 m groß, Box nur 0.3 m
  tief → färbt nur, wo die gewölbte Seitenwand im ±0.15-m-Streifen liegt (Höhenlinie). Test: Seite depth 0.5.
- LuaJIT jetzt installiert (`C:\Users\sebfa\scoop\shims\luajit.exe`) → Syntax-Check vor jedem Test
  (`luajit -b datei.lua /dev/null`), alle Dateien ok.

### M5.1, Lauf 3 (2026-11-07, Grand Marshal) – Streifen links
- Seiten-Staub depth 0.5: Streifen unverändert, weiterhin **nur links**, keine neuen Formen (Sebastian) → zurück auf 0.3.
- Screenshot 10-28-47: harte schräge Kante vom Spiegelfuß zur Türunterkante. Verdeckung ausgeschlossen: Shader prüft
  nur „Pixel in der Box“ (`decal.ps.hlsl:116-121`), Projektions-Flags ohne Tiefen-/Verdeckungsoption
  (`editor/api/dynamicDecals.lua:768-778`); VS malt in UV-Raum (`decal.vs.hlsl:83`).
- Verdacht: **geteilte UVs** (zwei Stellen des Modells auf derselben UV-Fläche) → Dreck von dort erscheint auch hier,
  Kanten folgen der UV-Insel. Test: `testScratch(seite, 3, 0, along)` mit neuem Parameter along (0 vorne … 1 hinten).
- UV-Test (`testScratch` along 0.3/0.5/0.7, beide Seiten): nichts auf der Gegenseite (Sebastian) → **geteilte UVs
  ausgeschlossen**. „links“ = Fahrerseite = Code `left` (+x).
- Nächster Test: Filter `grit_main.onlyDirt("spray"|"dust"|"contact")` – welche Dreck-Art macht den Streifen?

### M5.1, Lauf 4 (2026-11-07) – Streifen nur am ETK, Punktraster, Covet weiß
- Korrektur: Streifen-Läufe 1–3 waren **ETK I-Series** (Log 10:18–10:27, `etki`), nicht Grand Marshal. Der UV-Test
  lief am Grand Marshal (`fullsize`) → geteilte UVs am ETK **nicht** ausgeschlossen. Sebastian: Streifen nur am ETK.
- ETK hat 3 lackierte Meshes: `character_primary`, `etki_mechanicals`, `etki` (Log 10:36:08). Verdacht: ein Mesh
  (z. B. `etki_mechanicals`) nutzt dieselbe UV-Fläche wie die Karosserie → Dreck dort landet auf der Tür.
  Test: `grit_main.onlyMeshes("etki")` projiziert nur auf ein Mesh (`R:setTargets`, clearMaterialIdx/addMaterialIdx
  wie `newProj`).
- Neu gespawnte ETK (107542, 10:36:08) mit buntem Punktraster (Screenshot 10-36-19). Verdacht: Bake beim Anlegen
  trifft Render-Ziele, die noch nicht stehen → Speicher nie gelöscht. Änderung: leerer Stapel nach 5 und 60 Frames
  noch einmal backen (`initBake`).
- Covet: Stoßstangen vorne/hinten nach Streifen/Frontal teils ganz weiß. Noch kein Screenshot.

### M5.1, Lauf 5 (2026-11-07) ✅ Ursache Streifen
- `onlyMeshes("etki")`: kein Streifen. `onlyMeshes("etki_mechanicals")`: **genau und nur** die Streifen (Sebastian)
  → bestätigt: `etki_mechanicals` teilt UV-Flächen mit der Karosserie.
- Punktraster nach `initBake` nicht mehr aufgetaucht (mehrere Spawns) ✅.
- Fix: Meshes mit „mechanical“ im Namen bekommen kein Grit (`EXCLUDE_MESH` in main.lua). Bleiben im Vanilla-Lack.
- Covet weiße Stoßstange: nicht nachgestellt, offen.
- Lauf 5b: Streifen weg, nichts sichtbar zu sauber (Sebastian) ✅.
- Beobachtung: Screenshot 11-25-29 (vor „Grit geladen“ 11:25:33) ETK mit weißen Querstreifen. Das ist das Fenster
  beim Strg+L: alte Projektionen weg, Fahrzeug trägt noch den Grit-Skin → Stage liest ungültige Textur. Nach dem
  Neuspawn weg. Betrifft Spieler nur beim Abschalten des Mods im laufenden Spiel → für M6 vormerken
  (beim Entladen Skin zurücksetzen).
- Nebenbefund: nach Strg+L steht die alte Kopie `etki_mechanicals.grit.v108000` noch im Szenenbaum (unlackiert-Liste)
  und wird vom Skin genutzt; frisch gestartet entsteht sie nicht.

### M5.2 UI-App – Bau (2026-11-07)
- Belege:
  - Apps werden über `FS:findFiles("/ui/modules/apps/", "app.json", -1, …)` gefunden (`ge/extensions/ui/apps.lua:7,121`),
    also auch aus dem Mod-Ordner. Pflicht: `domElement` + `directive` (`apps.lua:154`), `app.js` daneben (`:155-156`).
    `simplemenu` weglassen = überall sichtbar (`apps.lua:32-34`). `interactive: "required"` (`:176`, wie AIControl).
  - Angular-Direktive in `beamng.apps`, `md-slider` (`ui/modules/apps/Winds/app.js:1-7`), `md-checkbox`
    (`ForceFeedbackGraph/app.js:9`), `md-button class="md-raised"` (`ESCStiffness/app.js:6`).
  - `bngApi.engineLua(ausdruck, function(data) …)` liefert den Lua-Rückgabewert (`threedexport/app.js:18-28`).
- Bau: `mod/ui/modules/apps/Grit/` (app.json, app.js). Schalter Dreck/Kratzer/Risse, Regler Dreck-Stärke
  (0.25–2) und Trocknungstempo (0.25–4, setzen erst nach 300 ms Ruhe), Knöpfe Wash (`grit_main.washNow()`: Radierer
  über das ganze Auto, Stärke 1) und Clear all (`grit_main.clear()`), Anzeige Ebenen x/500. Abfrage
  `grit_main.uiState()` alle 2 s. Beschriftung Englisch (Release).
- Lauf 1: App erscheint, Schalter/Regler/Wash/Clear all funktionieren, Werte nach Strg+L da ✅ (Sebastian).
  Wunsch: nicht dauerhaft sichtbar → auf- und zuklappbar. Bau: Kopfzeile „Grit ▴/▾“ per Klick, Inhalt `ng-show`,
  Hintergrund `.bngApp` (`ui/entrypoints/main/main.css:29`) nur an Kopf und Inhalt; Zustand in localStorage
  (try/catch, ohne Speicher zu). Abfrage alle 2 s nur, wenn offen.
- Lauf 2 ❌ (Screenshot 11-42-43): zugeklappt großer halbtransparenter Kasten in App-Größe, aufgeklappt nur orange
  Rechtecke in den unteren Ecken (vermutlich die md-buttons), Einstellungen unsichtbar. Kein Fehler im Log.
  Änderung: `ng-if` statt `ng-show` (Inhalt wird beim Öffnen neu aufgebaut, md-slider in verstecktem Container ist
  ein bekanntes Problem), offen wieder exakt das Layout von Lauf 1, Pfeile als HTML-Entities.
- Lauf 3: aufgeklappt alles richtig ✅, zugeklappt weiter großer Kasten (Screenshots 11-46-28/31). Ursache: der Kasten
  kommt vom Spiel, `overlay-item-editor__hover-bg` (`ui/ui-vue/src/common/modules/overlay/components/OverlayItemEditor.vue:225-232`)
  über den ganzen App-Rahmen (Größe aus app.json `css`). Änderung: Rahmen 28 px hoch, offenes Fenster
  `position: absolute` ragt darunter heraus (`.overlay-item` ohne overflow-Begrenzung, `OverlayItem.vue` Style).
  Gespeicherte Layouts behalten die alte Größe → App einmal entfernen und neu hinzufügen.
- Lauf 4: zugeklappt klein ✅, aufgeklappt abgeschnitten mit Scrollbalken. Ursache `.ui-app-host { overflow: hidden }`
  (`ui/ui-vue/src/modules/apps/components/AppHost.vue` Style). Änderung: offenes Fenster `position: fixed` an der
  Lage der Kopfzeile (getBoundingClientRect, alle 2 s nachgeführt), unten am Bildschirm nach oben ausweichen.
- Lauf 5 (Screenshot 11-53-18): Fenster wandert mit ✅, aber bis 80vh lang (leerer Bereich unten) und die
  Schalter zeigten `true` als leeres Kästchen (grit.json: alle true). Änderung: `height: auto`, `display: block`,
  eigene Schalter (Kästchen orange = an) statt md-checkbox.
- Lauf 6 ✅: Fenster so lang wie der Inhalt, Schalter richtig (Sebastian). **M5.2 UI-App bestätigt.**

### M5.3 Budget und Qualitätsstufen – Bau 1: Zusammenführen (2026-11-07)
- KI-Verkehr auf später verschoben (Sebastian).
- Konzept „Budget“: alte, stabile Ablagerungen in eine gebackene Ebene zusammenführen, falls die API das kann.
- Prüfung im Code, wofür `self.layers` gebraucht wird:
  - volles Neu-Backen (`R:rebake`) nur bei leerer Liste (`R.new`, `R:clear`, `initBake`)
  - Waschen backt nur Schäden neu obenauf (`R:erase`, `isKeep` = `R.isDamage`)
  - Trocknen liest nur nasse Layer und Schäden in der Nähe (`R:dry`)
  → trockener Dreck und Radierer werden nach dem Backen nie wieder gelesen. Die Textur ist die gebackene Ebene.
- Bau: `R:retire()` nimmt trockenen Dreck und Radierer aus der Liste (nach erase und dry); `R:commit` legt trockenen
  Dreck gar nicht erst in die Liste. Zähler `baked` („nur in der Textur“) in `status()`. Budget 500 zählt damit nur
  noch Schäden und nassen Dreck. Erwartung: keine sichtbare Änderung, Ebenen-Zahl bleibt klein.
- Lauf 1 ✅ (Sebastian: Dreck, Waschen, Trocknen wie vorher, Kratzer bleiben). Log 12:18:20: 53 Ebenen in der Liste,
  257 nur in der Textur; 12:20:32: 61 / 261. Bake Ø 0.86 ms.
- ❗ Messung: Waschschritt 110–133 ms bei 55 Kratzern neu darüber (vorher 11 Kratzer: 21–27 ms) → ≈ 2 ms je Schaden,
  ein Ruckler pro Waschschritt. Trocknen max 59 ms. Nächster Fix nach den Qualitätsstufen.
- Bau 2 Qualitätsstufen (Sebastian: „genau so wie vorgeschlagen“): `R.QUALITY` low 1024×512 / 200, medium
  2048×1024 / 500, high 4096×2048 / 800 (Auflösung / Schaden-Budget). 4096×2048 nutzt auch der Vanilla-Editor
  (`editor/api/dynamicDecals.lua:1475`). Wechsel legt die Projektionen neu an (`R:destroy`: setEnabled(false), Referenz
  weg wie `dynamicDecals.lua:3066`) und löscht dabei Dreck und Kratzer. App: Auswahl low/medium/high.
- Lauf 2 (Gavril D-Serie, 2026-11-07): kaum sichtbarer Unterschied zwischen low und high, je höher desto mehr
  Ruckeln (Sebastian). Messung:
  - Bake je Decal: medium Ø ≈ 0.8–2.9 ms (Log 12:28:52–57), **high Ø 6.99 ms, max 8.51 ms** (318 Decals, Status
    12:33:05) → etwa 8× teurer, bei 4 synthetischen pro Frame bis 35 ms.
  - Neu anlegen: low ≈ 10–12 ms, medium ≈ 14–19 ms, high ≈ 45 ms (einmalig).
  - Frametime (high): arbeitet Ø 11.4 ms / Leerlauf Ø 11.9 ms, Leerlauf max 220 ms, render:update max 46 ms.
- Folgerung: high bringt optisch nichts und kostet viel → Vorschlag an Sebastian: high streichen.
- Entscheidung (Sebastian): **Qualitätsstufen ganz weglassen**, fest 2048×1024 und Budget 500. Abweichung vom Konzept
  („Qualitätsstufen niedrig, mittel und hoch“). Entfernt aus settings.lua, render.lua, main.lua und der App.
  Alte `quality`-Einträge in grit.json werden beim Laden ignoriert (`coerce` → nil).

### M5.3, Bau 3: Schäden in eigener Ebene (Weg A, 2026-11-07)
- Entscheidung Sebastian: eigenes Texturpaar für Schäden, **Dreck über Kratzern** (Waschen legt sie frei).
- Bau:
  - render.lua: zweites Paar `@GritDamage` / `@GritDamageMask` (`dcolor`, `dmask`). `commit` backt Schäden dort hinein,
    Dreck ins alte Paar. `erase` backt nur noch den Radierer in die Dreck-Maske (kein Neu-Backen), `dry` färbt keine
    Schäden mehr neu. In der Liste bleiben nur noch nasse Layer; alles andere steckt nur in der Textur.
  - main.lua: Skin-Material bekommt zwei Stages, Schäden in Stage s, Dreck in s+1 (höhere Stage liegt oben –
    Annahme, im Test prüfen). Nur eine Stage frei (`activeLayers` 3) → nur Dreck, Warnung im Log.
- Erwartung: Waschschritt nur noch der Radierer (≈ 20 ms vorher ohne Kratzer → messen), Trocknen ohne Neu-Färben.
- Folge der Entscheidung: ein neuer Kratzer auf schon dreckigem Lack liegt UNTER dem Dreck und ist erst nach dem
  Waschen zu sehen.
- Lauf 1 (ETK): Dreck liegt über den Kratzern, Waschen legt sie frei ✅; kein Ruckeln beim Waschen ✅ (Sebastian).
  Messung: Waschschritt **0.5–1.1 ms** (vorher 110–133 ms bei 55 Kratzern). Trocknen Ø 1.22 ms, max 10.3 ms (vorher max
  59 ms). Bake Ø 1.05 ms. Liste: 100 Ebenen (alle nass/halb), 241 nur in der Textur.
- Kratzer auf Dreck kratzt den Dreck weg: „erstmal nicht, aber merken“ (Sebastian).
- ❌ Nach Strg+L ganzes Auto blau gefleckt (Screenshot 12-44-07, Datenreste), weg nach dem Neuspawn 12:44:10 bzw. dem
  ersten Dreck. Grundebene war schwarz mit Alpha 0 → Änderung: Alpha 1, damit die Fill-Ebene alte Inhalte überschreibt.
- Lauf 2: kein Flecktarn mehr nach mehrfach Strg+L ✅, Lack normal ✅ (Sebastian).
- Covet (12:50, Screenshots 12-51-40/44): Stoßstangen vorne und hinten großflächig hellgrau/weiß mit treppenförmiger
  schräger Kante (grobe Texel). Davor: Riss-Ereignisse an beiden Stoßstangen (Haar/Netz, y = ±1.05/−1.43) und
  Schrammen links vorne (x ≈ 1.1–1.2). Treppenkante = Grenze einer UV-Fläche mit wenig Texeln → Verdacht wie beim ETK:
  Stoßstange teilt/streckt UVs. Unklar, ob Risse oder Kratzer. Test: testScratch an der Seite ohne Crash,
  und Crash mit Rissen aus.
- Lauf 3: weder Testkratzer (links, along 0.1/0.5/0.9, z = Mitte) noch Frontal-Crash nur mit Rissen bzw. nur mit
  Kratzern machen die Stoßstangen weiß (Sebastian). Nebenbefund: Haarrisse am Heck (n20–n22, y 1.05, z 0.10) kommen
  5 s nach jedem Laden ohne Crash (Delle 0.03–0.04 beim Einfedern?).
- Unterschied zum Auftreten 12:50:50: lange Schramme links an der Wand mit Rissen an der **Seite** und Normale −y
  (Netz n317 pos(1.21,−0.33,0.75), n321 pos(1.23,−0.33,0.66), Haar n323 pos(1.14,−0.43,0.71)). Neuer Befehl
  `grit_main.testAt(kind, x,y,z, nx,ny,nz)` stellt einzelne Log-Einträge nach.
- Lauf 4: `testAt` mit den vier Log-Einträgen: nichts weiß. Erst beim langen Schrammen **rechts** mit ≈ 60 km/h
  wieder weiß (Sebastian). Log 13:00:03–20: 7 Netz-Risse links (Bruch), danach `delleMax` steigt stetig von 0.45 auf
  **118 m** → ein Kunststoffteil ist abgerissen und wurde mitgeschleift (Lage relativ zum Referenzknoten).
  Jeder 3-cm-Schritt gab ein Riss-Ereignis (`riss:delle` laufend, bis maxEvents 80) – Risse mit Positionen weit
  weg bzw. auf dem verbogenen Teil. Verdacht: viele Netz-Risse (grau, Stärke 0.9) decken die Stoßstange flächig.
- Fix sensor.lua: ab `DENT_MAX` 0.4 m gilt der Knoten als abgerissen (keine Risse mehr, Diagnose
  `delle-abgerissen`); Messung erst nach `DENT_SETTLE` 2 s, Lage dann als Ausgangslage (gegen die Haarrisse am Heck
  nach jedem Laden).
- Lauf 5: Stoßstangen bleiben weiß, mit und ohne Risse (Sebastian) → nicht die Risse. Screenshot 13-04-15: vordere
  Stoßstange untere Hälfte grau mit Treppenkante. Nebenbefund 13-03-18: Covet lila/schwarz gefleckt im Strg+L-Fenster
  (vor „Grit geladen“, bekannter M6-Punkt).
- Diagnose gebaut: `grit_main.uvCheck()` backt eine UV-Karte (`mod/art/grit/uvcheck.png`, Rot = u, Grün = v,
  Schachbrett 32 px; erzeugt von gen_textures.ps1) als Textur-Füllung (Layer type 2, Felder wie
  `editor/api/dynamicDecals.lua:1232-1243,307-315`) voll deckend ins Schaden-Paar. Gleiche Farbe auf zwei Teilen =
  gleiche UV-Stelle.
- Lauf 6 `uvCheck` (Covet, Screenshots 13-08-22/25/29/33), Farbe = UV1-Stelle (Rot = u, Grün = v):
  - linke Seite grün/türkis/blau (u klein, v groß), rechte Seite rot/lila/magenta (u groß, v klein) → Seiten getrennt.
  - **vordere und hintere Stoßstange: dasselbe Muster grün | türkis | grün** in großen Kästchen, also dieselbe
    UV1-Fläche, und diese liegt im Farbbereich der linken Seite (vorne am Kotflügel/Radlauf ebenfalls grün/türkis).
  - Grill und Kennzeichenleiste oliv (einheitlich, UV auf einen Punkt gestaucht).
  → Die Stoßstangen teilen sich UV1 untereinander und vermutlich mit einem Stück der linken Seite, bei geringer
  Texeldichte (große Kästchen, daher die Treppenkante). Ein Kratzer auf einer dieser Flächen erscheint auf allen.
  Das ist eine Eigenschaft des Modells (UV1 = Dynamic-Decal-UV), nicht von Grit. Prüfbar mit dem Vanilla-Decal-Editor.
- Entscheidung (Sebastian): als bekannte Einschränkung in die README, ohne Gegenprobe im Vanilla-Editor.

## M6 Release

### Bau 1: Skin beim Entladen/Neuladen neutralisieren
- Strg+L ruft vor dem Neuladen `exportPersistentData` → `serializePackages` → `onSerialize` jeder Extension
  (`ge/main.lua:1267-1270`, `common/utils.lua:995-1008`, `common/extensions.lua:993-995`). Entladen ruft
  `onExtensionUnloaded` (`common/extensions.lua:240-241`). Einen eigenen Hook vor Strg+L gibt es sonst nicht.
- Beide schalten die Grit-Stages der Skin-Kopien ab: `activeLayers` = erste Grit-Stage, dann `mat:reload()`
  (wie `editor/api/material.lua:66-68`). Nach dem Laden erkennt `activate` den alten Skin → Neuspawn wie bisher.
- Version 0.5.0 (Sebastian).
- Lauf 1 (Sebastian): ZIP funktioniert wie der Ordner. Deaktivieren im Mod-Manager: Auto sieht unverändert aus
  (Log „Entladen: Grit-Stages an 3 Materialien abgeschaltet“). Strg+L: Hooks laufen (Log „Lua neu laden … 2
  Materialien“, danach „alten Grit-Skin → Neuspawn“), aber erst beim 4. Strg+L ohne Glitches. Screenshot 13-26-04
  (12 s nach „aktiv“, Stapel leer): weiße senkrechte Streifen über die ganze Karosserie, lila Fensterrahmen →
  Datenreste **nach** der frischen Aktivierung, nicht nur in der Lücke. Grundebene (Bake bei Frame 5/60) reicht
  nicht immer; früher verschwand es mit dem ersten echten Decal.
- Lauf 2 (Sebastian): Streifen nach ≈ 10× Strg+L wieder da. `clear()` (Voll-Bake nur Grundebene) half nicht,
  `testScratch("left", 3)` (echte Projektion + Bake) beseitigte sie am ganzen Auto. Der Kratzer geht ins Schaden-Paar,
  die Projektion aber über `self.color` → vermutlich räumt erst `projectDynamicDecals`/der erste echte Decal-Bake
  den Speicher auf.
- Bau 2: `primeTextures` in `attach`: ein unsichtbares Decal (solid.png, Maske schwarz, Stärke 0, 0.2 × 0.2 m, Mitte
  linke Seite) direkt nach dem Aktivieren. Kostet einmal eine Projektion (12–15 ms) pro Spawn, liefert die Vorlage.
- Lauf 3 (Sebastian): beim 3. Strg+L Streifen, weg sobald Dreck kam; linke Seite normal. Log 13:38–13:41: nach
  „aktiv“ **keine** Projektion des Init-Decals (kein „Decal 1“, kein render:update > 8 ms) → die Anfrage kam nie an.
  Vermutung: ein Reset-Hook nach dem Spawn (`onVehicleResetted` → `R:clear`) leert die Warteschlange.
- Bau 3: Init-Decal 10 Frames nach „aktiv“ aus onUpdate anfragen, Log „Init-Decal angefragt“.
- Lauf 4 (Sebastian): ≈ 15× Strg+L ohne Streifen. Einmal kurz eine Hälfte matt, die andere metallisch, normal
  sobald man losfährt. Sebastian: kein weiterer Fokus nötig. → bekannter kleiner Restpunkt.

## Nach Release: Low Hanging Fruits (Notion, 2026-11-13)

Anlass: ein Reupload mit Änderungen (mehr Kratzer-Texturen, Risse, Dreck je Untergrund, „upscaled textures“).
Reupload weder angesehen noch übernommen.

### Kratzer-Varianten – Bau 1 (2026-11-13)
- `tools/gen_textures.ps1`: je Stufe 3 Varianten `scratch_<stufe>_1..3.png` (1024²). Variante 1 = alte Textur,
  per `cmp` bytegleich geprüft (gleicher Seed, `Draw-Streak` unverändert). Neu `Draw-StreakEx` (freier Anfang/Ende,
  Drift = schräge Linie) und `Get-Span` (Linie setzt später ein / bricht ab).
  - leicht 2: wenige, teils abgebrochene Haarlinien; leicht 3: schräges Bündel
  - mittel 2: kräftige Linien teils abgebrochen; mittel 3: schräges Bündel mit zwei kräftigen Linien
  - tief 2: eine breite durchgehende + eine kurze Riefe; tief 3: zwei leicht zusammenlaufende Riefen
- `main.lua`: `SCRATCH.levels[i].textures` (Liste), Auswahl `math.random(#t)`, dazu `up` zu 50 % negiert (180°
  gedreht) → 6 Ansichten pro Stufe. `-dir`: `LuaVec3.__unm` (`lua/common/mathlib.lua:136`).
- Spike 6 bleibt gültig: `R:synth` setzt `decalColorTexturePath = d.texture` pro Anfrage (`render.lua:293`), der
  Zellschlüssel (`render.lua:151-154`) enthält keine Textur.
- `testScratch(side, level, tilt, along, variant)`: 5. Argument wählt die Variante, Log nennt die Textur.
- Texturauflösung bewusst **nicht** erhöht (Schätzung, nicht gemessen): Ein Kratzer (0.12 × 0.3–1.0 m) belegt in der Zieltextur 2048×1024 nur
  einige zehn bis wenige hundert Texel, die 1024²-Quelle ist also schon 3- bis 20-fach überabgetastet. Eine
  2048²-Quelle wäre nicht schärfer, kostet aber das 4-Fache an Speicher. Der Engpass ist die Zielauflösung
  (`render.lua:11`), die Sebastian in M5.3 Lauf 2 bewusst bei 2048×1024 gelassen hat.

### Kratzer-Varianten – Lauf 1 (2026-11-13, Gavril Barstow, schwarz)
- `testScratch("left", 3, 0, 0.3|0.5|0.7, 1|2|3)`, Screenshot 17-25-25: drei verschiedene Riefen-Bilder (3 Riefen /
  lang+kurz / 2 Riefen). Sebastian: Varianten 2 und 3 „gefühlt gleich“ (beide zwei Linien).
- **Bug (alt, nicht durch die Varianten):** Nach Clear all (6×, Log „clear: 0 Ebenen … Voll-Bake 0.4 ms“) bleibt das
  zuletzt **echt projizierte** Decal stehen (Screenshot 17-25-45), die beiden davor sind weg. Vermutung: Live-Vorschau
  der Projektion `self.color`, die `clearBakedTextures`/`bakeLayers` nicht berührt; Alpha 0 der Vorschau reicht nicht.
- Bau 2: `grit_main.testHidePreview("enable"|"project")` (`R:hidePreview`): aus/ein per `setEnabled`
  (`editor/api/dynamicDecals.lua:2242-2243`) bzw. winziges Decal an der letzten Projektionsstelle.
- Lauf 2: `testHidePreview("enable")` und `("project")` → Kratzer bleibt. Vorschau-These damit unwahrscheinlich.
- Lauf 3: `grit_main.exportTex(tag)` (exportTextures, `editor/api/dynamicDecals.lua:2070-2071`). Vor clear: Kratzer
  in `dcolor_d`/`dmask_d` (UV 790–936 × 882–896), `color`/`mask` leer. **Nach clear sind alle vier `_d` leer**, der
  Kratzer ist im Spiel aber noch sichtbar → gebackene Texturen stimmen, die angezeigte (kombinierte) hinkt hinterher.
  `_m`/`_r` überall 255, `_cp` überall 0.
- Editor beim Abschalten: `flushDynamicTextures()` + sofort `combineTextures(set)` (`dynamicDecals.lua:2242-2247`).
  Bau 4: `R:clear` leert die dynamischen Texturen aller vier Projektionen, backt neu und kombiniert sofort.
- Lauf 4 (Sebastian) ✅: ein Kratzer und danach drei Kratzer, Clear all löscht jeweils alles (Log 17:38). Ursache
  also die nicht geleerten dynamischen Texturen bzw. das fehlende sofortige Kombinieren. `testHidePreview` wieder
  entfernt, `exportTex(tag)` bleibt als Diagnose.
