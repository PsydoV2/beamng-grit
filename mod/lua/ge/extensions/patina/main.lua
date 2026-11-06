-- Patina – GE-Hauptmodul (Extension patina_main): Fahrzeugverwaltung, Skin pro Fahrzeug, Ereignisse → Zeichnen.
-- Weg A′ (FINDINGS.md, Spikes 2–5):
--   * Kopie jedes lackierten Materials mit Zusatz-Stage als <mapTo>.patina.v<ID>, Skin-Slot "patina"
--     (vehicleObj:setSkin, common/jbeam/sections/licenseplatesSkins.lua:56-58; Vorrang vor paint_design, Spike 4).
--   * setSkin wirkt nur beim Spawn → einmal veh:respawn (core/vehicle/partmgmt.lua:935); bei jedem weiteren
--     Spawn (Strg+R) in onSpawnCCallback erneut setzen (core/vehicle/manager.lua:111-140).
--   * Sensor-Controller ins Fahrzeug laden (vehicle/controller.lua:297 loadControllerExternal).
-- M1: nur das Spielerfahrzeug, nur Schrammen.

local M = {}
local logTag = "patina"
local render = require("ge/extensions/patina/render")

local SLOT = "patina"
local SENSOR_FILE, SENSOR_NAME = "patina/sensor", "patinaSensor"
local SCRATCH = {   -- M1-Platzhalter: gestreckter weißer Strich (Spiel-Textur), heller Ton = Grundierung
  texture = "/art/dynamicDecals/textures/_one.png", color = { 0.78, 0.78, 0.76 },
  width = 0.03, depth = 0.25, minLen = 0.06, lenPerMs = 0.05, maxLen = 0.35,
}

M.debugLog = true           -- Entwicklung: zusätzlich sofort in <User>/patina.log (beamng.log puffert Minuten)
local DEV_LOG = "/patina.log"
local function L(level, fmt, ...)
  local msg = string.format(fmt, ...)
  log(level, logTag, msg)
  if M.debugLog then
    local f = io.open(DEV_LOG, "a")
    if f then f:write(string.format("%s|%s|%s\n", os.date("%H:%M:%S"), level, msg)); f:close() end
  end
end

local cars = {}   -- vehId → { phase = "respawn"|"active", skinMats = {}, r = render-Objekt, retried }

-- Materialien ------------------------------------------------------------------------

local function isTrue(v) return v == "1" or v == "true" end
-- lackiert: Material v1.5 mit colorPaletteMap in irgendeiner Stage, sonst Legacy mit instanceDiffuse; nie Glas
-- (Spike 2b Lauf 1–3)
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

local function meshStem(mapTo) return mapTo and mapTo:match("^([^%.]+)") or nil end
local function skinOf(vid) return "v" .. vid end
local function skinMatName(mesh, vid) return mesh .. "." .. SLOT .. "." .. skinOf(vid) end

-- lackierte Materialien des Fahrzeugs mit Index in der Decal-Form
local function findTargets(veh)
  local probe = DecalProjection("", Point2I(16, 16), 1, 0)
  probe:setShape(veh:getDecalProjectionShape())
  local idxByMesh = {}
  for k, n in pairs(probe:getShapeMaterialNames()) do idxByMesh[n] = k end
  local targets, skipped, seen = {}, {}, {}
  for _, objName in ipairs(veh:getMaterialNames() or {}) do
    local m = not seen[objName] and scenetree.findObject(objName)
    seen[objName] = true
    if m then
      local mapTo = m:getField("mapTo", 0)
      local mesh = idxByMesh[mapTo] and mapTo or meshStem(mapTo)
      local idx = mesh and idxByMesh[mesh]
      if idx and isPaintable(m) then
        if (tonumber(m:getField("activeLayers", 0)) or 1) >= 4 and not objName:find("%." .. SLOT .. "%.") then
          table.insert(skipped, objName)
        else
          table.insert(targets, { obj = m, objName = objName, mesh = mesh, idx = idx })
        end
      end
    end
  end
  return targets, skipped
end

-- Kopie wie der Material-Editor (editor/api/material.lua:231-245 dontCopy, :265-279, :338-344)
local DONT_COPY = { name = true, mapTo = true, persistentId = true, parentGroup = true, internalName = true, class = true,
  className = true, superClass = true, hidden = true, locked = true, canSave = true, canSaveDynamicFields = true }
local function copyMaterial(src, dst)
  for f, _ in pairs(src:getFields()) do
    if not DONT_COPY[f] then for s = 0, 3 do dst:setField(f, s, src:getField(f, s)) end end
  end
  for _, f in ipairs(src:getDynamicFields() or {}) do
    if not DONT_COPY[f] then dst:setDynDataFieldbyName(f, 0, src:getDynDataFieldbyName(f, 0)) end
  end
end

local function patinaStage(m)
  for s = 0, 3 do if m:getField("baseColorMap", s) == render.COLOR_PREFIX .. "BaseColor" then return s end end
end

