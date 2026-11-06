-- Patina – Spike 4: Lackierungsmuster + eigener Skin-Slot "patina" (Basis Spike 3 inkl. Lasttest). Wegwerf-Prototyp.
-- Misst bei n Decals in s Sekunden: Frametime (Grundlinie vs. Last), Bake-Zeit, Projektionskosten.
-- Modus "inc":  nur das neue Decal dazubacken, ohne clear (wie der Editor: addDecal_Redo → bakeLayers({decal}),
--               editor/api/dynamicDecals.lua:1091-1095).
-- Modus "full": jedes Mal clear + alle Layer (wie reprojectLayers, dynamicDecals.lua:1647-1651).
--
-- Konsole (GE - Lua):
--   patinaSpike_spike4.load(200, 20, "inc")   -- Lasttest: 200 Decals in 20 s, Ergebnis ins Log
--   patinaSpike_spike4.load(200, 20, "full")
--   patinaSpike_spike4.rebakeFull()          -- alles neu backen (Vergleich inc ↔ full, Bild muss gleich bleiben)
--   extensions.load("patinaSpike_spike4")
--   patinaSpike_spike4.start()          -- Skin anlegen, Fahrzeug lädt einmal neu, danach bereit
--   patinaSpike_spike4.coat2(0.6)       -- 5 große Decals = gleichmäßiger Dreck
--   patinaSpike_spike4.decal("left")    -- Test-„1“: "left" | "right" | "top" | "front" | "rear"
--   patinaSpike_spike4.export("a")      -- gebackene Texturen als PNG nach <User>/patina_export/a/
--   patinaSpike_spike4.clear()          -- Dreck entfernen
--   patinaSpike_spike4.stop()           -- Skin entfernen, Fahrzeug lädt einmal neu

local M = {}
local logTag = "patinaSpike4"

local TEST_TEXTURE = "/art/dynamicDecals/textures/digit_basic_1.png"
local RESOLUTION = Point2I(2048, 1024)
local UV_LAYER = 1
local COLOR_PREFIX, MASK_PREFIX = "@PatinaTexture", "@PatinaMask"
local USE_MOUSE_POS = bit.lshift(1, 2)
local FRAMES_BEFORE_READ, FRAMES_MAX = 3, 30
local DIRT = { 0.30, 0.20, 0.10 }

local dirs = {   -- Fahrzeug-Koordinatensystem: −x = rechts, −y = vorne (Spike 1)
  left  = vec3(-1, 0, 0), right = vec3( 1, 0, 0),
  front = vec3( 0, 1, 0), rear  = vec3( 0,-1, 0),
  top   = vec3( 0, 0,-1),
}

local state = nil

-- beamng.log wird mit Minuten Verzögerung geschrieben → zusätzlich sofort in eine eigene Datei
-- (Muster: ge/extensions/career/modules/log.lua:22, io.open(..., "a")). Landet im User-Ordner.
local SPIKE_LOG = "/patina_spike.log"
local function L(level, fmt, ...)
  local msg = string.format(fmt, ...)
  log(level, logTag, msg)
  local f = io.open(SPIKE_LOG, "a")
  if f then f:write(string.format("%s|%s|%s\n", os.date("%H:%M:%S"), level, msg)); f:close() end
end
local function uid(p) return string.format("%s-%04X", p, math.random(0, 0xFFFF)) end
local function getVeh()
  local veh = getPlayerVehicle(0)
  if not veh then L("E", "Kein Spielerfahrzeug.") end
  return veh
end

-- Material-Erkennung -------------------------------------------------------------

local function isTrue(v) return v == "1" or v == "true" end

-- lackiert:
--  * Material v1.5: irgendeine Stage hat colorPaletteMap (etki_main/covet_main Stage 0: nullcolormaskR,
--    Skins: eigene Palette). Lauf 1 von 2b: etki_main hat KEIN instanceDiffuse.
--  * Material v1.0 (Legacy): instanceDiffuse.
--  * durchsichtige Materialien (Glas) nie – Lauf 1 erkannte sonst glass_invisible.
local function isPaintable(m)
  if isTrue(m:getField("translucent", 0)) then return false end
  for s = 0, 3 do
    local cp = m:getField("colorPaletteMap", s)
    if cp and cp ~= "" then return true end
  end
  if m:getField("version", 0) ~= "1.5" then
    for s = 0, 3 do if isTrue(m:getField("instanceDiffuse", s)) then return true end end
  end
  return false
