-- Grit – Sensor im Fahrzeug-Lua. Misst nur und schickt kompakte Ereignisse an GE (grit_main.onSensorEvents).
-- Geladen per controller.loadControllerExternal("grit/sensor", "gritSensor", {}) (vehicle/controller.lua:297).
-- Quellen siehe FINDINGS.md Spike 5: nodeCollision(p) (vehicle/main.lua:491-501), obj:getSimTime,
-- obj:getDirectionVector/-Up (vehicle/ai.lua:41), v.data.nodes[cid].pos = Ausgangsposition im Fahrzeugraum
-- (vehicle/bdebugImpl.lua:648), obj:queueGameEngineLua (vehicle/ai.lua:5730).
--
-- M1: Schrammen. Ein Karosserie-Knoten (nicht Reifen, materialID2 ~= 4 RUBBER, Spike 5) gleitet mit
-- slipVel > SCRAPE_SLIP über etwas → Ereignis mit Ort, Fläche (Normale) und Schleifrichtung im Fahrzeugraum.

local M = {}
M.type = "auxiliary"

local SCRAPE_SLIP = 1.5        -- m/s Gleitgeschwindigkeit
local NODE_COOLDOWN = 0.15     -- s pro Knoten (M1.1: Budget nach 300 Schrammen voll)
local SEND_INTERVAL = 0.1      -- s
local MAX_PER_SEND = 12
local RUBBER = 4

local pending, lastEmit = {}, {}
local sendT = 0
local axF, axU, axL            -- Fahrzeugachsen in Welt (vorne, oben, links), pro Frame
-- Decal-Raum = Ausgangspositionen relativ zum Referenzknoten (M1.1 Lauf 3: ohne Abzug ~0.32 m seitlich versetzt;
-- Ausgangsposition des Referenzknotens wie vehicle/bdebugImpl.lua:648)
local refPos
-- Rad-Knoten (Felge/Nabe aus Metall rutschen am Reifenfilter vorbei, M1.1 Lauf 5): wheels.wheels[i].nodes/.treadNodes
-- (vehicle/wheels.lua:183,200,1091-1092)
local wheelNodes = {}
local SOFT = { [7] = true, [8] = true, [9] = true }   -- FOLIAGE, CLOTH, WATER (particles.json:2-35)
local center = vec3(0, 0, 0)  -- Mittelpunkt der Ausgangspositionen relativ zum Referenzknoten

-- Weltvektor → Fahrzeugraum (jbeam: +x links, −y vorne, +z oben; Spike 1)
local function toLocal(w)
  return vec3(w:dot(axL), -w:dot(axF), w:dot(axU))
end

local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end

