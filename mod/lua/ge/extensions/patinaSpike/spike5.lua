-- Patina – Spike 5: Ereignis-Logger. Lädt den Fahrzeug-Controller patinaSpike/eventLogger ins Spielerfahrzeug
-- (vehicle/controller.lua:297 loadControllerExternal) und schreibt dessen Zusammenfassungen (5 pro Sekunde)
-- in <User>/patina_spike.log. Wegwerf-Prototyp.
--
-- Konsole (GE - Lua):
--   extensions.load("patinaSpike_spike5")
--   patinaSpike_spike5.start()     -- Logger ins Spielerfahrzeug laden
--   patinaSpike_spike5.mark("x")   -- Markierung ins Log (z. B. vor jedem Fahrabschnitt)
--   patinaSpike_spike5.stop()      -- entladen + Zusammenfassung

local M = {}
local logTag = "patinaSpike5"
local CTRL_FILE, CTRL_NAME = "patinaSpike/eventLogger", "patinaSpikeLogger"

local SPIKE_LOG = "/patina_spike.log"
local function L(level, fmt, ...)
  local msg = string.format(fmt, ...)
  log(level, logTag, msg)
  local f = io.open(SPIKE_LOG, "a")
  if f then f:write(string.format("%s|%s|%s\n", os.date("%H:%M:%S"), level, msg)); f:close() end
end

local state = nil

local function loadCtrl(veh)
  veh:queueLuaCommand(string.format('controller.loadControllerExternal(%q, %q, {})', CTRL_FILE, CTRL_NAME))
end

local function newTotals()
  return { msgs = 0, impacts = 0, maxPerp = 0, maxDmg = 0, cpuColl = 0, cpuGfx = 0, frames = 0, contacts = 0 }
end

M.start = function()
  local veh = getPlayerVehicle(0); if not veh then L("E", "Kein Spielerfahrzeug."); return end
  if state then L("W", "Läuft schon."); return end
  state = { vehId = veh:getID(), tot = newTotals() }
  loadCtrl(veh)
  L("I", "start(): Logger in %s (ID %d) geladen.", veh.jbeam, state.vehId)
end

M.mark = function(txt) L("I", "---- MARKE %s ----", tostring(txt)) end

local function summary()
  local t = state.tot
  L("I", "=== Zusammenfassung: %d Meldungen, %d Frames, %d Kontakte, %d Stöße (max %.1f m/s), max Schaden/Fenster %.0f",
    t.msgs, t.frames, t.contacts, t.impacts, t.maxPerp, t.maxDmg)
  if t.frames > 0 then
    L("I", "CPU im Fahrzeug-Lua: nodeCollision Ø %.4f ms/Frame, updateGFX Ø %.4f ms/Frame",
      t.cpuColl / t.frames, t.cpuGfx / t.frames)
  end
end

M.stop = function()
  if not state then return end
  local veh = be:getObjectByID(state.vehId)
  if veh then veh:queueLuaCommand(string.format('controller.unloadControllerExternal(%q)', CTRL_NAME)) end
  summary()
  state = nil
end

-- vom Fahrzeug-Lua aufgerufen
M.onVehicleEvents = function(vehId, m)
  if not state or vehId ~= state.vehId or type(m) ~= "table" then return end
  local t = state.tot
  t.msgs, t.frames, t.contacts = t.msgs + 1, t.frames + (m.frames or 0), t.contacts + (m.contacts or 0)
  t.impacts = t.impacts + #(m.impacts or {})
  t.maxPerp = math.max(t.maxPerp, m.maxPerp or 0)
  t.maxDmg = math.max(t.maxDmg, m.dmg or 0)
  t.cpuColl, t.cpuGfx = t.cpuColl + (m.cpuColl or 0), t.cpuGfx + (m.cpuGfx or 0)

  local bm = {}
  for k, n in pairs(m.byMat or {}) do table.insert(bm, k .. ":" .. n) end
  local imp = {}
  for _, i in ipairs(m.impacts or {}) do table.insert(imp, string.format("n%d %.1fm/s mat%d (%.2f,%.2f,%.2f)", i.n, i.v, i.m, i.x, i.y, i.z)) end
  L("I", "ev v=%.1f räder[%s] slip=%.2f | kontakte=%d [%s] perp=%.1f slipV=%.1f | wasser=%.2f g=%.1f dmg=%.0f | cpu %.3f/%.3f ms%s",
    (m.speed or 0) * 3.6, m.wheelMat or "", m.wheelSlip or 0, m.contacts or 0, table.concat(bm, " "),
    m.maxPerp or 0, m.maxSlip or 0, m.water or 0, m.g or 0, m.dmg or 0, m.cpuColl or 0, m.cpuGfx or 0,
    #imp > 0 and (" | STOSS " .. table.concat(imp, "; ")) or "")
end

-- Neuspawn/Strg+R: Fahrzeug-Lua startet neu → Logger erneut laden
M.onVehicleSpawned = function(vid)
  if state and vid == state.vehId then
    local veh = be:getObjectByID(vid)
    if veh then loadCtrl(veh); L("I", "onVehicleSpawned(%d): Logger neu geladen.", vid) end
  end
end
M.onVehicleDestroyed = function(vid) if state and vid == state.vehId then summary(); state = nil end end
M.onExtensionUnloaded = function() M.stop() end

return M