end

-- Mesh-Name aus mapTo: "etki" → "etki", Skin "etki.skin.camo" → "etki"
local function meshStem(mapTo)
  return mapTo and mapTo:match("^([^%.]+)") or nil
end

local function findTargets(veh, proj)
  local idxByMesh = {}
  for k, n in pairs(proj:getShapeMaterialNames()) do idxByMesh[n] = k end

  local targets, skipped, seen = {}, {}, {}
  for _, objName in ipairs(veh:getMaterialNames() or {}) do
    local m = not seen[objName] and scenetree.findObject(objName)
    seen[objName] = true
    if m then
      local mapTo = m:getField("mapTo", 0)
      local mesh = idxByMesh[mapTo] and mapTo or meshStem(mapTo)
      local idx = mesh and idxByMesh[mesh]
      if idx and isPaintable(m) then
        local layers = tonumber(m:getField("activeLayers", 0)) or 1
        if layers >= 4 then
          table.insert(skipped, objName .. " (4 Ebenen belegt)")
        else
          table.insert(targets, { obj = m, objName = objName, mesh = mesh, idx = idx, stage = layers })
        end
      end
    end
  end
  return targets, skipped
end

-- Projektionen -------------------------------------------------------------------

local function newProj(veh, targets)
  local p = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  p:setShape(veh:getDecalProjectionShape())
  p:clearMaterialIdx()
  local seen = {}
  for _, t in ipairs(targets) do
    if not seen[t.idx] then p:addMaterialIdx(t.idx); seen[t.idx] = true end
  end
  p:setEnabled(true)
  return p
end

local function refreshProj(veh, p, prefix, set)
  veh:setTextureSet(prefix, set)
  p:setShape(veh:getDecalProjectionShape())
  p:setWorldTransform(veh:getRefNodeMatrix())
  p:setTransform(veh:getRefNodeMatrix():copy():setPosition(vec3(0, 0, 0)):inverse())
end

local function refresh(veh)
  refreshProj(veh, state.color.proj, COLOR_PREFIX, state.color.set)
  refreshProj(veh, state.mask.proj, MASK_PREFIX, state.mask.set)
end

local function baseLayer()   -- schwarz = unsichtbar in der Maske, gegen Datenreste (Spike 2, Lauf 3)
  return { type = 1, blendMode = 1, color = Point4F(0, 0, 0, 0), colorPaletteMapId = 0,
           enabled = true, locked = false, uid = uid("base"), name = "Patina Base", children = {} }
end

-- Der Bake wandelt Layer-Farben sRGB → linear (Export Lauf 4: 0.7 → 116/255 = 0.7^2.2, 0.3 → 18/255).
-- Die Maske ist aber Daten (Deckkraft) → vorher mit 1/2.2 kodieren, damit 0.7 auch 0.7 deckt.
M.gammaFix = true
local function enc(v) return M.gammaFix and math.pow(v, 1 / 2.2) or v end

-- Jeder Patina-Layer trägt patinaColor und patinaStrength. Daraus entstehen beide Stacks.
local function buildStacks()
  local colorStack, maskStack = { baseLayer() }, { baseLayer() }
  for _, l in ipairs(state.layers) do
    local c, s = l.patinaColor, l.patinaStrength
    local cl = shallowcopy(l); cl.color = Point4F(enc(c[1]), enc(c[2]), enc(c[3]), 1); cl.uid = l.uid .. "-c"
    local e = enc(s); local ml = shallowcopy(l); ml.color = Point4F(e, e, e, 1); ml.uid = l.uid .. "-m"
    table.insert(colorStack, cl)
    table.insert(maskStack, ml)
  end
  return colorStack, maskStack
end

local function rebake()
  if not state then return end
  local veh = be:getObjectByID(state.vehId); if not veh then return end
  refresh(veh)
  local cs, ms = buildStacks()
  local t = hptimer()
  state.color.proj:clearBakedTextures()
  local r1 = state.color.proj:bakeLayers(cs, veh.jbeam)
  state.mask.proj:clearBakedTextures()
  local r2 = state.mask.proj:bakeLayers(ms, veh.jbeam)
  local dt = t:stopAndReset()
  if not state.quiet then
    L("I", "bake: %d Layer, %.2f ms, code=%s/%s", #state.layers, dt,
      tostring(r1 and r1.status and r1.status.code), tostring(r2 and r2.status and r2.status.code))
  end
  return dt
