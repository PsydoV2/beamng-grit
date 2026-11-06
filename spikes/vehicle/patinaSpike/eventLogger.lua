-- Patina – Spike 5: Ereignis-Logger im Fahrzeug-Lua. Wegwerf-Prototyp.
-- Geladen zur Laufzeit über controller.loadControllerExternal("patinaSpike/eventLogger", "patinaSpikeLogger", {})
-- (vehicle/controller.lua:297-374, Datei unter lua/vehicle/controller/<fileName>.lua).
-- Quellen (alle im Spiel-Lua belegt):
--   nodeCollision(p): jeder Knoten-Kontakt, Felder aus vehicle/main.lua:491-501 (pos, normal, perpendicularVel,
--                     slipVel, depth, materialID1/2); Controller-Hook: vehicle/controller.lua:186,605.
--   Räder: wheels.wheels[i].contactMaterialID1/2, lastSlip, wheelSpeed, contactDepth (vehicle/sounds.lua:429,
--          vehicleController.lua:363-367).
--   Wasser: obj:inWater(cid) (vehicle/controller/playerController.lua:376).
--   Schaden: beamstate.damage (vehicle/ai.lua:4379). g-Kräfte: sensors.gx/gy/gz (vehicle/sensors.lua:7-29).
--   Materialnamen: particles.getMaterialsParticlesTable() (common/particles.lua, Reihenfolge = IDs, particles.json).
--   Timer: HighPerfTimer() (vehicle/beamstate.lua:1542). An GE senden: obj:queueGameEngineLua (vehicle/ai.lua:5730).

local M = {}
M.type = "auxiliary"

local SEND_INTERVAL = 0.2      -- s
local IMPACT_VEL = 2.0         -- m/s senkrecht → als Stoß werten
local MAX_IMPACTS = 8          -- pro Fenster
local WATER_SAMPLE_STEP = 8    -- jeden n-ten Knoten auf Wasser prüfen

local matNames = {}
local sampleNodes = {}
local win, timer, cpu
local lastDamage = 0
local sendT = 0

local function newWindow()
  return { contacts = 0, byMat = {}, impacts = {}, maxPerp = 0, maxSlip = 0, wheelMat = {}, wheelSlip = 0,
           speedMax = 0, gMax = 0, waterMax = 0, frames = 0 }
end

local function nodeCollision(p)
  timer:stopAndReset()
  win.contacts = win.contacts + 1
  local key = p.materialID1 .. "/" .. p.materialID2
  win.byMat[key] = (win.byMat[key] or 0) + 1
  if p.perpendicularVel > win.maxPerp then win.maxPerp = p.perpendicularVel end
  if p.slipVel > win.maxSlip then win.maxSlip = p.slipVel end
  if p.perpendicularVel > IMPACT_VEL and #win.impacts < MAX_IMPACTS then
    local pos = obj:getNodePosition(p.id1)   -- relativ zum Fahrzeug-Ursprung
    table.insert(win.impacts, { n = p.id1, v = math.floor(p.perpendicularVel * 10 + 0.5) / 10,
      m = p.materialID2, x = math.floor(pos.x * 100) / 100, y = math.floor(pos.y * 100) / 100, z = math.floor(pos.z * 100) / 100 })
  end
  cpu.coll = cpu.coll + timer:stopAndReset()
end

local function updateGFX(dt)
  timer:stopAndReset()
  win.frames = win.frames + 1
  local speed = obj:getGroundSpeed()
  if speed > win.speedMax then win.speedMax = speed end

  for i = 0, wheels.wheelCount - 1 do
    local wd = wheels.wheels[i]
    if wd then
      local m = wd.contactMaterialID1
      if m == 4 then m = wd.contactMaterialID2 end   -- 4 = RUBBER (Reifen selbst), wie sounds.lua:430-432
      if m and m >= 0 then win.wheelMat[m] = (win.wheelMat[m] or 0) + 1 end
      if (wd.lastSlip or 0) > win.wheelSlip then win.wheelSlip = wd.lastSlip end
    end
  end

  local wet = 0
  for _, cid in ipairs(sampleNodes) do if obj:inWater(cid) then wet = wet + 1 end end
  local wetFrac = #sampleNodes > 0 and wet / #sampleNodes or 0
  if wetFrac > win.waterMax then win.waterMax = wetFrac end

  local g = math.sqrt(sensors.gx * sensors.gx + sensors.gy * sensors.gy + (sensors.gz - 9.81) * (sensors.gz - 9.81)) / 9.81
  if g > win.gMax then win.gMax = g end
  cpu.gfx = cpu.gfx + timer:stopAndReset()

  sendT = sendT + dt
  if sendT >= SEND_INTERVAL then
    local wm = {}
    for id, n in pairs(win.wheelMat) do table.insert(wm, (matNames[id] or tostring(id)) .. "=" .. n) end
    local dmg = beamstate.damage or 0
    local msg = {
      t = sendT, frames = win.frames, speed = win.speedMax, wheelMat = table.concat(wm, ","), wheelSlip = win.wheelSlip,
      contacts = win.contacts, byMat = win.byMat, maxPerp = win.maxPerp, maxSlip = win.maxSlip, impacts = win.impacts,
      water = win.waterMax, g = win.gMax, dmg = dmg - lastDamage, cpuColl = cpu.coll, cpuGfx = cpu.gfx,
    }
    lastDamage = dmg
    obj:queueGameEngineLua(string.format("patinaSpike_spike5.onVehicleEvents(%d, %s)", obj:getId(), serialize(msg)))
    win, sendT, cpu = newWindow(), 0, { coll = 0, gfx = 0 }
  end
end

local function reset()
  win, sendT, cpu = newWindow(), 0, { coll = 0, gfx = 0 }
  lastDamage = beamstate.damage or 0
end

local function init()
  timer = HighPerfTimer()
  local mats = particles.getMaterialsParticlesTable()
  for id, m in pairs(mats or {}) do matNames[id] = m.name end
  sampleNodes = {}
  local i = 0
  for cid, _ in pairs(v.data.nodes or {}) do
    if i % WATER_SAMPLE_STEP == 0 then table.insert(sampleNodes, cid) end
    i = i + 1
  end
  reset()
  log("I", "patinaSpikeLogger", string.format("init: %d Materialnamen (ID 10 = %s), %d Wasser-Prüfknoten",
    tableSize(matNames), tostring(matNames[10]), #sampleNodes))
end

M.init = init
M.reset = reset
M.updateGFX = updateGFX
M.nodeCollision = nodeCollision

return M