local function ensureSkinMaterial(orig, name)
  local old = scenetree.findObject(name)
  if old and old:getName() == orig:getName() then return old end   -- trägt den Skin schon
  if old then old:delete() end
  local c = createObject("Material")
  if orig.getFilename and orig:getFilename() then c:setFilename(orig:getFilename()) end
  copyMaterial(orig, c)
  c:setField("name", 0, name)
  c:setField("mapTo", 0, name)
  local s = patinaStage(c) or (tonumber(c:getField("activeLayers", 0)) or 1)
  c:setField("baseColorMap", s, render.COLOR_PREFIX .. "BaseColor")
  c:setField("diffuseMapUseUV", s, "1")
  c:setField("opacityMap", s, render.MASK_PREFIX .. "BaseColor")
  c:setField("opacityMapUseUV", s, "1")
  c:setField("metallicFactor", s, "0")
  c:setField("roughnessFactor", s, "1")
  c:setField("instanceDiffuse", s, "0")
  c:setField("activeLayers", 0, tostring(s + 1))
  c.canSave = false
  c:registerObject(name)
  return c
end

local function deleteSkinMaterials(car)
  for _, n in ipairs(car.skinMats or {}) do
    local m = scenetree.findObject(n)
    if m then m:delete() end
  end
  car.skinMats = {}
end

-- Lebenszyklus -----------------------------------------------------------------------

local function respawn(veh)
  local vd = core_vehicle_manager.getVehicleData(veh:getID())
  if not (vd and vd.config) then return false end
  veh:respawn(serialize(vd.config))
  return true
end

