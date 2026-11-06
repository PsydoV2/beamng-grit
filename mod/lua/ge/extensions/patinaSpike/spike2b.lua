-- Patina – Spike 2b: Weg A′ auf ALLEN lackierten Materialien eines beliebigen Fahrzeugs.
-- Baut auf Spike 2 auf (Farbe @PatinaTexture + Maske @PatinaMask, Zusatz-Stage über dem Lack).
-- Wegwerf-Prototyp.
--
-- Konsole (GE - Lua):
--   extensions.load("patinaSpike_spike2b")
--   patinaSpike_spike2b.start()          -- alle lackierten Materialien finden und vorbereiten
--   patinaSpike_spike2b.coat(0.7)        -- alle erfassten Lackflächen gleichmäßig verdrecken
--   patinaSpike_spike2b.coat2(0.7)       -- wie coat(), aber mit 5 großen Decals statt Fill-Layer
--   patinaSpike_spike2b.decal("left")    -- Test-„1“: "left" | "right" | "top" | "front" | "rear"
--   patinaSpike_spike2b.full()           -- Diagnose: Ebene ohne Maske, überall deckend (full(false) = Maske wieder an)
--   patinaSpike_spike2b.status()         -- Material-Felder ins Log
--   patinaSpike_spike2b.export("a")      -- gebackene Texturen als PNG nach <User>/patina_export/a/
--   patinaSpike_spike2b.clear()          -- Dreck entfernen
--   patinaSpike_spike2b.stop()           -- alle Materialien wiederherstellen

local M = {}
local logTag = "patinaSpike2b"

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

local STAGE_FIELDS = { "baseColorMap", "diffuseMapUseUV", "opacityMap", "opacityMapUseUV",
  "metallicFactor", "roughnessFactor", "instanceDiffuse" }

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
  L("I", "bake: %d Layer, %.2f ms, code=%s/%s", #state.layers, dt,
    tostring(r1 and r1.status and r1.status.code), tostring(r2 and r2.status and r2.status.code))
end

local function applyStages()
  for _, t in ipairs(state.targets) do
    local m, s = t.obj, t.stage
    t.backup = { activeLayers = m:getField("activeLayers", 0) }
    for _, f in ipairs(STAGE_FIELDS) do t.backup[f] = m:getField(f, s) end
    m:setField("baseColorMap", s, COLOR_PREFIX .. "BaseColor")
    m:setField("diffuseMapUseUV", s, tostring(UV_LAYER))
    m:setField("opacityMap", s, MASK_PREFIX .. "BaseColor")
    m:setField("opacityMapUseUV", s, tostring(UV_LAYER))
    m:setField("metallicFactor", s, "0")
    m:setField("roughnessFactor", s, "1")
    m:setField("instanceDiffuse", s, "0")
    m:setField("activeLayers", 0, tostring(s + 1))
    m:reload()
  end
end

local function restoreStages()
  for _, t in ipairs(state.targets) do
    if t.backup then
      for _, f in ipairs(STAGE_FIELDS) do t.obj:setField(f, t.stage, t.backup[f] or "") end
      t.obj:setField("activeLayers", 0, t.backup.activeLayers or "1")
      t.obj:reload()
    end
  end
end

-- Befehle --------------------------------------------------------------------------

