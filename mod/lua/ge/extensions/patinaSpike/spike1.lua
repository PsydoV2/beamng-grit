-- Patina – Spike 1: ein Decal per Code über eine virtuelle Kamera aufs Fahrzeug setzen.
-- Wegwerf-Prototyp. Nutzt nur APIs, die in FINDINGS.md belegt sind.
--
-- Konsole (~), GE-Lua:
--   extensions.load("patinaSpike_spike1")
--   patinaSpike_spike1.info()        -- Fahrzeug, Materialien, Preset vorhanden?
--   patinaSpike_spike1.prepare()     -- Vanilla-Skin "dynamicTextures" setzen (Respawn!)
--   patinaSpike_spike1.start()       -- eigene DecalProjection anlegen, Lackfarbe als Fill-Layer
--   patinaSpike_spike1.decal("left") -- Test-Decal: "left" | "right" | "top" | "front" | "rear"
--   patinaSpike_spike1.paint()       -- Diagnose: Lack-Ebene knallgrün färben
--   patinaSpike_spike1.clear()       -- alle Test-Decals entfernen
--   patinaSpike_spike1.stop()        -- aufräumen, alten Skin zurück (Respawn)

local M = {}
local logTag = "patinaSpike"

local TEST_TEXTURE = "/art/dynamicDecals/textures/digit_basic_1.png"   -- liegt in gameengine.zip
local RESOLUTION = Point2I(2048, 1024)
local UV_LAYER = 1

local state = nil           -- { vehId, proj, textureSet, layers, matIdx }
local skinBeforePrepare = nil

local function L(level, fmt, ...)
  log(level, logTag, string.format(fmt, ...))
end

local function getVeh()
  local veh = getPlayerVehicle(0)
  if not veh then L("E", "Kein Spielerfahrzeug.") end
  return veh
end