-- M2 Radspritzer: pro Rad Strecke auf losem Untergrund sammeln; je SPRAY_DIST Meter ein Ereignis.
-- Daten: wheels.wheels[i].wheelSpeed (vorzeichenbehaftet, vehicle/wheels.lua:654-658), .contactMaterialID1/2
-- und .downForceRaw (wheels.lua:374), .node1/.node2 (Achs-Knoten), .radius, .isBroken.
local SPRAY_DIST = 12          -- m Fahrstrecke pro Spritzer-Ereignis und Rad
local SPRAY_MIN_SPEED = 3      -- m/s
local LOOSE = { [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true, [22] = true }
local wheelInfo, sprayDose, sprays = {}, {}, {}

local function updateSpray(dt)
  for i, w in pairs(wheelInfo) do
    local wd = wheels.wheels[i]
    if wd and not wd.isBroken then
      local mat = wd.contactMaterialID1
      if mat == RUBBER then mat = wd.contactMaterialID2 end
      local spd = wd.wheelSpeed or 0
      if LOOSE[mat] and (wd.downForceRaw or 0) > 0 and math.abs(spd) > SPRAY_MIN_SPEED then
        -- Schlupf schleudert mehr: Strecke + Schlupfgeschwindigkeit
        sprayDose[i] = (sprayDose[i] or 0) + (math.abs(spd) + math.abs(wd.lastSlip or 0)) * dt
        if sprayDose[i] >= SPRAY_DIST then
          sprayDose[i] = 0
          table.insert(sprays, { w = i, m = mat, v = r3(spd), s = r3(wd.lastSlip or 0),
            cx = w.cx, cy = w.cy, cz = w.cz, ox = w.ox, r = w.r })
        end
      end
    end
  end
end


-- M2.2 Staub: trockener, loser Untergrund ab mittlerem Tempo (Konzept). Häufigstes Kontaktmaterial der Räder;
-- je DUST_DIST Meter ein Ereignis. Tempo: obj:getVelocity() (vehicle/controller/dragTimer.lua:60).
local DUST_DIST = 15          -- M2.2 Lauf 3: 35 m gab zu wenig Staub
local DUST_MIN_SPEED = 8       -- m/s ≈ 30 km/h
local DUSTY = { [14] = true, [15] = true, [16] = true, [17] = true, [19] = true }
local dustDose, dusts = 0, {}

local function updateDust(dt)
  local count, best, bestN = {}, nil, 0
  for i in pairs(wheelInfo) do
    local wd = wheels.wheels[i]
    if wd and not wd.isBroken and (wd.downForceRaw or 0) > 0 then
      local mat = wd.contactMaterialID1
      if mat == RUBBER then mat = wd.contactMaterialID2 end
      if DUSTY[mat] then
        count[mat] = (count[mat] or 0) + 1
        if count[mat] > bestN then best, bestN = mat, count[mat] end
      end
    end
  end
  local spd = obj:getVelocity():length()
  if not best or bestN < 2 or spd < DUST_MIN_SPEED then return end
  dustDose = dustDose + spd * dt
  if dustDose >= DUST_DIST then
    dustDose = 0
    table.insert(dusts, { m = best, v = r3(spd) })
  end
end

local function initWheels()
  wheelInfo, sprayDose, sprays = {}, {}, {}
  for i = 0, (wheels.wheelCount or 0) - 1 do
    local wd = wheels.wheels[i]
    local a, b = wd and v.data.nodes[wd.node1], wd and v.data.nodes[wd.node2]
    if a and b and refPos then
      local c = (vec3(a.pos) + vec3(b.pos)) * 0.5 - refPos
      -- äußerer Achs-Knoten = weiter von der Fahrzeugmitte (x) weg; Mitte grob aus allen Rädern, unten
      wheelInfo[i] = { cx = r3(c.x), cy = r3(c.y), cz = r3(c.z), r = r3(wd.radius or 0.35),
        ax = a.pos.x - refPos.x, bx = b.pos.x - refPos.x }
    end
  end
  local sum, n = 0, 0
  for _, w in pairs(wheelInfo) do sum, n = sum + w.cx, n + 1 end
  local mid = n > 0 and sum / n or 0
  for _, w in pairs(wheelInfo) do
    w.ox = r3((math.abs(w.ax - mid) > math.abs(w.bx - mid)) and w.ax or w.bx)
  end
end

-- Diagnose (M2.2 Lauf 6: Leitplanke ohne Kratzer): Karosserie-Kontakte nach Grund und Untergrund zählen
-- Diagnose an/aus: tools/build_release.ps1 setzt DIAG = false fürs Release
local DIAG = true
local diag, diagT = {}, 0
local function count(reason, mat) if not DIAG then return end; local k = reason .. ":" .. tostring(mat); diag[k] = (diag[k] or 0) + 1 end

-- M2.3 Kontakt-Dreck (Konzept: Karosserie-Knoten berührt weichen Boden → Dreck genau an der Kontaktstelle).
-- Weicher Boden schmiert statt zu kratzen; Schotter (19) und Fels kratzen weiter.
local SMEAR = { [14] = true, [15] = true, [16] = true, [17] = true, [18] = true, [20] = true, [22] = true }
local DIRT_COOLDOWN = 0.3
local lastDirt, contacts = {}, {}

local function contactDirt(p, cid)
  local now = obj:getSimTime()
  if lastDirt[cid] and now - lastDirt[cid] < DIRT_COOLDOWN then return end
  lastDirt[cid] = now
  local node = v.data.nodes[cid]
  if not node or not refPos then return end
  local n = -toLocal(vec3(p.normal))
  if n.z < -0.6 then return end                       -- Unterboden: unsichtbar
  local off = vec3(node.pos) - refPos - center
  if off:length() > 0.1 and n:dot(off:normalized()) < -0.3 then return end
  table.insert(contacts, { c = cid, px = r3(node.pos.x - refPos.x), py = r3(node.pos.y - refPos.y),
    pz = r3(node.pos.z - refPos.z), nx = r3(n.x), ny = r3(n.y), nz = r3(n.z), v = r3(p.slipVel), m = p.materialID1 })
end

-- M4 Risse (Konzept: Kunststoff-Knoten bekommt Einschlag über Schwellwert oder ein angrenzender Beam bricht).
-- Kunststoff = nodeMaterial 3 (vehicle/beamstate.lua:886, dort Plastiksplitter beim Bruch).
-- Bruch = Controller-Feld beamBroken(id, energy) (vehicle/controller.lua:596, main.lua:371), Beam über
-- v.data.beams[id] (beamstate.lua:820).
-- Einschlag: p.perpendicularVel ist an Kunststoff-Knoten immer 0 (M4.1 Lauf 2: 546 Kollisionen, max 0.0) →
-- stattdessen Delle = Verschiebung gegen die Ausgangslage, wie die Debug-Ansicht „displacement“:
-- obj:getNodePositionRelative(cid) − obj:getOriginalNodePositionRelative(cid) (vehicle/bdebugImpl.lua:1057-1058).
-- Je DENT_STEP weiterer Eindrückung ein Riss.
local DENT_STEP = 0.03          -- m
local DENT_INTERVAL = 0.25      -- s
-- M5.3 (Covet): Log 13:00:04–20 delleMax bis 118 m → Teil abgerissen und mitgeschleift, jeder Schritt gab Risse.
-- Ab DENT_MAX gilt der Knoten als abgerissen/zerstört: keine weiteren Risse von ihm.
local DENT_MAX = 0.4            -- m
-- Haarrisse am Covet-Heck 5 s nach jedem Laden ohne Crash (Delle 0.03–0.04, Einfedern) → erst nach DENT_SETTLE
-- Sekunden messen und die Lage dann als Ausgangslage nehmen.
local DENT_SETTLE = 2.0         -- s
local CRACK_COOLDOWN = 1.0      -- s pro Knoten
local plastic, lastCrack, cracks = {}, {}, {}
local dentDone, dentT, dentMax = {}, 0, 0
local dentAge, dentBase = 0, nil   -- M5.3: Einfeder-Zeit und Ausgangslage nach dem Spawn

-- Richtung auf die Hauptachse runden (keine Flächennormale bekannt)
local function snapAxis(d)
  local ax, ay, az = math.abs(d.x), math.abs(d.y), math.abs(d.z)
  if ax >= ay and ax >= az then return vec3(d.x > 0 and 1 or -1, 0, 0) end
  if ay >= az then return vec3(0, d.y > 0 and 1 or -1, 0) end
  return vec3(0, 0, d.z > 0 and 1 or -1)
end

local function addCrack(cid, n, kind, val, dir)
  local now = obj:getSimTime()
  if lastCrack[cid] and now - lastCrack[cid] < CRACK_COOLDOWN then count("riss-pause", kind); return end
  local node = v.data.nodes[cid]
  if not node or not refPos then return end
  if n.z < -0.6 then count("riss-unten", kind); return end
  lastCrack[cid] = now
  count("riss", kind)
  table.insert(cracks, { c = cid, k = kind, v = r3(val), px = r3(node.pos.x - refPos.x), py = r3(node.pos.y - refPos.y),
    pz = r3(node.pos.z - refPos.z), nx = r3(n.x), ny = r3(n.y), nz = r3(n.z),
    dx = r3(dir and dir.x or 0), dy = r3(dir and dir.y or 0), dz = r3(dir and dir.z or 0) })
end

local function beamBroken(id, energy)
  local b = v.data.beams[id]
  if not b or not refPos then return end
  local cid = plastic[b.id1] and b.id1 or (plastic[b.id2] and b.id2 or nil)
  if not cid or wheelNodes[cid] then return end
  local n = snapAxis(vec3(v.data.nodes[cid].pos) - refPos - center)   -- von der Fahrzeugmitte nach außen
  local a, c = v.data.nodes[b.id1].pos, v.data.nodes[b.id2].pos
  addCrack(cid, n, "bruch", energy or 0, vec3(c) - vec3(a))
end

local function updateDents(dt)
  dentT = dentT + dt
  dentAge = dentAge + dt
  if dentT < DENT_INTERVAL or not refPos or dentAge < DENT_SETTLE then return end
  dentT = 0
  local t = HighPerfTimer()
  local maxD = 0
  local first = not dentBase
  if first then dentBase = {} end
  for cid in pairs(plastic) do
    local d = obj:getNodePositionRelative(cid)
    d:setSub(obj:getOriginalNodePositionRelative(cid))
    if first then dentBase[cid] = vec3(d) end
    d:setSub(dentBase[cid])
    local len = d:length()
    if len > maxD then maxD = len end
    local done = dentDone[cid] or 0
    if len > DENT_MAX then
      if done < math.huge then dentDone[cid] = math.huge; count("delle-abgerissen") end
    elseif len >= done + DENT_STEP then
      dentDone[cid] = len
      -- eingedrückt → außen ist entgegen der Verschiebung; Riss quer zur Verschiebung
      addCrack(cid, snapAxis(-d), "delle", len, d)
    end
  end
  local ms = t:stop()
  if DIAG and maxD > dentMax + 0.01 then
    dentMax = maxD
    count("delleMax", string.format("%.2f m %.2f ms", maxD, ms))
  end
end

local function nodeCollision(p)
  if p.materialID2 == RUBBER or not axF then return end
  local cid = p.id1
  if wheelNodes[cid] then return end
  if SMEAR[p.materialID1] then contactDirt(p, cid); return end
  if p.slipVel < SCRAPE_SLIP then if p.slipVel > 0.3 then count("langsam", p.materialID1) end; return end
  if SOFT[p.materialID1] then count("weich", p.materialID1); return end   -- Büsche/Stoff/Wasser kratzen nicht (M2.2 Lauf 4: Busch → schwarze Flächen)
  local now = obj:getSimTime()
  if lastEmit[cid] and now - lastEmit[cid] < NODE_COOLDOWN then count("pause", p.materialID1); return end
  lastEmit[cid] = now
  local node = v.data.nodes[cid]
  if not node or not refPos then return end
  -- p.normal = Normale der getroffenen Fläche (zeigt zum Auto hin) → nach außen am Auto = −normal (M1.1: Striche unsichtbar)
  local n = -toLocal(vec3(p.normal))
  -- Unterboden (Fläche zeigt nach unten): unsichtbar, und die Projektion von unten färbte senkrechte Flächen in
  -- Streifen (M2.2 Lauf 2: Aufsetzen auf Schotter → 121 Schrammen, senkrechte Streifen an der Bordwand)
  if n.z < -0.6 then count("unten", p.materialID1); return end
  -- Normale zeigt ins Auto (Büsche: n quer zur Karosserie, M2.2 Lauf 4) → Projektion streift schräg über Haube
  local off = vec3(node.pos) - refPos - center
  if off:length() > 0.1 and n:dot(off:normalized()) < -0.3 then count("innen", p.materialID1); return end
  count("ok", p.materialID1)
  local s = toLocal(vec3(p.slipVec))
  table.insert(pending, {
    c = cid, px = r3(node.pos.x - refPos.x), py = r3(node.pos.y - refPos.y), pz = r3(node.pos.z - refPos.z),
    nx = r3(n.x), ny = r3(n.y), nz = r3(n.z), sx = r3(s.x), sy = r3(s.y), sz = r3(s.z),
    v = r3(p.slipVel), f = r3(p.normalForce or 0), m1 = p.materialID1, m2 = p.materialID2,
  })
end

-- M3.1 Waschen: Wasserstand am Auto. obj:inWater(cid) (vehicle/fire.lua:87, controller/playerController.lua:376)
-- für alle Knoten alle WATER_INTERVAL s; Wasserlinie = höchste Ausgangsposition (Fahrzeugraum, relativ zum
-- Referenzknoten) eines Knotens im Wasser. Verformung bleibt unberücksichtigt.
local WATER_INTERVAL = 0.5
local waterT, water = 0, nil

local function updateWater(dt)
  waterT = waterT + dt
  if waterT < WATER_INTERVAL or not refPos then return end
  waterT = 0
  local t = HighPerfTimer()   -- Kosten messen (vehicle/jbeam/stage2.lua:592,610)
  local top, n = nil, 0
  for cid, node in pairs(v.data.nodes) do
    if node.pos and obj:inWater(cid) then
      n = n + 1
      local z = node.pos.z - refPos.z
      if not top or z > top then top = z end
    end
  end
  local ms = t:stop()
  if n > 0 then water = { z = r3(top), n = n, v = r3(obj:getVelocity():length()), ms = r3(ms) } end
end

local function updateGFX(dt)
  axF = obj:getDirectionVector()
  axU = obj:getDirectionVectorUp()
  axL = axU:cross(axF)
  updateSpray(dt)
  updateDust(dt)
  updateWater(dt)
  updateDents(dt)
  diagT = diagT + dt
  if diagT >= 2 then
    diagT = 0
    if next(diag) then
      obj:queueGameEngineLua(string.format("grit_main.onSensorDiag(%d, %s)", obj:getId(), serialize(diag)))
      diag = {}
    end
  end
  sendT = sendT + dt
  if sendT < SEND_INTERVAL then return end
  sendT = 0
  if #pending == 0 and #sprays == 0 and #dusts == 0 and #contacts == 0 and #cracks == 0 and not water then return end
  if #pending > MAX_PER_SEND then
    table.sort(pending, function(a, b) return a.v > b.v end)
    for i = #pending, MAX_PER_SEND + 1, -1 do pending[i] = nil end
  end
  obj:queueGameEngineLua(string.format("grit_main.onSensorEvents(%d, %s)", obj:getId(),
    serialize({ scrapes = pending, sprays = sprays, dusts = dusts, contacts = contacts, water = water, cracks = cracks })))
  pending, sprays, dusts, contacts, water, cracks = {}, {}, {}, {}, nil, {}
end

local function reset()
  pending, lastEmit, sendT, sprayDose, sprays, dustDose, dusts = {}, {}, 0, {}, {}, 0, {}
  lastDirt, contacts = {}, {}
  waterT, water = 0, nil
  lastCrack, cracks, dentDone, dentT, dentMax = {}, {}, {}, 0, 0
  dentAge, dentBase = 0, nil
end

local function init()
  local rn = v.data.refNodes and v.data.refNodes[0]
  local n = rn and v.data.nodes[rn.ref]
  refPos = n and vec3(n.pos) or nil
  if not refPos then log("W", "gritSensor", "Kein Referenzknoten – Schrammen aus") end
  if refPos then
    local sum, cnt = vec3(0, 0, 0), 0
    for _, nd in pairs(v.data.nodes) do if nd.pos then sum = sum + vec3(nd.pos); cnt = cnt + 1 end end
    center = cnt > 0 and (sum * (1 / cnt) - refPos) or vec3(0, 0, 0)
  end
  wheelNodes = {}
  for i = 0, (wheels.wheelCount or 0) - 1 do
    local wd = wheels.wheels[i]
    if wd then
      for _, n in pairs(wd.nodes or {}) do wheelNodes[n] = true end
      for _, n in pairs(wd.treadNodes or {}) do wheelNodes[n] = true end
    end
  end
  plastic = {}
  local np = 0
  for cid, nd in pairs(v.data.nodes) do if nd.nodeMaterial == 3 then plastic[cid] = true; np = np + 1 end end
  initWheels()
  reset()
  if DIAG then count("plastikKnoten", np) end
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.nodeCollision = nodeCollision
M.beamBroken = beamBroken

return M
