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

-- Weltvektor → Fahrzeugraum (jbeam: +x links, −y vorne, +z oben; Spike 1)
local function toLocal(w)
  return vec3(w:dot(axL), -w:dot(axF), w:dot(axU))
end

local function r3(x) return math.floor(x * 1000 + 0.5) / 1000 end

local function nodeCollision(p)
  if p.materialID2 == RUBBER or p.slipVel < SCRAPE_SLIP or not axF then return end
  local cid = p.id1
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
  sendT = sendT + dt
  if sendT < SEND_INTERVAL then return end
  sendT = 0
  if #pending == 0 then return end
  if #pending > MAX_PER_SEND then
    table.sort(pending, function(a, b) return a.v > b.v end)
    for i = #pending, MAX_PER_SEND + 1, -1 do pending[i] = nil end
  end
  obj:queueGameEngineLua(string.format("patina_main.onSensorEvents(%d, %s)", obj:getId(), serialize({ scrapes = pending })))
  pending = {}
end

local function reset()
  pending, lastEmit, sendT = {}, {}, 0
end

local function init()
  local rn = v.data.refNodes and v.data.refNodes[0]
  local n = rn and v.data.nodes[rn.ref]
  refPos = n and vec3(n.pos) or nil
  if not refPos then log("W", "patinaSensor", "Kein Referenzknoten – Schrammen aus") end
  reset()
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.nodeCollision = nodeCollision

return M