local function prepare(veh)
  local vid = veh:getID()
  local targets, skipped = findTargets(veh)
  if #skipped > 0 then L("W", "Fahrzeug %d: übersprungen (4 Ebenen belegt): %s", vid, table.concat(skipped, ", ")) end
  if #targets == 0 then L("W", "Fahrzeug %d (%s): keine lackierten Materialien", vid, tostring(veh.jbeam)); return end
  local car = cars[vid] or { skinMats = {} }
  cars[vid] = car
  local keep = {}
  for _, t in ipairs(targets) do
    local name = skinMatName(t.mesh, vid)
    ensureSkinMaterial(t.obj, name)
    keep[name] = true
  end
  -- Reste eines vorigen Fahrzeugs/Musters mit derselben ID löschen (nicht mehr in Benutzung: Skin war aus)
  for _, n in ipairs(car.skinMats) do
    if not keep[n] then local m = scenetree.findObject(n); if m then m:delete() end end
  end
  car.skinMats = {}
  for n, _ in pairs(keep) do table.insert(car.skinMats, n) end
  veh:setSkin(SLOT .. "." .. skinOf(vid))
  car.phase = "respawn"
  car.timer = hptimer()
  L("I", "Fahrzeug %d (%s): %d Lackmaterialien → Skin %s.%s, Neuspawn", vid, tostring(veh.jbeam), #targets, SLOT, skinOf(vid))
  if not respawn(veh) then L("E", "Fahrzeug %d: Neuspawn nicht möglich", vid); car.phase = nil end
end

local function loadSensor(veh)
  veh:queueLuaCommand(string.format('controller.loadControllerExternal(%q, %q, {})', SENSOR_FILE, SENSOR_NAME))
end

local function attach(veh)
  local vid = veh:getID()
  local car = cars[vid]
  local targets = findTargets(veh)
  local onSkin, missing = {}, {}
  for _, t in ipairs(targets) do
    if t.objName == skinMatName(t.mesh, vid) then table.insert(onSkin, t) else table.insert(missing, t.objName) end
  end
  if #missing > 0 and not car.retried then
    -- z. B. Teilewechsel: neue Teile ohne Skin-Material → noch einmal vorbereiten
    L("I", "Fahrzeug %d: %d Materialien ohne Patina (%s) → neu vorbereiten", vid, #missing, table.concat(missing, ", "))
    car.retried = true
    prepare(veh)
    return
  end
  car.retried = nil
  car.r = render.new(veh, onSkin, L)
  car.phase = "active"
  loadSensor(veh)
  L("I", "Fahrzeug %d aktiv: %d/%d Materialien auf Patina%s, Neuspawn %.0f ms", vid, #onSkin, #targets,
    #missing > 0 and (" (ohne: " .. table.concat(missing, ", ") .. ")") or "", car.timer and car.timer:stopAndReset() or -1)
end

local function activate(vid)
  local veh = be:getObjectByID(vid)
  if not veh or (cars[vid] and cars[vid].phase) then return end
  prepare(veh)
end

-- Ereignisse vom Sensor ----------------------------------------------------------------

M.onSensorEvents = function(vid, ev)
  local car = cars[vid]
  if not car or car.phase ~= "active" or type(ev) ~= "table" then return end
  for _, s in ipairs(ev.scrapes or {}) do
    if (car.scrapes or 0) < 15 then
      L("I", "Schramme n%d pos(%.2f,%.2f,%.2f) n(%.2f,%.2f,%.2f) dir(%.2f,%.2f,%.2f) %.1f m/s mat %d/%d",
        s.c, s.px, s.py, s.pz, s.nx, s.ny, s.nz, s.sx, s.sy, s.sz, s.v, s.m1, s.m2)
    end
    local len = math.min(SCRATCH.maxLen, SCRATCH.minLen + s.v * SCRATCH.lenPerMs)
    local ok = car.r:request({
      pos = vec3(s.px, s.py, s.pz), normal = vec3(s.nx, s.ny, s.nz), up = vec3(s.sx, s.sy, s.sz),
      width = SCRATCH.width, length = len, depth = SCRATCH.depth, texture = SCRATCH.texture,
      color = SCRATCH.color, strength = math.min(1, 0.4 + s.v * 0.05), name = "Patina Kratzer",
    })
    if ok then car.scrapes = (car.scrapes or 0) + 1 end
  end
end

-- Hooks ------------------------------------------------------------------------------

M.onUpdate = function()
  for vid, car in pairs(cars) do
    if car.phase == "active" and car.r then
      local veh = be:getObjectByID(vid)
      if veh then car.r:update(veh) end
    end
  end
end

-- Nur beim eigenen Neuspawn den Skin behalten. Jeder andere Spawn (Strg+R, neues Fahrzeug mit gleicher ID,
-- Teile-/Musterwechsel) → Skin aus, danach frische Kopien der aktuellen Materialien (M1.1: ein neu gespawnter
-- ETKI erbte über dieselbe ID das Muster des vorigen).
M.onSpawnCCallback = function(vid)
  local car = cars[vid]
  if not car or not car.phase then return end
  local veh = be:getObjectByID(vid) or scenetree.findObject(vid)
  if not veh then return end
  if car.phase == "respawn" then
    veh:setSkin(SLOT .. "." .. skinOf(vid))
  else
    veh:setSkin(SLOT .. ".")
    car.phase, car.r = "renew", nil
  end
end

M.onVehicleSpawned = function(vid)
  local veh = be:getObjectByID(vid); if not veh then return end
  local car = cars[vid]
  if car and car.phase == "respawn" then
    attach(veh)
  elseif car and car.phase == "renew" then
    prepare(veh)  -- Strg+R / neues Fahrzeug / Teilewechsel: frisch kopieren, Zustand neu (Konzept: Mesh geändert/repariert)
  elseif vid == be:getPlayerVehicleID(0) then
    activate(vid)
  end
end

M.onVehicleSwitched = function(oldId, newId)
  if newId and newId >= 0 and not cars[newId] then activate(newId) end
end

M.onVehicleResetted = function(vid)
  local car = cars[vid]
  if car and car.phase == "active" and car.r then
    local veh = be:getObjectByID(vid)
    if veh then car.r:clear(veh) end   -- Reset repariert das Auto → Patina weg (Konzept, Zustandsmodell)
  end
end

M.onVehicleDestroyed = function(vid)
  local car = cars[vid]
  if car and car.phase ~= "respawn" then deleteSkinMaterials(car); cars[vid] = nil end
end

M.onExtensionLoaded = function()
  L("I", "Patina geladen.")
  local pv = be:getPlayerVehicleID(0)
  if pv and pv >= 0 then activate(pv) end
end

-- Konsole: patina_main.status()
M.status = function()
  for vid, car in pairs(cars) do
    L("I", "Fahrzeug %d: Phase %s, %d Ebenen, %d in Warteschlange, %d Schrammen, %d verworfen (Budget), %d ohne Treffer",
      vid, tostring(car.phase), car.r and #car.r.layers or 0, car.r and #car.r.queue or 0, car.scrapes or 0,
      car.r and car.r.dropped or 0, car.r and car.r.misses or 0)
  end
end
-- Diagnose: künstlicher Kratzer mitten auf einer Seite (ohne Sensor). side = "left" | "right" | "top"
M.testScratch = function(side)
  local vid = be:getPlayerVehicleID(0); local car = cars[vid]; local veh = be:getObjectByID(vid)
  if not (car and car.r and veh) then L("E", "testScratch: Fahrzeug nicht aktiv"); return end
  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local c = (mn + mx) * 0.5
  local n = ({ left = vec3(1, 0, 0), right = vec3(-1, 0, 0), top = vec3(0, 0, 1) })[side or "left"]
  local pos = vec3(n.x > 0 and mx.x or (n.x < 0 and mn.x or c.x), c.y, n.z > 0 and mx.z or c.z)
  car.r:request({ pos = pos, normal = n, up = vec3(0, -1, 0), width = 0.05, length = 0.6, depth = 0.4,
    texture = SCRATCH.texture, color = SCRATCH.color, strength = 1, name = "Patina Test" })
  L("I", "testScratch(%s): pos %s", tostring(side), tostring(pos))
end

M.clear = function()
  local vid = be:getPlayerVehicleID(0); local car = cars[vid]
  if car and car.r then car.r:clear(be:getObjectByID(vid)) end
end

return M