local function currentSkin(veh)
  local data = core_vehicle_manager.getPlayerVehicleData()
  local slot = data and data.config and data.config.partsTree and data.config.partsTree.children
    and data.config.partsTree.children["paint_design"]
  local part = slot and slot.chosenPartName
  if not part or part == "" then return nil end
  local prefix = veh.JBeam .. "_skin_"
  if string.startswith(part, prefix) then return string.sub(part, #prefix + 1) end
  return nil
end

local function uid(prefix)
  return string.format("%s-%04X", prefix, math.random(0, 0xFFFF))
end

-- Pointer/Transform jedes Frame aktualisieren, wie editor_api_dynamicDecals app.onUpdate (dynamicDecals.lua:1492)
local function refresh(veh)
  local p = state.proj
  veh:setTextureSet("@DynamicTexture", state.textureSet)
  p:setShape(veh:getDecalProjectionShape())
  p:setWorldTransform(veh:getRefNodeMatrix())
  p:setTransform(veh:getRefNodeMatrix():copy():setPosition(vec3(0, 0, 0)):inverse())
end

local function rebake()
  local veh = getVeh()
  if not veh or not state then return end
  refresh(veh)
  local t = hptimer()
  state.proj:clearBakedTextures()
  local res = state.proj:bakeLayers(state.layers, veh.jbeam)
  local ms = t:stopAndReset()
  L("I", "bakeLayers: %d Layer, %.2f ms, status=%s", #state.layers, ms, res and tostring(res.status) or "nil")
  local code = res and res.status and res.status.code
  if code ~= 0 then L("W", "bake result: %s", dumps(res)) end
end

-------------------------------------------------------------------------------

M.info = function()
  local veh = getVeh(); if not veh then return end
  L("I", "Fahrzeug: %s (id %d), Skin: %s", veh.jbeam, veh:getID(), tostring(currentSkin(veh)))
  local preset = scenetree.findObject(veh.jbeam .. ".skin.dynamicTextures")
  L("I", "Preset-Material '%s.skin.dynamicTextures': %s", veh.jbeam, preset and "vorhanden" or "FEHLT")
  local p = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  p:setShape(veh:getDecalProjectionShape())
  local names = p:getShapeMaterialNames()
  local list = {}
  for k, n in pairs(names) do table.insert(list, string.format("[%s] %s", tostring(k), n)) end
  table.sort(list)
  L("I", "Shape-Materialien (%d):\n  %s", #list, table.concat(list, "\n  "))
  local aabb = veh:getSpawnLocalAABB()
  L("I", "SpawnLocalAABB min=%s max=%s", tostring(aabb.minExtents), tostring(aabb.maxExtents))
end

M.prepare = function()
  local veh = getVeh(); if not veh then return end
  skinBeforePrepare = currentSkin(veh)
  L("I", "Setze Skin dynamicTextures (vorher: %s). Fahrzeug wird neu gespawnt, danach start().", tostring(skinBeforePrepare))
  core_vehicle_partmgmt.setSkin("dynamicTextures")
end

M.start = function()
  local veh = getVeh(); if not veh then return end
  if currentSkin(veh) ~= "dynamicTextures" then
    L("W", "Aktueller Skin ist '%s', nicht dynamicTextures. Erst prepare() ausführen.", tostring(currentSkin(veh)))
  end

  local proj = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  proj:setShape(veh:getDecalProjectionShape())

  -- Material wählen wie dynamicDecals.lua:1414 (Name = jbeam), Fallback *main / *body
  local matIdx, fallback
  for k, n in pairs(proj:getShapeMaterialNames()) do
    if n == veh.jbeam then matIdx = k end
    if not fallback and (string.endswith(n, "main") or string.endswith(n, "body")) then fallback = k end
  end
  matIdx = matIdx or fallback
  if not matIdx then L("E", "Kein passendes Material gefunden, siehe info()."); return end
  proj:clearMaterialIdx()
  proj:addMaterialIdx(matIdx)

  proj:setEnabled(true)   -- wie ui/liveries.lua:85 (api.setEnabled(true))
  state = { vehId = veh:getID(), proj = proj, textureSet = proj:getTextureSet(), layers = {}, matIdx = matIdx,
            pending = nil, dumped = false }

  -- Das Preset ersetzt den Lack → Lackfarbe als unterste Fill-Ebene (wie ui/liveries/fill.lua)
  table.insert(state.layers, {
    type = 1, blendMode = 1, color = veh.color, colorPaletteMapId = 0,
    enabled = true, locked = false, uid = uid("fill"), name = "Patina Fill", children = {},
  })
  rebake()
  L("I", "start(): Projektion aktiv auf Material-Index %s. Jetzt decal(\"left\") usw.", tostring(matIdx))
end

-- Richtungen im Fahrzeug-Koordinatensystem. Welche Achse "links" ist, prüft genau dieser Spike.
local dirs = {
  left  = vec3( 1, 0, 0), right = vec3(-1, 0, 0),
  front = vec3( 0, 1, 0), rear  = vec3( 0,-1, 0),
  top   = vec3( 0, 0,-1),
}

M.decal = function(side, size)
  if not state then L("E", "Erst start()."); return end
  local veh = getVeh(); if not veh then return end
  side = side or "left"
  local dir = dirs[side]; if not dir then L("E", "Unbekannte Seite '%s'", tostring(side)); return end
  size = size or 0.5

  -- virtuelle Kamera: außerhalb der AABB, Blick durch die Mitte auf das Fahrzeug
  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local center = (mn + mx) * 0.5
  local ext = (mx - mn) * 0.5
  local reach = math.abs(dir.x) * ext.x + math.abs(dir.y) * ext.y + math.abs(dir.z) * ext.z + 1.0
  local camPos = center - dir * reach
  local up = math.abs(dir.z) > 0.9 and vec3(0, 1, 0) or vec3(0, 0, 1)
  local q = quatFromDir(dir, up)
  local camM = QuatF(q.x, q.y, q.z, q.w):getMatrix()
  camM:setPosition(camPos)

  local p = state.proj
  p:setDecalTexturePath("color", TEST_TEXTURE)
  p.decalColor = Point4F(1, 0.15, 0.1, 1)
  p.decalScale = vec3(size, 1.0, size)
  p.decalRotation = 0
  p.useSurfaceNormal = false

  -- Der Treffer entsteht erst im GPU-Durchlauf projectDynamicDecals (dynamicDecals.lua:3036), den der
  -- Editor jedes Frame mit derselben Kamera ausführt. Deshalb: einige Frames projizieren, dann auslesen.
  state.pending = { side = side, dir = dir, camPos = camPos, camM = camM, projM = getCameraProjMatrix(), frames = 0 }
  L("I", "decal(%s): eingereiht, Auswertung in den nächsten Frames …", side)
end

local FRAMES_BEFORE_READ = 3
local FRAMES_MAX = 30

local function hitInfo(data, req)
  local hit = data and data.decalPos and vec3(data.decalPos)
  if not hit or hit.x ~= hit.x or math.abs(hit.x) > 1e6 or math.abs(hit.y) > 1e6 or math.abs(hit.z) > 1e6 then
    return nil
  end
  local toHit = hit - req.camPos
  local along = toHit:dot(req.dir)
  local off = (toHit - req.dir * along):length()
  return hit, off, along
end

-- Strahl durch die Bildmitte statt durch die Maus (ui/liveries/decal.lua:604-609, Flag UseMousePos = 1<<2)
local USE_MOUSE_POS = bit.lshift(1, 2)
local function centerCursor(p)
  if bit.band(p:getSettings(), USE_MOUSE_POS) == USE_MOUSE_POS then
    p:toggleSetting(USE_MOUSE_POS)
  end
  p.cursorPosition = Point2F(0.5, 0.5)
end

local function processPending(veh)
  local req = state.pending
  local p = state.proj
  centerCursor(p)
  p:projectDynamicDecals(req.camM, req.projM)
  req.frames = req.frames + 1
  if req.frames < FRAMES_BEFORE_READ then return end

  local ok, data = pcall(function() return p:getDecalData(req.camM, req.projM) end)
  if not ok then L("E", "getDecalData fehlgeschlagen: %s", tostring(data)); state.pending = nil; return end

  local hit, off, along = hitInfo(data, req)
  if not hit then
    if req.frames < FRAMES_MAX then return end
    L("W", "decal(%s): nach %d Frames kein gültiger Treffer. decalPos=%s cursorUv=%s settings=%s",
      req.side, req.frames, tostring(data and data.decalPos), dumps(data and data.cursorPosScreenUv), tostring(p:getSettings()))
    if not state.dumped then L("I", "decalData:\n%s", dumps(data)); state.dumped = true end
    p:flushDynamicTextures()
    state.pending = nil
    return
  end

  L("I", "decal(%s): Treffer nach %d Frames: hit=%s, Abstand zum Strahl=%.3f m, Tiefe=%.2f m, cursorUv=%s %s",
    req.side, req.frames, tostring(hit), off, along, dumps(data.cursorPosScreenUv), off < 0.05 and "OK" or "ABWEICHUNG")
  if not state.dumped then L("I", "decalData:\n%s", dumps(data)); state.dumped = true end

  data.uid = uid("decal")
  data.name = "Patina Test " .. req.side
  data.enabled = true
  data.locked = false
  data.children = {}
  table.insert(state.layers, data)

  p:flushDynamicTextures()   -- Live-Vorschau verwerfen, wie api.setEnabled(false)
  state.pending = nil
  rebake()
end

-- Diagnose: färbt die Fill-Ebene um. Wird das Auto grün, kommt die Render-Kette sichtbar an.
M.paint = function(r, g, b)
  if not state then L("E", "Erst start()."); return end
  state.layers[1].color = Point4F(r or 0, g or 1, b or 0, 1)
  rebake()
  L("I", "paint(): Fill-Farbe gesetzt.")
end

M.clear = function()
  if not state then return end
  local fill = state.layers[1]
  state.layers = { fill }
  rebake()
end

M.stop = function()
  state = nil
  local veh = getPlayerVehicle(0)
  if veh and currentSkin(veh) == "dynamicTextures" then
    core_vehicle_partmgmt.setSkin(skinBeforePrepare)   -- nil = kein Skin
  end
  skinBeforePrepare = nil
  L("I", "stop(): aufgeräumt.")
end

M.onUpdate = function()
  if not state then return end
  local veh = getPlayerVehicle(0)
  if not veh or veh:getID() ~= state.vehId then return end
  refresh(veh)
  if state.pending then processPending(veh) end
  if not state then return end
  state.proj:combineTextures(state.textureSet)   -- wie M.onUpdate_ (dynamicDecals.lua:3040)
end

M.onVehicleDestroyed = function(vid)
  if state and state.vehId == vid then state = nil; L("I", "Fahrzeug entfernt, Spike-Status verworfen.") end
end

M.onVehicleReplaced = function(vid)
  if state and state.vehId == vid then state = nil; L("I", "Fahrzeug ersetzt, bitte start() erneut.") end
end

return M
