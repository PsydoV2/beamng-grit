-- Patina – Spike 2 (Weg A′): Dynamic Texture als ZUSÄTZLICHE Material-Ebene über dem Lack.
-- Kein Preset-Material, kein paint_design-Skin. Wegwerf-Prototyp.
--
-- Konsole (GE - Lua), Fahrzeug OHNE Lackierung/Skin:
--   extensions.load("patinaSpike_spike2")
--   patinaSpike_spike2.start()             -- Projektion + Stage auf dem Lack-Material
--   patinaSpike_spike2.decal("left")       -- "left" | "right" | "top" | "front" | "rear"
--   patinaSpike_spike2.opacity("Mask")     -- Deckkraft-Quelle: "Mask" (Standard) | "BaseColor" | "Metallic" | "Roughness" | "none"
--   patinaSpike_spike2.color(r, g, b)      -- Farbe der nächsten Decals
--   patinaSpike_spike2.strength(0.5)       -- Deckkraft der nächsten Decals (Grauwert in der Maske)
--   patinaSpike_spike2.prefix("@DynamicTexture")  -- Textur-Set-Name umschalten (Standard "@PatinaTexture")
--   patinaSpike_spike2.status()            -- aktuelle Material-Felder ausgeben
--   patinaSpike_spike2.respawn()           -- Auto mit geändertem Material neu spawnen (falls reload() nicht reicht)
--   patinaSpike_spike2.stop()              -- Material wiederherstellen

local M = {}
local logTag = "patinaSpike2"

local TEST_TEXTURE = "/art/dynamicDecals/textures/digit_basic_1.png"
local RESOLUTION = Point2I(2048, 1024)
local UV_LAYER = 1
local USE_MOUSE_POS = bit.lshift(1, 2)
local FRAMES_BEFORE_READ, FRAMES_MAX = 3, 30

-- Fahrzeug-Koordinatensystem (Spike 1): −x = rechts, −y = vorne. dir = Blickrichtung der Kamera.
local dirs = {
  left  = vec3(-1, 0, 0), right = vec3( 1, 0, 0),
  front = vec3( 0, 1, 0), rear  = vec3( 0,-1, 0),
  top   = vec3( 0, 0,-1),
}

-- Felder der Patina-Stage. Gespeichert/wiederhergestellt pro Material.
local STAGE_FIELDS = { "baseColorMap", "diffuseMapUseUV", "opacityMap", "opacityMapUseUV",
  "metallicFactor", "roughnessFactor", "instanceDiffuse", "baseColorFactor" }

local state = nil

local function L(level, fmt, ...) log(level, logTag, string.format(fmt, ...)) end
local function uid(p) return string.format("%s-%04X", p, math.random(0, 0xFFFF)) end

local function getVeh()
  local veh = getPlayerVehicle(0)
  if not veh then L("E", "Kein Spielerfahrzeug.") end
  return veh
end

local MASK_PREFIX = "@PatinaMask"

local function refreshProj(veh, p, prefix, set)
  veh:setTextureSet(prefix, set)
  p:setShape(veh:getDecalProjectionShape())
  p:setWorldTransform(veh:getRefNodeMatrix())
  p:setTransform(veh:getRefNodeMatrix():copy():setPosition(vec3(0, 0, 0)):inverse())
end

local function refresh(veh)
  refreshProj(veh, state.proj, state.prefix, state.textureSet)
  refreshProj(veh, state.mask.proj, MASK_PREFIX, state.mask.textureSet)
end

-- Masken-Layer = dieselben Layer, Farbe = Weiß × Stärke. Grundebene bleibt schwarz (= unsichtbar).
local function maskLayers()
  local out = {}
  for i, l in ipairs(state.layers) do
    if i == 1 then
      out[i] = l
    else
      local m = shallowcopy(l)
      local s = l.patinaStrength or 1
      m.color = Point4F(s, s, s, 1)
      m.uid = l.uid .. "-m"
      out[i] = m
    end
  end
  return out
end

local function bakeOne(p, layers, jbeam)
  p:clearBakedTextures()
  local res = p:bakeLayers(layers, jbeam)
  return res and res.status and res.status.code
end

