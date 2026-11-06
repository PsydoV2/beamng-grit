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
-- Kratzer in drei Tiefen (Konzept: leicht = Klarlack, mittel = Grundierung, tief = blankes Metall).
-- Masken aus tools/gen_textures.ps1. Dauerschrammen desselben Knotens: Treffer 1–2 leicht, 3–4 mittel, ab 5 tief;
-- jeder Treffer etwas versetzt entlang der Schleifrichtung → lange Spuren statt eines Flecks (M1.2 Lauf 1:
-- „schwer Kratzer zu bekommen“, alle Ebenen lagen genau übereinander). Harte Schramme mindestens mittel.
local SCRATCH = {
  depth = 0.25, minLen = 0.3, lenPerMs = 0.06, maxLen = 1.0,
  levels = {
    { texture = "/art/patina/scratch_light.png",  color = { 0.95, 0.95, 0.93 }, strength = 0.85, width = 0.12 },
    { texture = "/art/patina/scratch_medium.png", color = { 0.45, 0.45, 0.43 }, strength = 1.00, width = 0.12 },
    { texture = "/art/patina/scratch_deep.png",   color = { 0.75, 0.76, 0.78 }, strength = 1.00, width = 0.10 },
  },
  levelAt = { 1, 3, 5 }, -- ab diesem Treffer pro Knoten gilt Stufe 1/2/3
  hardSlip = 8,          -- m/s: ab hier mindestens mittel
  maxPerNode = 8,
  jitter = 0.5,          -- Versatz entlang Schleifrichtung, Anteil der Länge
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
  if #targets == 0 then   -- merken, sonst versucht onUpdate es alle 30 Frames erneut
    L("W", "Fahrzeug %d (%s): keine lackierten Materialien", vid, tostring(veh.jbeam))
    cars[vid] = { phase = "none", skinMats = (cars[vid] and cars[vid].skinMats) or {} }
    return
  end
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
    car.phase, car.wait = "prepareLater", 2   -- nicht im Spawn-Hook neu spawnen (M1.1 Lauf 4)
    return
  end
  car.retried = nil
  car.r, car.nodeHits, car.sprayCount = render.new(veh, onSkin, L), {}, {}
  car.phase = "active"
  loadSensor(veh)
  L("I", "Fahrzeug %d aktiv: %d/%d Materialien auf Patina%s, Neuspawn %.0f ms", vid, #onSkin, #targets,
    #missing > 0 and (" (ohne: " .. table.concat(missing, ", ") .. ")") or "", car.timer and car.timer:stopAndReset() or -1)
end

-- Aktivieren. Trägt das Fahrzeug noch einen Patina-Skin aus unbekanntem Zustand (z. B. nach Strg+L), erst Skin aus
-- und neu spawnen, damit frisch von den echten Materialien kopiert wird (M1.1 Lauf 2).
local function activate(vid)
  local veh = be:getObjectByID(vid)
  if not veh or (cars[vid] and cars[vid].phase) then return true end
  local vd = core_vehicle_manager.getVehicleData(vid)
  if not (vd and vd.config) then return false end   -- direkt nach Strg+L noch keine Fahrzeugdaten → später erneut
  local stale = false
  for _, t in ipairs(findTargets(veh)) do
    if t.objName:find("%." .. SLOT .. "%.") then stale = true; break end
  end
  if stale then
    local car = cars[vid] or { skinMats = {} }
    cars[vid] = car
    veh:setSkin(SLOT .. ".")
    car.phase = "renew"
    L("I", "Fahrzeug %d trägt alten Patina-Skin → Skin aus, Neuspawn", vid)
    if not respawn(veh) then car.phase = nil; return false end
    return true
  end
  prepare(veh)
  return cars[vid] ~= nil and cars[vid].phase ~= nil
end

-- M2 Dreck: feste Farbe pro Untergrund (collisiontype-IDs, particles.json:2-35; FINDINGS Spike 5).
-- Konzept-Frage „Tabelle oder Terrain-Textur“ → MVP Tabelle. Werte sRGB, Kodierung in render.variants.
local DIRT = {
  texture = "/art/patina/dirt_splash.png",
  colors = {
    [14] = { 0.55, 0.47, 0.36 }, -- DIRT_DUSTY
    [15] = { 0.36, 0.27, 0.18 }, -- DIRT
    [16] = { 0.72, 0.63, 0.46 }, -- SAND
    [17] = { 0.62, 0.55, 0.42 }, -- SANDY_ROAD
    [18] = { 0.22, 0.17, 0.11 }, -- MUD
    [19] = { 0.50, 0.47, 0.42 }, -- GRAVEL
    [20] = { 0.32, 0.29, 0.18 }, -- GRASS (Erde + Grün)
    [22] = { 0.93, 0.94, 0.96 }, -- SNOW
  },
  names = { [14] = "DIRT_DUSTY", [15] = "DIRT", [16] = "SAND", [17] = "SANDY_ROAD", [18] = "MUD", [19] = "GRAVEL",
            [20] = "GRASS", [22] = "SNOW" },
  minSize = 0.45, maxSize = 0.8, depth = 0.35,
  maxPerWheel = 30,      -- danach ist dieser Bereich „voll“ (Ebenen-Budget)
  rearChance = 0.3,      -- Hinterrad: Anteil der Spritzer aufs Heck
  maxStrength = 0.9, buildUp = 0.02,   -- Deckkraft je Bereich steigt pro Spritzer, nie abwärts
}

local function tint(c, s)   -- leichte Farbstreuung pro Spritzer
  local f = 1 + (math.random() - 0.5) * 0.15
  return { math.min(1, c[1] * f), math.min(1, c[2] * f), math.min(1, c[3] * f) }
end

local function handleSprays(car, vid, list)
  if not list or #list == 0 then return end
  local veh = be:getObjectByID(vid); if not veh then return end
  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local mid = (mn + mx) * 0.5
  car.sprayCount = car.sprayCount or {}
  for _, s in ipairs(list) do
    local col = DIRT.colors[s.m]
    local cnt = car.sprayCount[s.w] or 0
    if col and cnt < DIRT.maxPerWheel then
      local back = s.v >= 0 and 1 or -1        -- vorwärts (−y) → Spritzer nach hinten (+y)
      local side = (s.ox >= mid.x) and 1 or -1
      local pos, n, tol, up, w, h
      if s.cy * back > mid.y * back and math.random() < DIRT.rearChance then
        -- Hinterrad → Heck (bzw. Front bei Rückwärtsfahrt): großer, eher runder Fleck, zufällig gedreht
        pos = vec3(s.cx - side * s.r * 0.5 * math.random(), back > 0 and mx.y or mn.y, s.cz + s.r * (0.2 + 0.8 * math.random()))
        n, tol = vec3(0, back, 0), 0.5
        local a = math.random() * 2 * math.pi
        up = vec3(math.cos(a), 0, math.sin(a))
        w = DIRT.minSize + (DIRT.maxSize - DIRT.minSize) * math.random(); h = w
      else
        -- Seite hinter dem Rad: breit nach hinten gezogen (M2.1 Lauf 1: „großflächiger“). Höhe ab Achse aufwärts –
        -- unter der Achse verfehlten die Strahlen bei der D-Serie die Karosserie (10 von 10 verworfen).
        pos = vec3(s.ox, s.cy + back * s.r * (1.3 + 1.2 * math.random()), s.cz + s.r * (0.1 + 0.9 * math.random()))
        n, tol = vec3(side, 0, 0), 0.35
        local t = (math.random() - 0.5) * 0.6       -- ±17° Neigung
        up = vec3(0, math.sin(t), math.cos(t))      -- Länge = Höhe, Breite = entlang des Autos
        w = (DIRT.minSize + (DIRT.maxSize - DIRT.minSize) * math.random()) * 1.6
        h = DIRT.minSize + (DIRT.maxSize - DIRT.minSize) * math.random() * 0.7
      end
      -- M2.1 Lauf 2: „mal mehr, mal weniger Lackfarbe“ → ein schwächerer Spritzer über einem stärkeren zog die
      -- Deckkraft herunter; die additive Maske (blendMode 2 am Layer) wirkt offenbar nicht. Deshalb pro Bereich
      -- (Seite je Rad, Heck gemeinsam) nie schwächer als der vorige Spritzer, jeder legt etwas zu.
      car.dirtLevel = car.dirtLevel or {}
      local key = (n.y ~= 0) and ("heck" .. n.y) or ("rad" .. s.w)
      local want = math.min(0.75, 0.3 + math.abs(s.v) * 0.012 + math.abs(s.s) * 0.02)
      local strength = math.min(DIRT.maxStrength, math.max(car.dirtLevel[key] or 0, want))
      car.dirtLevel[key] = math.min(DIRT.maxStrength, strength + DIRT.buildUp)
      local ok = car.r:request({ pos = pos, normal = n, up = up, tolAlong = tol, region = key,
        width = w, length = h, depth = DIRT.depth, texture = DIRT.texture,
        color = tint(col), strength = strength, name = "Patina Dreck" })
      if ok then
        car.sprayCount[s.w] = cnt + 1
        car.sprays = (car.sprays or 0) + 1
        if car.sprays <= 10 then
          L("I", "Spritzer Rad %d %s %.1f m/s → pos(%.2f,%.2f,%.2f) n(%d,%d,%d)", s.w, DIRT.names[s.m] or "?", s.v,
            pos.x, pos.y, pos.z, n.x, n.y, n.z)
        end
      end
    end
  end
end

-- M2.2 Staub (Konzept: großflächige Noise-Decals, geringe Deckkraft, von hinten oder oben; lagert sich am Heck und
-- dünn auf Oberseiten ab). Deckkraft je Bereich monoton wie beim Dreck (M2.1 Lauf 2).
local DUST = {
  -- depth begrenzt: Die Box-Projektion färbt alles in der Box, egal wie die Fläche liegt (kein Winkeltest,
  -- shaders/common/dynamicDecals/decal.ps.hlsl:116-121). 0.6 m war zu viel (M2.2 Lauf 1); die „Formen“ kamen
  -- aber vor allem von Unterboden-Schrammen und abgeschnittenen Textur-Flecken (Lauf 2) → 0.3 m.
  -- M2.2 Lauf 3: „zu wenig, feiner Staub nimmt viel größere Flächen ein“ → größer, häufiger, auch an den Seiten
  -- (untere Hälfte). Abweichung vom Konzept (nur Heck + Oberseiten), von Sebastian gewünscht.
  texture = "/art/patina/dust.png", depth = 0.3,
  rear = { chance = 0.35, minSize = 1.0, maxSize = 1.5, start = 0.18, step = 0.01,  max = 0.5,  tol = 0.6 },
  side = { chance = 0.45, minSize = 1.0, maxSize = 1.6, start = 0.15, step = 0.008, max = 0.4,  tol = 0.5 },
  top  = {                minSize = 1.0, maxSize = 1.5, start = 0.12, step = 0.006, max = 0.28, tol = 1.2 },  -- tol: Ladefläche 1 m unter AABB-Oberkante
  maxEvents = 220,
}

local function handleDusts(car, vid, list)
  if not list or #list == 0 then return end
  local veh = be:getObjectByID(vid); if not veh then return end
  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local ext = mx - mn
  car.dirtLevel = car.dirtLevel or {}
  for _, s in ipairs(list) do
    local col = DIRT.colors[s.m]
    if col and (car.dusts or 0) < DUST.maxEvents then
      local r, rx, ry = math.random(), math.random(), math.random()
      local where, cfg, key, pos, n, up
      local a = math.random() * 2 * math.pi
      if r < DUST.rear.chance then          -- Heck: +y (Spike 1: −y vorne)
        where, cfg, key = "Heck", DUST.rear, "staubHeck"
        pos = vec3(mn.x + ext.x * (0.15 + 0.7 * rx), mx.y, mn.z + ext.z * (0.2 + 0.6 * ry))
        n, up = vec3(0, 1, 0), vec3(math.cos(a), 0, math.sin(a))
      elseif r < DUST.rear.chance + DUST.side.chance then   -- Seite, untere Hälfte, hinten dichter
        local sd = (math.random() < 0.5) and 1 or -1
        where, cfg, key = "Seite", DUST.side, "staubSeite" .. sd
        pos = vec3(sd > 0 and mx.x or mn.x, mn.y + ext.y * (0.05 + 0.9 * math.sqrt(rx)), mn.z + ext.z * (0.12 + 0.4 * ry))
        n, up = vec3(sd, 0, 0), vec3(0, math.cos(a), math.sin(a))
      else                                  -- Oberseite, hinten etwas dichter
        where, cfg, key = "oben", DUST.top, "staubOben"
        pos = vec3(mn.x + ext.x * (0.2 + 0.6 * rx), mn.y + ext.y * (0.25 + 0.75 * math.sqrt(ry)), mx.z)
        n, up = vec3(0, 0, 1), vec3(math.cos(a), math.sin(a), 0)
      end
      local size = cfg.minSize + (cfg.maxSize - cfg.minSize) * math.random()
      local strength = math.min(cfg.max, math.max(car.dirtLevel[key] or 0, cfg.start))
      car.dirtLevel[key] = math.min(cfg.max, strength + cfg.step)
      local ok = car.r:request({ pos = pos, normal = n, up = up, tolAlong = cfg.tol, region = key,
        width = size, length = size, depth = DUST.depth, texture = DUST.texture,
        color = tint(col), strength = strength, name = "Patina Staub" })
      if ok then
        car.dusts = (car.dusts or 0) + 1
        if car.dusts <= 10 then
          L("I", "Staub %s %.1f m/s → %s pos(%.2f,%.2f,%.2f) Deckkraft %.2f", DIRT.names[s.m] or "?", s.v,
            where, pos.x, pos.y, pos.z, strength)
        end
      end
    end
  end
end

-- Ereignisse vom Sensor ----------------------------------------------------------------

M.onSensorEvents = function(vid, ev)
  local car = cars[vid]
  if not car or car.phase ~= "active" or type(ev) ~= "table" then return end
  handleSprays(car, vid, ev.sprays)
  handleDusts(car, vid, ev.dusts)
  for _, s in ipairs(ev.scrapes or {}) do
    if (car.scrapes or 0) < 15 then
      L("I", "Schramme n%d pos(%.2f,%.2f,%.2f) n(%.2f,%.2f,%.2f) dir(%.2f,%.2f,%.2f) %.1f m/s mat %d/%d",
        s.c, s.px, s.py, s.pz, s.nx, s.ny, s.nz, s.sx, s.sy, s.sz, s.v, s.m1, s.m2)
    end
    car.nodeHits = car.nodeHits or {}
    local hits = car.nodeHits[s.c] or 0
    if hits < SCRATCH.maxPerNode then
      local level = 1
      for i, at in ipairs(SCRATCH.levelAt) do if hits + 1 >= at then level = i end end
      if s.v >= SCRATCH.hardSlip and level < 2 then level = 2 end
      local lv = SCRATCH.levels[level]
      local len = math.min(SCRATCH.maxLen, SCRATCH.minLen + s.v * SCRATCH.lenPerMs)
      local dir = vec3(s.sx, s.sy, s.sz)
      local pos = vec3(s.px, s.py, s.pz)
      if hits > 0 and dir:length() > 1e-3 then   -- erster Treffer genau am Knoten, weitere versetzt
        pos = pos + dir:normalized() * ((math.random() - 0.5) * len * SCRATCH.jitter)
      end
      local ok = car.r:request({
        pos = pos, normal = vec3(s.nx, s.ny, s.nz), up = dir,
        tolAlong = 0.1, region = "k",   -- M1.3 Lauf 2: Spiegel-Knoten stehen ab → Strahl trifft Motorhaube/Kotflügel 0.12–0.2 m innen
        width = lv.width, length = len, depth = SCRATCH.depth, texture = lv.texture,
        color = lv.color, strength = lv.strength, name = "Patina Kratzer " .. level,
      })
      if ok then car.scrapes = (car.scrapes or 0) + 1; car.nodeHits[s.c] = hits + 1 end
    end
  end
end

-- Hooks ------------------------------------------------------------------------------

local retryFrames = 0
-- Messung (M2.2 Lauf 1: Frames brechen am Anfang ein): Frametime getrennt nach „Patina arbeitet“ / „leerlauf“,
-- CPU-Zeit von render:update. Ausgabe und Zurücksetzen in M.status().
local perf = { busy = { n = 0, sum = 0, max = 0 }, idle = { n = 0, sum = 0, max = 0 }, upd = { n = 0, sum = 0, max = 0 } }
local function addPerf(t, ms) t.n, t.sum, t.max = t.n + 1, t.sum + ms, math.max(t.max, ms) end

M.onUpdate = function(dtReal)
  local busy = false
  for _, car in pairs(cars) do if car.r and #car.r.queue > 0 then busy = true end end
  if dtReal then addPerf(busy and perf.busy or perf.idle, dtReal * 1000) end
  -- Spielerfahrzeug ohne Patina? (neu, ersetzt mit gleicher ID, nach Strg+L, Fahrzeugwechsel) → aktivieren,
  -- bei Misserfolg alle 30 Frames erneut
  local pv = be:getPlayerVehicleID(0)
  if pv and pv >= 0 and not (cars[pv] and cars[pv].phase) then
    if retryFrames <= 0 then
      if not activate(pv) then retryFrames = 30 end
    else
      retryFrames = retryFrames - 1
    end
  end
  for vid, car in pairs(cars) do
    if car.phase == "prepareLater" then
      car.wait = car.wait - 1
      local veh = car.wait <= 0 and be:getObjectByID(vid)
      if veh then car.phase = nil; prepare(veh) end
    end
    if car.phase == "active" and car.r then
      local veh = be:getObjectByID(vid)
      if veh then
        local tu = hptimer()
        car.r:update(veh)
        addPerf(perf.upd, tu:stopAndReset())
      end
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
    -- Strg+R / neues Fahrzeug / Teilewechsel: frisch kopieren, Zustand neu (Konzept: Mesh geändert/repariert).
    -- Nicht hier im Spawn-Hook neu spawnen – das blieb liegen (M1.1 Lauf 4) → 2 Frames später in onUpdate.
    car.phase, car.wait = "prepareLater", 2
  end
  -- neue Spielerfahrzeuge aktiviert onUpdate (auch bei Ersetzen mit gleicher ID, core/vehicles.lua:1780-1794)
end

M.onVehicleResetted = function(vid)
  local car = cars[vid]
  if car and car.phase == "active" and car.r then
    local veh = be:getObjectByID(vid)
    if veh then car.r:clear(veh); car.nodeHits, car.sprayCount, car.dirtLevel, car.dusts = {}, {}, {}, 0 end   -- Reset repariert das Auto → Patina weg (Konzept, Zustandsmodell)
  end
end

M.onVehicleDestroyed = function(vid)
  local car = cars[vid]
  if car and car.phase ~= "respawn" and car.phase ~= "renew" then deleteSkinMaterials(car); cars[vid] = nil end
end

M.onExtensionLoaded = function()
  L("I", "Patina geladen.")
end

-- Konsole: patina_main.status()
M.status = function()
  for vid, car in pairs(cars) do
    L("I", "Fahrzeug %d: Phase %s, %d Ebenen, %d in Warteschlange, %d Schrammen, %d Spritzer, %d Staub, %d verworfen (Budget), %d ohne Treffer",
      vid, tostring(car.phase), car.r and #car.r.layers or 0, car.r and #car.r.queue or 0, car.scrapes or 0, car.sprays or 0, car.dusts or 0,
      car.r and car.r.dropped or 0, car.r and car.r.misses or 0)
    if car.r then
      local cells = 0
      for _ in pairs(car.r.cells or {}) do cells = cells + 1 end
      L("I", "  Spike 6: %d synthetisch, %d übersprungen (Zelle verfehlt), %d Zellen", car.r.synthN or 0, car.r.skipped or 0, cells)
    end
    if car.r and (car.r.bakeN or 0) > 0 then
      L("I", "  Bake: %d Decals, Ø %.2f ms, max %.2f ms", car.r.bakeN, car.r.bakeSum / car.r.bakeN, car.r.bakeMax)
    end
  end
  local function fmt(t) return t.n > 0 and string.format("%d Frames Ø %.1f ms max %.1f ms", t.n, t.sum / t.n, t.max) or "–" end
  L("I", "Frametime Patina arbeitet: %s | Leerlauf: %s | render:update CPU: %s", fmt(perf.busy), fmt(perf.idle), fmt(perf.upd))
  perf = { busy = { n = 0, sum = 0, max = 0 }, idle = { n = 0, sum = 0, max = 0 }, upd = { n = 0, sum = 0, max = 0 } }
end
-- Diagnose: künstlicher Kratzer mitten auf einer Seite (ohne Sensor). side = "left" | "right" | "top"
M.testScratch = function(side, level, tilt)   -- tilt: Grad, Spur nach oben/vorne geneigt (Vorzeichen-Test)
  local vid = be:getPlayerVehicleID(0); local car = cars[vid]; local veh = be:getObjectByID(vid)
  if not (car and car.r and veh) then L("W", "testScratch: Patina ist für dieses Fahrzeug (noch) nicht aktiv"); return end
  local aabb = veh:getSpawnLocalAABB()
  local mn, mx = vec3(aabb.minExtents), vec3(aabb.maxExtents)
  local c = (mn + mx) * 0.5
  local n = ({ left = vec3(1, 0, 0), right = vec3(-1, 0, 0), top = vec3(0, 0, 1) })[side or "left"]
  local pos = vec3(n.x > 0 and mx.x or (n.x < 0 and mn.x or c.x), c.y, n.z > 0 and mx.z or c.z)
  local lv = SCRATCH.levels[level or 3] or SCRATCH.levels[3]
  local a = math.rad(tilt or 0)
  local up = n.z > 0.5 and vec3(-math.sin(a), -math.cos(a), 0) or vec3(0, -math.cos(a), math.sin(a))
  car.r:request({ pos = pos, normal = n, up = up, width = 0.2, length = 0.6, depth = 0.4,
    texture = lv.texture, color = lv.color, strength = lv.strength, name = "Patina Test" })
  L("I", "testScratch(%s): pos %s", tostring(side), tostring(pos))
end

-- Spike 6: synthetische Decals an/aus (Vergleich)
M.synthetic = function(on) render.SYNTHETIC = on and true or false; L("I", "Synthetische Decals: %s", tostring(render.SYNTHETIC)) end

M.clear = function()
  local vid = be:getPlayerVehicleID(0); local car = cars[vid]
  if car and car.r then car.r:clear(be:getObjectByID(vid)); car.nodeHits, car.sprayCount, car.dirtLevel, car.dusts = {}, {}, {}, 0 end
end

return M