M.start = function()
  local veh = getVeh(); if not veh then return end
  if state then L("W", "Läuft schon, erst stop()."); return end

  local probe = DecalProjection("", RESOLUTION, UV_LAYER, 0)
  probe:setShape(veh:getDecalProjectionShape())
  local targets, skipped = findTargets(veh, probe)

  local lines = {}
  for _, t in ipairs(targets) do
    table.insert(lines, string.format("  %-28s → Mesh '%s' [%d], Stage %d", t.objName, t.mesh, t.idx, t.stage))
  end
  L("I", "Fahrzeug %s: %d lackierte Materialien\n%s", veh.jbeam, #targets, table.concat(lines, "\n"))
  if #skipped > 0 then L("W", "Übersprungen: %s", table.concat(skipped, ", ")) end
  if #targets == 0 then L("E", "Keine lackierten Materialien gefunden."); return end
  local cp, mp = newProj(veh, targets), newProj(veh, targets)
  state = {
    vehId = veh:getID(), targets = targets, layers = {},
    color = { proj = cp, set = cp:getTextureSet() },
    mask  = { proj = mp, set = mp:getTextureSet() },
    -- Lauf K: das Material ist pro Modell geteilt. Andere Fahrzeuge ohne eigenes Set zeigen Datenreste.
    -- Lauf K′: ein gemeinsames leeres Set (mit der Form des Patina-Autos) → zweiter ETKI lavendelblau.
    -- Jetzt: jedes andere Fahrzeug bekommt eine eigene leere Projektion mit SEINER Form.
    others = {},
  }
  applyStages()
  rebake()
  L("I", "start(): bereit. coat(0.7) oder decal(\"left\").")
  L("I", "start(): bereit. coat(0.7) oder decal(\"left\").")
end

-- gleichmäßiger Dreck auf allen erfassten Flächen (Fill-Layer)
M.coat = function(strength, r, g, b)
  if not state then L("E", "Erst start()."); return end
  table.insert(state.layers, {
    type = 1, blendMode = 1, colorPaletteMapId = 0, enabled = true, locked = false,
    uid = uid("coat"), name = "Patina Coat", children = {},
    patinaColor = { r or DIRT[1], g or DIRT[2], b or DIRT[3] }, patinaStrength = strength or 0.7,
  })
  rebake()
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
  camM:setPosition(camPos)

  state.queue = state.queue or {}
  table.insert(state.queue, {
    side = side, dir = dir, camPos = camPos, camM = camM, projM = getCameraProjMatrix(), frames = 0,
    texture = opts.texture or TEST_TEXTURE, size = opts.size or 0.5, depth = opts.depth or 0.1,
    color = opts.color or { DIRT[1], DIRT[2], DIRT[3] }, strength = opts.strength or 1,
  })
end

M.decal = function(side, size)
  queueDecal(side or "left", { size = size })
end

-- Variante zu coat(): fünf große, flächige Decals (Textur _one.png = voll weiß) statt Fill-Layer
M.coat2 = function(strength, r, g, b)
  local opts = { texture = "/art/dynamicDecals/textures/_one.png", size = 6, depth = 4,
                 color = { r or DIRT[1], g or DIRT[2], b or DIRT[3] }, strength = strength or 0.7 }
  for _, side in ipairs({ "left", "right", "front", "rear", "top" }) do queueDecal(side, opts) end
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
    L("W", "decal(%s): kein Treffer nach %d Frames (kein erfasstes Material im Strahl?).", req.side, req.frames)
    p:flushDynamicTextures(); table.remove(state.queue, 1)
    return
  end
  data.uid, data.name, data.enabled, data.locked, data.children = uid("decal"), "Patina " .. req.side, true, false, {}
  data.patinaColor, data.patinaStrength = req.color, req.strength
  table.insert(state.layers, data)
  p:flushDynamicTextures()
  table.remove(state.queue, 1)
  L("I", "decal(%s): Treffer bei %s (Größe %.1f, Tiefe %.1f, Stärke %.2f)", req.side, tostring(hit), req.size, req.depth, req.strength)
  rebake()
end

-- Diagnose: Patina-Ebene ohne Maske (überall voll deckend). Zeigt, auf welchen Flächen die Stage wirkt.
M.full = function(on)
  if not state then L("E", "Erst start()."); return end
  for _, t in ipairs(state.targets) do
    t.obj:setField("opacityMap", t.stage, on == false and (MASK_PREFIX .. "BaseColor") or "")
    t.obj:reload()
  end
  L("I", "full(%s): Maske %s", tostring(on ~= false), on == false and "an" or "aus")
end

M.status = function()
  if not state then L("E", "Erst start()."); return end
  for _, t in ipairs(state.targets) do
    local m, parts = t.obj, {}
    table.insert(parts, "activeLayers=" .. tostring(m:getField("activeLayers", 0)))
    for s = 0, 3 do
      for _, f in ipairs({ "baseColorMap", "colorPaletteMap", "opacityMap", "diffuseMapUseUV", "opacityMapUseUV" }) do
        local v = m:getField(f, s)
        if v and v ~= "" then table.insert(parts, string.format("[%d]%s=%s", s, f, v)) end
      end
    end
    L("I", "%s: %s", t.objName, table.concat(parts, " "))
  end
end

-- Diagnose: gebackene Texturen beider Projektionen als PNG in den User-Ordner (/patina_export/<tag>/)
-- Muster: exportSkin → decalProjection:exportTextures(dir, name, "png") (dynamicDecals.lua:2083)
M.export = function(tag)
  if not state then L("E", "Erst start()."); return end
  tag = tag or os.date("%H%M%S")
  local dir = "/patina_export/" .. tag .. "/"
  local ok1, e1 = pcall(function() return state.color.proj:exportTextures(dir, "color", "png") end)
  local ok2, e2 = pcall(function() return state.mask.proj:exportTextures(dir, "mask", "png") end)
  L("I", "export(%s): color %s, mask %s → %s", tag, ok1 and "ok" or tostring(e1), ok2 and "ok" or tostring(e2), dir)
  local veh = getVeh()
  if veh then L("I", "Fahrzeugfarbe: %s", tostring(veh.color)) end
end

-- Diagnose: leere Projektionen der anderen Fahrzeuge exportieren
M.exportOthers = function(tag)
  if not state then return end
  tag = tag or os.date("%H%M%S")
  for id, o in pairs(state.others) do
    local ok, e = pcall(function() return o.proj:exportTextures("/patina_export/" .. tag .. "/", "other" .. id, "png") end)
    L("I", "exportOthers(%s): ID %d %s", tag, id, ok and "ok" or tostring(e))
  end
end

M.clear = function()
  if not state then return end
  state.layers = {}
  rebake()
end

M.stop = function()
  if not state then return end
  restoreStages()
  L("I", "stop(): %d Materialien wiederhergestellt.", #state.targets)
  state = nil
end

local SPAWN_DELAY = 30
local function bindEmpty()
  local me = be:getObjectByID(state.vehId)
  local model = me and me.jbeam
  local alive = {}
  for _, v in ipairs(getAllVehicles()) do
    local id = v:getID()
    if id ~= state.vehId and v.jbeam == model then  -- nur gleiches Modell teilt das Material (Spike)
      alive[id] = true
      local o = state.others[id]
      -- Lauf K″: direkt im Spawn-Frame gebacken → blau. Erst nach SPAWN_DELAY Frames erzeugen.
      state.seen = state.seen or {}
      state.seen[id] = (state.seen[id] or 0) + 1
      if not o and state.seen[id] < SPAWN_DELAY then goto continue end
      if not o then
        local p = newProj(v, state.targets)
        o = { proj = p, set = p:getTextureSet() }
        refreshProj(v, p, MASK_PREFIX, o.set)
        v:setTextureSet(COLOR_PREFIX, o.set)
        state.others[id] = o
      end
      -- Lauf 9: nach 30 Frames nur teilweise richtig → mehrmals neu backen (Teile laden nach?)
      o.age = (o.age or 0) + 1
      if o.age == 1 or o.age == 60 or o.age == 180 or o.age == 600 then
        refreshProj(v, o.proj, MASK_PREFIX, o.set)
        o.proj:clearBakedTextures()
        local r = o.proj:bakeLayers({ baseLayer() }, v.jbeam)
        L("I", "leere Projektion %s (ID %d) gebacken bei Frame %d, Materialien %d, code=%s", tostring(v.jbeam), id,
          o.age, #(o.proj:getShapeMaterialNames() or {}), tostring(r and r.status and r.status.code))
      end
      refreshProj(v, o.proj, MASK_PREFIX, o.set)
      v:setTextureSet(COLOR_PREFIX, o.set)
      o.proj:combineTextures(o.set)
    end
    ::continue::
  end
  for id in pairs(state.others) do if not alive[id] then state.others[id] = nil end end
end

M.onUpdate = function()
  if not state then return end
  bindEmpty()
  local veh = be:getObjectByID(state.vehId)
  if not veh then return end
  refresh(veh)
  if state.queue and #state.queue > 0 then processPending() end
  if not state then return end
  state.color.proj:combineTextures(state.color.set)
  state.mask.proj:combineTextures(state.mask.set)
end

M.onVehicleDestroyed = function(vid) if state and state.vehId == vid then M.stop() end end
M.onVehicleReplaced  = function(vid) if state and state.vehId == vid then M.stop() end end
M.onExtensionUnloaded = function() M.stop() end

return M
