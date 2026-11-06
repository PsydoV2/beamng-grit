-- Patina – Sensor im Fahrzeug-Lua. Misst nur und schickt kompakte Ereignisse an GE (patina_main.onSensorEvents).
-- Geladen per controller.loadControllerExternal("patina/sensor", "patinaSensor", {}) (vehicle/controller.lua:297).
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

local function nodeCollision(p)
  if p.materialID2 == RUBBER or p.slipVel < SCRAPE_SLIP or not axF then return end
  local cid = p.id1
  if wheelNodes[cid] then return end
  local now = obj:getSimTime()
  if lastEmit[cid] and now - lastEmit[cid] < NODE_COOLDOWN then return end
  lastEmit[cid] = now
  local node = v.data.nodes[cid]
  if not node or not refPos then return end
  -- p.normal = Normale der getroffenen Fläche (zeigt zum Auto hin) → nach außen am Auto = −normal (M1.1: Striche unsichtbar)
  local n = -toLocal(vec3(p.normal))
  local s = toLocal(vec3(p.slipVec))
  table.insert(pending, {
    c = cid, px = r3(node.pos.x - refPos.x), py = r3(node.pos.y - refPos.y), pz = r3(node.pos.z - refPos.z),
    nx = r3(n.x), ny = r3(n.y), nz = r3(n.z), sx = r3(s.x), sy = r3(s.y), sz = r3(s.z),
    v = r3(p.slipVel), f = r3(p.normalForce or 0), m1 = p.materialID1, m2 = p.materialID2,
  })
end

local function updateGFX(dt)
  axF = obj:getDirectionVector()
  axU = obj:getDirectionVectorUp()
  axL = axU:cross(axF)
  updateSpray(dt)
  sendT = sendT + dt
  if sendT < SEND_INTERVAL then return end
  sendT = 0
  if #pending == 0 and #sprays == 0 then return end
  if #pending > MAX_PER_SEND then
    table.sort(pending, function(a, b) return a.v > b.v end)
    for i = #pending, MAX_PER_SEND + 1, -1 do pending[i] = nil end
  end
  obj:queueGameEngineLua(string.format("patina_main.onSensorEvents(%d, %s)", obj:getId(),
    serialize({ scrapes = pending, sprays = sprays })))
  pending, sprays = {}, {}
end

local function reset()
  pending, lastEmit, sendT, sprayDose, sprays = {}, {}, 0, {}, {}
end

local function init()
  local rn = v.data.refNodes and v.data.refNodes[0]
  local n = rn and v.data.nodes[rn.ref]
  refPos = n and vec3(n.pos) or nil
  if not refPos then log("W", "patinaSensor", "Kein Referenzknoten – Schrammen aus") end
  wheelNodes = {}
  for i = 0, (wheels.wheelCount or 0) - 1 do
    local wd = wheels.wheels[i]
    if wd then
      for _, n in pairs(wd.nodes or {}) do wheelNodes[n] = true end
      for _, n in pairs(wd.treadNodes or {}) do wheelNodes[n] = true end
    end
  end
  initWheels()
  reset()
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.nodeCollision = nodeCollision

return M