end
M.rebakeFull = function()
  if not state or state.phase ~= "active" then L("E", "Noch nicht bereit."); return end
  rebake()
end

-- inkrementell: nur einen Layer auf die vorhandenen gebackenen Texturen (ohne clear)
local function bakeOne(l)
  local veh = be:getObjectByID(state.vehId); if not veh then return 0 end
  local c, s = l.patinaColor, l.patinaStrength
  local cl = shallowcopy(l); cl.color = Point4F(enc(c[1]), enc(c[2]), enc(c[3]), 1); cl.uid = l.uid .. "-c"
  local e = enc(s); local ml = shallowcopy(l); ml.color = Point4F(e, e, e, 1); ml.uid = l.uid .. "-m"
  local t = hptimer()
  state.color.proj:bakeLayers({ cl }, veh.jbeam)
  state.mask.proj:bakeLayers({ ml }, veh.jbeam)
  return t:stopAndReset()
end

-- Skin pro Fahrzeug ---------------------------------------------------------------
-- Skin-Materialien heißen <mapTo>.skin.<name> (editor/api/dynamicDecals.lua:2099,2108) und werden vom Spiel
-- lackiert. vehicleObj:setSkin(slot.."."..name) (common/jbeam/sections/licenseplatesSkins.lua:56-58, Slot ''
-- für paint_design) wirkt nur beim Spawn: Meshes entstehen danach in jbeamMeshs.process (common/jbeam/loader.lua:387,411).
-- Neu spawnen wie partmgmt: veh:respawn(serialize(config)) (core/vehicle/partmgmt.lua:935).
-- Material kopieren wie der Material-Editor (editor/api/material.lua:231-245 dontCopy, :265-279, :338-344).
local DONT_COPY = { name = true, mapTo = true, persistentId = true, parentGroup = true, internalName = true, class = true,
  className = true, superClass = true, hidden = true, locked = true, canSave = true, canSaveDynamicFields = true }
local function copyMaterial(src, dst)
  for f, _ in pairs(src:getFields()) do
    if not DONT_COPY[f] then
      for s = 0, 3 do dst:setField(f, s, src:getField(f, s)) end
    end
  end
  for _, f in ipairs(src:getDynamicFields() or {}) do
    if not DONT_COPY[f] then dst:setDynDataFieldbyName(f, 0, src:getDynDataFieldbyName(f, 0)) end
  end
end

-- Spike 4: eigener Skin-Slot. setSkin ist pro Slot (licenseplatesSkins.lua:56-58: skinType/slotType, '' für
-- paint_design → Material "<mat>.skin.<name>"; z. B. Slot skin_interior → "etki_intcarpet.skin_interior.cream",
-- etki/skin.materials.json). Spawn setzt nur Slots echter Teile neu → Slot "patina" bleibt über Neuspawn/Strg+R,
-- und paint_design (Lackierungsmuster) bleibt unberührt. Offen: welches Material gewinnt bei zwei Slots?
-- M.slot = "" → alter Weg über paint_design (Spike 2d/3).
M.slot = "patina"
local function skinOf(vehId) return "v" .. vehId end
local function slotPart() return M.slot == "" and "skin" or M.slot end
local function skinMatName(mesh, vehId) return mesh .. "." .. slotPart() .. "." .. skinOf(vehId) end

-- Stage, in der schon eine Patina-Ebene steckt (sonst nil) – gegen doppelte Stages (2c Lauf 7)
local function patinaStage(m)
  for s = 0, 3 do
    if m:getField("baseColorMap", s) == COLOR_PREFIX .. "BaseColor" then return s end
  end
end