local function rebake()
  local veh = getVeh(); if not veh or not state then return end
  refresh(veh)
  local t = hptimer()
  local c1 = bakeOne(state.proj, state.layers, veh.jbeam)
  local c2 = bakeOne(state.mask.proj, maskLayers(), veh.jbeam)
  local ms = t:stopAndReset()
  L("I", "bakeLayers (Farbe + Maske): %d Layer, %.2f ms, code=%s/%s", #state.layers, ms, tostring(c1), tostring(c2))
end

-- Stage schreiben ---------------------------------------------------------------

local function applyStage()
  local mat, stage = state.mat, state.stage
  mat:setField("baseColorMap", stage, state.prefix .. "BaseColor")
  mat:setField("diffuseMapUseUV", stage, tostring(UV_LAYER))
  local opacityTex = ""
  if state.opacitySrc == "Mask" then
    opacityTex = MASK_PREFIX .. "BaseColor"
  elseif state.opacitySrc ~= "none" then
    opacityTex = state.prefix .. state.opacitySrc
  end
  mat:setField("opacityMap", stage, opacityTex)
  mat:setField("opacityMapUseUV", stage, tostring(UV_LAYER))
  mat:setField("metallicFactor", stage, "0")
  mat:setField("roughnessFactor", stage, "1")
  mat:setField("instanceDiffuse", stage, "0")
  if tonumber(mat:getField("activeLayers", 0)) < stage + 1 then
    mat:setField("activeLayers", 0, tostring(stage + 1))
  end
  mat:reload()
  L("I", "Stage %d auf '%s': baseColor=%sBaseColor, opacity=%s",
    stage, state.matName, state.prefix, opacityTex == "" and "(keine)" or opacityTex)
end

M.status = function()
  if not state then L("E", "Erst start()."); return end
  local mat = state.mat
  local lines = { string.format("activeLayers=%s", tostring(mat:getField("activeLayers", 0))) }
  for s = 0, 3 do
    for _, f in ipairs(STAGE_FIELDS) do
      local v = mat:getField(f, s)
      if v and v ~= "" then table.insert(lines, string.format("  [%d] %s = %s", s, f, v)) end
    end
  end
  L("I", "Material '%s':\n%s", state.matName, table.concat(lines, "\n"))
end

-- Mesh-Materialnamen sind mapTo-Namen. Das Material-OBJEKT heißt oft anders (etki → etki_main).
-- scenetree.findObject("etki") fand in Lauf 1 ein Legacy-Material mit mapTo "etki_old".
local function resolveMaterial(veh, meshName)
  local used = veh:getMaterialNames() or {}   -- wie editor/materialEditor.lua:1004
  L("I", "veh:getMaterialNames() (%d): %s", #used, table.concat(used, ", "))
  local candidates = {}
  for _, n in ipairs(used) do
    local m = scenetree.findObject(n)
    if m and m:getField("mapTo", 0) == meshName then table.insert(candidates, n) end
  end
  if #candidates == 0 then
    for _, n in ipairs(scenetree.findClassObjects("Material") or {}) do
      local m = scenetree.findObject(n)
      if m and m:getField("mapTo", 0) == meshName then table.insert(candidates, n) end
    end
  end
  L("I", "Materialobjekte mit mapTo='%s': %s", meshName, table.concat(candidates, ", "))
  return candidates[1] and scenetree.findObject(candidates[1]), candidates[1]
end

-- Frische Dynamic Textures enthalten Datenreste (Lauf 3: rechte Seite rot nach start()).
-- Deshalb immer zuerst eine schwarze, transparente Fill-Ebene backen (Fill-Layer wie ui/liveries/fill.lua).
-- Lauf 4: Mit opacity("Metallic") wurde das ganze Auto matt schwarz → die Grundebene schreibt Metallic = 1.
-- Varianten für den Metallic-Hintergrund 0:
--   "normal" Fill, blendMode Normal (Lauf 4)
--   "clear"  Fill, blendMode Clear (0)
--   "zero"   Fill, Normal + metallicIntensity/roughnessIntensity = 0 (Felder wie bei Decal-Layern)
local baseMode = "normal"   -- schwarz/Normal ist belegt unsichtbar bei Helligkeits-Deckkraft (Lauf 4, Frage 0)
M._baseLayer = function()
  local l = { type = 1, blendMode = 1, color = Point4F(0, 0, 0, 0), colorPaletteMapId = 0,
              enabled = true, locked = false, uid = uid("base"), name = "Patina Base", children = {} }
  if baseMode == "clear" then l.blendMode = 0 end
  if baseMode == "zero" then l.metallicIntensity, l.roughnessIntensity = 0, 0 end
  return l
end

M.base = function(mode)
  baseMode = mode or "clear"
  if state then state.layers[1] = M._baseLayer(); rebake() end
  L("I", "base(): Grundebene = %s", baseMode)
end

M.start = function(meshName)
  local veh = getVeh(); if not veh then return end
  if state then L("W", "Läuft schon, erst stop()."); return end

  meshName = meshName or veh.jbeam
  local mat, matObjName = resolveMaterial(veh, meshName)
  if not mat then L("E", "Kein Materialobjekt mit mapTo '%s'.", meshName); return end
  local matName = meshName
  local layers = tonumber(mat:getField("activeLayers", 0)) or 1
  if layers >= 4 then L("E", "Material '%s' hat schon 4 Ebenen.", matName); return end
  local stage = layers   -- erste freie Stage (0-basiert)

  local proj = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  proj:setShape(veh:getDecalProjectionShape())
  local matIdx
  for k, n in pairs(proj:getShapeMaterialNames()) do if n == matName then matIdx = k end end
  if not matIdx then L("E", "Material '%s' ist nicht im Shape.", matName); return end
  proj:clearMaterialIdx()
  proj:addMaterialIdx(matIdx)
  proj:setEnabled(true)

  -- zweite Projektion nur für die Deckkraft-Maske
  local mproj = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  mproj:setShape(veh:getDecalProjectionShape())
  mproj:clearMaterialIdx()
  mproj:addMaterialIdx(matIdx)
  mproj:setEnabled(true)

  local backup = { activeLayers = mat:getField("activeLayers", 0) }
  for _, f in ipairs(STAGE_FIELDS) do backup[f] = mat:getField(f, stage) end

  state = {
    vehId = veh:getID(), proj = proj, textureSet = proj:getTextureSet(), layers = { M._baseLayer() },
    mask = { proj = mproj, textureSet = mproj:getTextureSet() },
    mat = mat, matName = matName .. " (Objekt " .. matObjName .. ")", meshName = meshName, stage = stage, backup = backup,
    prefix = "@PatinaTexture", opacitySrc = "Mask", pending = nil,
  }
  applyStage()
  rebake()
  L("I", "start(): Material '%s' (Index %d), Stage %d. Jetzt decal(\"left\").", matName, matIdx, stage)
end

M.opacity = function(src)
  if not state then L("E", "Erst start()."); return end
  state.opacitySrc = src or "BaseColor"
  applyStage()
end

M.prefix = function(p)
  if not state then L("E", "Erst start()."); return end
  state.prefix = p or "@PatinaTexture"
  applyStage()
  rebake()
end

-- Decal setzen (wie Spike 1, mit korrigierten Achsen und 10 cm Projektionstiefe) -----------

M.decal = function(side, size)
  if not state then L("E", "Erst start()."); return end
  local veh = getVeh(); if not veh then return end
  side = side or "left"
  local dir = dirs[side]; if not dir then L("E", "Unbekannte Seite '%s'", tostring(side)); return end
  size = size or 0.5

  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local center, ext = (mn + mx) * 0.5, (mx - mn) * 0.5
  local reach = math.abs(dir.x) * ext.x + math.abs(dir.y) * ext.y + math.abs(dir.z) * ext.z + 1.0
  local camPos = center - dir * reach
  local q = quatFromDir(dir, math.abs(dir.z) > 0.9 and vec3(0, 1, 0) or vec3(0, 0, 1))
  local camM = QuatF(q.x, q.y, q.z, q.w):getMatrix()
  camM:setPosition(camPos)

  local p = state.proj
  p:setDecalTexturePath("color", TEST_TEXTURE)
  local c = state.color or { 0.35, 0.22, 0.1 }  -- Standard: dreckbraun
  p.decalColor = Point4F(c[1], c[2], c[3], 1)
  if state.metallic then p.metallicIntensity = state.metallic end
  if state.roughness then p.roughnessIntensity = state.roughness end
  p.decalScale = vec3(size, 0.1, size)         -- y = Projektionstiefe
  p.decalRotation = 0
  p.useSurfaceNormal = false
  state.pending = { side = side, dir = dir, camPos = camPos, camM = camM, projM = getCameraProjMatrix(), frames = 0 }
end

local function processPending()
  local req, p = state.pending, state.proj
  if bit.band(p:getSettings(), USE_MOUSE_POS) == USE_MOUSE_POS then p:toggleSetting(USE_MOUSE_POS) end
  p.cursorPosition = Point2F(0.5, 0.5)
  p:projectDynamicDecals(req.camM, req.projM)
  req.frames = req.frames + 1
  if req.frames < FRAMES_BEFORE_READ then return end

  local ok, data = pcall(function() return p:getDecalData(req.camM, req.projM) end)
  local hit = ok and data and data.decalPos and vec3(data.decalPos)
  local valid = hit and hit.x == hit.x and hit:length() < 1e6
  if not valid then
    if req.frames < FRAMES_MAX then return end
    L("W", "decal(%s): kein Treffer nach %d Frames.", req.side, req.frames)
    p:flushDynamicTextures(); state.pending = nil
    return
  end
  local toHit = hit - req.camPos
  local along = toHit:dot(req.dir)
  L("I", "decal(%s): Treffer nach %d Frames, Abstand zum Strahl %.3f m", req.side, req.frames,
    (toHit - req.dir * along):length())

  data.uid, data.name, data.enabled, data.locked, data.children = uid("decal"), "Patina " .. req.side, true, false, {}
  data.patinaStrength = state.strength or 1
  table.insert(state.layers, data)
  p:flushDynamicTextures()
  state.pending = nil
  rebake()
end

-- Farbe und Intensitäten für die NÄCHSTEN Decals (zum Testen, welcher Kanal die Deckkraft steuert)
M.color = function(r, g, b)
  if not state then L("E", "Erst start()."); return end
  state.color = { r or 1, g or 1, b or 1 }
  L("I", "color(): nächste Decals in %.2f/%.2f/%.2f", state.color[1], state.color[2], state.color[3])
end

-- Deckkraft der NÄCHSTEN Decals (0..1), landet als Grauwert in der Maske
M.strength = function(s)
  if not state then L("E", "Erst start()."); return end
  state.strength = s or 1
  L("I", "strength(): %.2f", state.strength)
end

M.intensity = function(metallic, roughness)
  if not state then L("E", "Erst start()."); return end
  state.metallic, state.roughness = metallic, roughness
  L("I", "intensity(): metallic=%s roughness=%s", tostring(metallic), tostring(roughness))
end

M.clear = function()
  if not state then return end
  state.layers = { M._baseLayer() }
  rebake()
end

M.stop = function()
  if not state then return end
  local mat, b = state.mat, state.backup
  for _, f in ipairs(STAGE_FIELDS) do mat:setField(f, state.stage, b[f] or "") end
  mat:setField("activeLayers", 0, b.activeLayers or "1")
  mat:reload()
  L("I", "stop(): Material '%s' wiederhergestellt.", state.matName)
  state = nil
end

M.onUpdate = function()
  if not state then return end
  local veh = getPlayerVehicle(0)
  if not veh or veh:getID() ~= state.vehId then return end
  refresh(veh)
  if state.pending then processPending() end
  state.proj:combineTextures(state.textureSet)
  state.mask.proj:combineTextures(state.mask.textureSet)
end

M.onVehicleDestroyed = function(vid)
  if state and state.vehId == vid and not state.respawning then M.stop() end
end

-- Test: Greift die Material-Änderung erst, wenn das Fahrzeug mit dem geänderten Material neu gespawnt wird?
-- Respawn mit gleicher Config wie core_vehicle_partmgmt.setSkin (partmgmt.lua:876-880). Status bleibt erhalten.
M.respawn = function()
  if not state then L("E", "Erst start()."); return end
  local veh = getVeh(); if not veh then return end
  local data = core_vehicle_manager.getPlayerVehicleData()
  if not data or not data.config then L("E", "Keine Fahrzeugdaten."); return end
  state.respawning = true
  L("I", "respawn(): Fahrzeug wird mit geänderter Material-Stage neu gespawnt …")
  core_vehicles.replaceVehicle(veh.JBeam, { config = data.config }, veh)
end

M.onVehicleReplaced = function(vid)
  if not state then return end
  if state.respawning then
    state.respawning = false
    local veh = getPlayerVehicle(0)
    if not veh then return end
    state.vehId = veh:getID()
    state.proj:setShape(veh:getDecalProjectionShape())
    state.mask.proj:setShape(veh:getDecalProjectionShape())
    rebake()
    L("I", "respawn(): fertig (id %d), Layer neu gebacken.", state.vehId)
    return
  end
  if state.vehId == vid then M.stop() end
end

M.onExtensionUnloaded = function() M.stop() end

return M