local function createSkinMaterial(orig, name)
  local old = scenetree.findObject(name)
  if old and old:getName() == orig:getName() then   -- Fahrzeug trägt den Patina-Skin schon (2d Lauf 1: hing sonst)
    return old, patinaStage(old) or -1
  end
  if old then old:delete() end
  local c = createObject("Material")
  if orig.getFilename and orig:getFilename() then c:setFilename(orig:getFilename()) end
  copyMaterial(orig, c)
  c:setField("name", 0, name)
  c:setField("mapTo", 0, name)
  local s = patinaStage(c) or (tonumber(c:getField("activeLayers", 0)) or 1)
  c:setField("baseColorMap", s, COLOR_PREFIX .. "BaseColor")
  c:setField("diffuseMapUseUV", s, tostring(UV_LAYER))
  c:setField("opacityMap", s, MASK_PREFIX .. "BaseColor")
  c:setField("opacityMapUseUV", s, tostring(UV_LAYER))
  c:setField("metallicFactor", s, "0")
  c:setField("roughnessFactor", s, "1")
  c:setField("instanceDiffuse", s, "0")
  c:setField("activeLayers", 0, tostring(s + 1))
  c.canSave = false
  c:registerObject(name)
  return c, s
end

local function respawn(veh)
  local vd = core_vehicle_manager.getVehicleData(veh:getID())
  if not (vd and vd.config) then L("E", "Keine Fahrzeugdaten für Neuspawn."); return false end
  state.respawnTimer = hptimer()
  veh:respawn(serialize(vd.config))
  return true
end

local function deleteSkinMaterials()
  for _, n in ipairs(state.skinMats or {}) do
    local m = scenetree.findObject(n)
    if m then m:delete() end
  end
end

-- nach dem Spawn: Ziele sind jetzt die Skin-Materialien. Projektionen anlegen/neu zuordnen, binden, backen.
local function attach(veh)
  local skin = skinOf(state.vehId)
  local probe = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  probe:setShape(veh:getDecalProjectionShape())
  local targets = findTargets(veh, probe)
  local lines, onSkin = {}, 0
  for _, t in ipairs(targets) do
    local isSkin = t.objName == skinMatName(t.mesh, state.vehId)
    if isSkin then onSkin = onSkin + 1; t.stage = patinaStage(t.obj) or t.stage end
    table.insert(lines, string.format("  %-34s → Mesh '%s' [%d], Patina-Stage %s", t.objName, t.mesh, t.idx,
      isSkin and tostring(t.stage) or "– (kein Skin!)"))
  end
  L("I", "attach: %d/%d Lackmaterialien auf Skin %s\n%s", onSkin, #targets, skin, table.concat(lines, "\n"))
  state.targets = targets
  if not state.color then
    local cp, mp = newProj(veh, targets), newProj(veh, targets)
    state.color = { proj = cp, set = cp:getTextureSet() }
    state.mask  = { proj = mp, set = mp:getTextureSet() }
  else
    for _, p in ipairs({ state.color.proj, state.mask.proj }) do
      p:setShape(veh:getDecalProjectionShape()); p:clearMaterialIdx()
      for _, t in ipairs(targets) do p:addMaterialIdx(t.idx) end
    end
  end
  refresh(veh)
  rebake()
  state.phase = "active"
end
-- Decal-Anfrage in die Warteschlange. opts: texture, size, depth, color{r,g,b}, strength
local function queueDecal(side, opts)
  if not state then L("E", "Erst start()."); return end
  local veh = getVeh(); if not veh then return end
  local dir = dirs[side]; if not dir then L("E", "Unbekannte Seite '%s'", tostring(side)); return end
  opts = opts or {}

  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local center, ext = (mn + mx) * 0.5, (mx - mn) * 0.5
  local reach = math.abs(dir.x) * ext.x + math.abs(dir.y) * ext.y + math.abs(dir.z) * ext.z + 1.0
  local camPos = center - dir * reach
  local q = quatFromDir(dir, math.abs(dir.z) > 0.9 and vec3(0, 1, 0) or vec3(0, 0, 1))
  local camM = QuatF(q.x, q.y, q.z, q.w):getMatrix()
  if opts.offset then camPos = camPos + opts.offset end
  camM:setPosition(camPos)

  state.queue = state.queue or {}
  table.insert(state.queue, {
    side = side, dir = dir, camPos = camPos, camM = camM, projM = getCameraProjMatrix(), frames = 0,
    texture = opts.texture or TEST_TEXTURE, size = opts.size or 0.5, depth = opts.depth or 0.1,
    color = opts.color or { DIRT[1], DIRT[2], DIRT[3] }, strength = opts.strength or 1,
  })
end



local function processPending()
  local req, p = state.queue[1], state.color.proj
  if req.frames == 0 then
    p:setDecalTexturePath("color", req.texture)
    p.decalColor = Point4F(1, 1, 1, 1)
    p.decalScale = vec3(req.size, req.depth, req.size)
    p.decalRotation = 0
    p.useSurfaceNormal = false
  end
  if bit.band(p:getSettings(), USE_MOUSE_POS) == USE_MOUSE_POS then p:toggleSetting(USE_MOUSE_POS) end
  p.cursorPosition = Point2F(0.5, 0.5)
  p:projectDynamicDecals(req.camM, req.projM)
  req.frames = req.frames + 1
  if req.frames < FRAMES_BEFORE_READ then return end

  local ok, data = pcall(function() return p:getDecalData(req.camM, req.projM) end)
  local hit = ok and data and data.decalPos and vec3(data.decalPos)
  if not (hit and hit.x == hit.x and hit:length() < 1e6) then
    if req.frames < FRAMES_MAX then return end
    if state.loadTest then state.loadTest.miss = state.loadTest.miss + 1
    else L("W", "decal(%s): kein Treffer nach %d Frames (kein erfasstes Material im Strahl?).", req.side, req.frames) end
    p:flushDynamicTextures(); table.remove(state.queue, 1)
    return
  end
  data.uid, data.name, data.enabled, data.locked, data.children = uid("decal"), "Patina " .. req.side, true, false, {}
  data.patinaColor, data.patinaStrength = req.color, req.strength
  table.insert(state.layers, data)
  p:flushDynamicTextures()
  table.remove(state.queue, 1)
  local lt = state.loadTest
  if lt then
    local ms = (lt.mode == "inc") and bakeOne(data) or rebake()
    table.insert(lt.bakes, ms)
    table.insert(lt.reqFrames, req.frames)
    lt.hit = lt.hit + 1
    return
  end
  L("I", "decal(%s): Treffer bei %s (Größe %.1f, Tiefe %.1f, Stärke %.2f)", req.side, tostring(hit), req.size, req.depth, req.strength)
  rebake()
end

-- Lasttest ---------------------------------------------------------------------------
local LOAD_TEXTURES = {   -- Spiel-eigene Decal-Texturen (/art/dynamicDecals/textures/)
  "/art/dynamicDecals/textures/_one.png", "/art/dynamicDecals/textures/digit_basic_1.png",
}
local SIDES = { "left", "right", "front", "rear", "top" }
local BASELINE_S, COOLDOWN_S = 3, 3

local function stats(list)
  local n = #list
  if n == 0 then return "n=0" end
  local s = {}; local sum = 0
  for i, v in ipairs(list) do s[i] = v; sum = sum + v end
  table.sort(s)
  local function pct(p) return s[math.max(1, math.min(n, math.ceil(p * n)))] end
  return string.format("n=%d Ø %.2f  p50 %.2f  p95 %.2f  p99 %.2f  max %.2f", n, sum / n, pct(0.5), pct(0.95), pct(0.99), s[n])
end

-- zufälliger Strahl: Seite + seitlicher Versatz innerhalb der Fahrzeugmaße
local function randomRequest(veh)
  local side = SIDES[math.random(#SIDES)]
  local d = dirs[side]
  local aabb = veh:getSpawnLocalAABB()
  local ext = (vec3(aabb.maxExtents) - vec3(aabb.minExtents)) * 0.5
  local function j(axis, e) return (math.abs(d[axis]) < 0.5) and (math.random() * 2 - 1) * e * 0.8 or 0 end
  local off = vec3(j("x", ext.x), j("y", ext.y), j("z", ext.z))
  local tl = state.loadTest
  queueDecal(side, { texture = LOAD_TEXTURES[math.random(#LOAD_TEXTURES)], size = 0.2 + math.random() * 0.4,
    depth = 0.3, strength = 0.3 + math.random() * 0.5, offset = off })
  tl.issued = tl.issued + 1
end

M.load = function(n, seconds, mode)
  if not state or state.phase ~= "active" then L("E", "Noch nicht bereit (start() und Neuspawn abwarten)."); return end
  if state.loadTest then L("W", "Lasttest läuft schon."); return end
  n, seconds, mode = n or 200, seconds or 20, mode or "inc"
  state.quiet = true
  state.loadTest = { n = n, seconds = seconds, mode = mode, phase = "baseline", t = 0, issued = 0, hit = 0, miss = 0,
    frames = { baseline = {}, run = {}, cooldown = {} }, bakes = {}, reqFrames = {}, upd = {}, combine = {},
    layersBefore = #state.layers }
  L("I", "load(%d, %d s, %s): Grundlinie %d s …", n, seconds, mode, BASELINE_S)
end

local function loadTick(veh, dt)
  local lt = state.loadTest
  lt.t = lt.t + dt
  table.insert(lt.frames[lt.phase], dt * 1000)
  if lt.phase == "baseline" and lt.t >= BASELINE_S then
    lt.phase, lt.t = "run", 0
    lt.wall = hptimer()
  elseif lt.phase == "run" then
    local due = math.min(lt.n, math.floor(lt.t / lt.seconds * lt.n) + 1)
    while lt.issued < due do randomRequest(veh) end
    if lt.issued >= lt.n and #(state.queue or {}) == 0 then
      lt.runWall = lt.wall:stopAndReset() / 1000
      lt.phase, lt.t = "cooldown", 0
    end
  elseif lt.phase == "cooldown" and lt.t >= COOLDOWN_S then
    L("I", "=== Lasttest %s: %d Decals angefragt, %d Treffer, %d ohne Treffer, Laufzeit %.1f s (Soll %d s), Layer %d → %d",
      lt.mode, lt.issued, lt.hit, lt.miss, lt.runWall or -1, lt.seconds, lt.layersBefore, #state.layers)
    L("I", "Frametime Grundlinie ms: %s", stats(lt.frames.baseline))
    L("I", "Frametime Last ms:       %s", stats(lt.frames.run))
    L("I", "Frametime danach ms:     %s", stats(lt.frames.cooldown))
    L("I", "Bake pro Decal ms:       %s", stats(lt.bakes))
    L("I", "Frames pro Decal (Projektion+Auslesen): %s", stats(lt.reqFrames))
    L("I", "Patina-onUpdate (CPU) ms Last: %s", stats(lt.upd))
    L("I", "combineTextures (CPU) ms Last: %s", stats(lt.combine))
    state.quiet = false
    state.loadTest = nil
  end
end

-- Befehle --------------------------------------------------------------------------

M.start = function()
  local veh = getVeh(); if not veh then return end
  if state then L("W", "Läuft schon (Phase %s), erst stop().", tostring(state.phase)); return end
  local vehId = veh:getID()
  state = { vehId = vehId, layers = {}, phase = "prepare" }

  local probe = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  probe:setShape(veh:getDecalProjectionShape())
  local targets, skipped = findTargets(veh, probe)
  if #skipped > 0 then L("W", "Übersprungen: %s", table.concat(skipped, ", ")) end
  if #targets == 0 then L("E", "Keine lackierten Materialien gefunden."); state = nil; return end

  local skin = skinOf(vehId)
  state.skinMats = {}
  local lines = {}
  for _, t in ipairs(targets) do
    local name = skinMatName(t.mesh, vehId)
    local _, s = createSkinMaterial(t.obj, name)
    table.insert(state.skinMats, name)
    table.insert(lines, string.format("  %-28s → %s (Stage %d)", t.objName, name, s))
  end
  L("I", "Fahrzeug %s (ID %d): %d Skin-Materialien\n%s", veh.jbeam, vehId, #targets, table.concat(lines, "\n"))
  veh:setSkin(M.slot .. "." .. skin)
  state.phase = "respawn"
  L("I", "setSkin('%s.%s'), Neuspawn …", M.slot, skin)
  if not respawn(veh) then deleteSkinMaterials(); state = nil end
end

M.coat2 = function(strength, r, g, b)
  if not state or state.phase ~= "active" then L("E", "Noch nicht bereit (start() und Neuspawn abwarten)."); return end
  local opts = { texture = "/art/dynamicDecals/textures/_one.png", size = 6, depth = 4,
                 color = { r or DIRT[1], g or DIRT[2], b or DIRT[3] }, strength = strength or 0.7 }
  for _, side in ipairs({ "left", "right", "front", "rear", "top" }) do queueDecal(side, opts) end
end

M.decal = function(side, size)
  if not state or state.phase ~= "active" then L("E", "Noch nicht bereit."); return end
  queueDecal(side or "left", { size = size })
end

-- Muster: exportSkin → decalProjection:exportTextures(dir, name, "png") (dynamicDecals.lua:2083)
M.export = function(tag)
  if not state or not state.color then L("E", "Erst start()."); return end
  tag = tag or os.date("%H%M%S")
  local dir = "/patina_export/" .. tag .. "/"
  local ok1, e1 = pcall(function() return state.color.proj:exportTextures(dir, "color", "png") end)
  local ok2, e2 = pcall(function() return state.mask.proj:exportTextures(dir, "mask", "png") end)
  L("I", "export(%s): color %s, mask %s → %s", tag, ok1 and "ok" or tostring(e1), ok2 and "ok" or tostring(e2), dir)
end

M.clear = function()
  if not state or state.phase ~= "active" then return end
  state.layers = {}
  rebake()
end

M.stop = function()
  if not state then return end
  local veh = be:getObjectByID(state.vehId)
  if veh and state.phase ~= "restore" then
    veh:setSkin(M.slot .. ".")
    state.phase = "restore"
    L("I", "stop(): setSkin('%s.'), Neuspawn …", M.slot)
    if respawn(veh) then return end
  end
  deleteSkinMaterials()
  L("I", "stop(): %d Skin-Materialien gelöscht.", #(state.skinMats or {}))
  state = nil
end

-- Hooks ----------------------------------------------------------------------------

-- Lauf 1: Strg+R (be:reloadVehicle, core/vehicle/manager.lua:319-324) verliert alle Skins, auch Slot "patina".
-- onSpawnCCallback feuert am Anfang jedes Spawns, vor Laden der Teile und Meshes
-- (core/vehicle/manager.lua:111-140) → Skin dort erneut setzen.
M.onSpawnCCallback = function(objID)
  if not state or state.vehId ~= objID or state.phase ~= "active" then return end
  local v = be:getObjectByID(objID) or scenetree.findObject(objID)
  if not v then L("W", "onSpawnCCallback(%d): Fahrzeug nicht gefunden", objID); return end
  v:setSkin(M.slot .. "." .. skinOf(objID))
  L("I", "onSpawnCCallback(%d): setSkin('%s.%s') erneut", objID, M.slot, skinOf(objID))
end

M.onVehicleSpawned = function(vid)
  if not state or state.vehId ~= vid then return end
  local veh = be:getObjectByID(vid); if not veh then return end
  local ms = state.respawnTimer and state.respawnTimer:stopAndReset() or -1
  L("I", "onVehicleSpawned(%d), Phase %s, Neuspawn %.0f ms", vid, state.phase, ms)
  if state.phase == "respawn" or state.phase == "active" then
    state.spawnFrames = 0
    attach(veh)
  elseif state.phase == "restore" then
    deleteSkinMaterials()
    L("I", "stop(): Fahrzeug sauber, %d Skin-Materialien gelöscht.", #(state.skinMats or {}))
    state = nil
  end
end

M.onUpdate = function(dtReal)
  if not state or state.phase ~= "active" then return end
  local veh = be:getObjectByID(state.vehId)
  if not veh then return end
  local tu = hptimer()
  if state.loadTest then loadTick(veh, dtReal or 0) end
  refresh(veh)
  if state.queue and #state.queue > 0 then processPending() end
  if not state then return end
  local tc = hptimer()
  state.color.proj:combineTextures(state.color.set)
  state.mask.proj:combineTextures(state.mask.set)
  local lt = state.loadTest
  if lt and lt.phase == "run" then
    table.insert(lt.combine, tc:stopAndReset())
    table.insert(lt.upd, tu:stopAndReset())
  end
end

M.onVehicleReplaced = function(vid)
  if state and state.vehId == vid then L("I", "onVehicleReplaced(%d), Phase %s", vid, state.phase) end
end
M.onVehicleDestroyed = function(vid)
  if state and state.vehId == vid then
    if state.phase == "respawn" or state.phase == "restore" then
      L("I", "onVehicleDestroyed(%d) während Neuspawn (Phase %s) → ignoriert", vid, state.phase); return
    end
    L("I", "onVehicleDestroyed(%d), Phase %s → aufräumen", vid, state.phase)
    deleteSkinMaterials(); state = nil
  end
end
M.onExtensionUnloaded = function() if state then M.stop() end end

return M
