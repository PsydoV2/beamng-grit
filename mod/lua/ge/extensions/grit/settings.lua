-- Grit – Einstellungen (M5.1, Konzept: Tabelle „Einstellungen“). Gespeichert in <User>/settings/grit.json wie
-- core/vehicle/mirror.lua:33-37 (jsonWriteFile/jsonReadFile, common/utils.lua:466,484).
-- Kein globaler Zustand: Modul per require, Zustand nur hier drin.

local S = {}

local FILE = "/settings/grit.json"

-- Schlüssel → { Standard, Typ, min, max | Auswahl }
local DEFS = {
  dirt         = { default = true,  kind = "bool" },
  scratches    = { default = true,  kind = "bool" },
  cracks       = { default = true,  kind = "bool" },
  dirtStrength = { default = 1.0,   kind = "number", min = 0.25, max = 2.0 },
  dryingSpeed  = { default = 1.0,   kind = "number", min = 0.25, max = 4.0 },
  -- Notion „Kratzer häufiger / Empfindlichkeit einstellbar“ (2026-11-13): 1.0 = bisheriges Verhalten.
  -- Höher = schon bei langsamerem Schleifen, kürzere Pause pro Knoten, mehr Kratzer pro Knoten.
  scratchSensitivity = { default = 1.0, kind = "number", min = 0.5, max = 2.0 },
  aiVehicles   = { default = false, kind = "bool" },          -- wirkt ab M5.3
}
S.ORDER = { "dirt", "scratches", "cracks", "dirtStrength", "dryingSpeed", "scratchSensitivity", "aiVehicles" }   -- quality gestrichen (M5.3 Lauf 2)

local values = {}

-- Wert prüfen und in den richtigen Typ bringen; nil = ungültig
local function coerce(key, v)
  local d = DEFS[key]
  if not d then return nil end
  if d.kind == "bool" then
    if v == true or v == "true" or v == 1 or v == "1" then return true end
    if v == false or v == "false" or v == 0 or v == "0" then return false end
    return nil
  elseif d.kind == "number" then
    local n = tonumber(v)
    if not n or n ~= n then return nil end
    return math.max(d.min, math.min(d.max, n))
  elseif d.kind == "choice" then
    return d.choices[v] and v or nil
  end
end

function S.load()
  values = {}
  for k, d in pairs(DEFS) do values[k] = d.default end
  local f = jsonReadFile(FILE)
  local bad = {}
  if type(f) == "table" then
    for k, v in pairs(f) do
      local c = coerce(k, v)
      if c ~= nil then values[k] = c else bad[#bad + 1] = tostring(k) end
    end
  end
  return f ~= nil, bad
end

function S.save()
  local out = {}
  for _, k in ipairs(S.ORDER) do out[k] = values[k] end
  return jsonWriteFile(FILE, out, true)
end

function S.get(key) return values[key] end

-- setzen + speichern; liefert (true, neuer Wert) oder (false, Grund)
function S.set(key, v)
  local d = DEFS[key]
  if not d then return false, "unbekannte Einstellung" end
  local c = coerce(key, v)
  if c == nil then
    if d.kind == "choice" then
      local ch = {}
      for k in pairs(d.choices) do ch[#ch + 1] = k end
      table.sort(ch)
      return false, "erlaubt: " .. table.concat(ch, ", ")
    end
    return false, d.kind == "bool" and "erlaubt: true/false" or "keine Zahl"
  end
  values[key] = c
  S.save()
  return true, c
end

function S.reset()
  for k, d in pairs(DEFS) do values[k] = d.default end
  S.save()
end

-- Zeile fürs Log: Schlüssel=Wert in fester Reihenfolge
function S.describe()
  local parts = {}
  for _, k in ipairs(S.ORDER) do
    local d = DEFS[k]
    local range = d.kind == "number" and string.format(" (%.2f–%.2f)", d.min, d.max) or ""
    parts[#parts + 1] = string.format("%s=%s%s", k, tostring(values[k]), range)
  end
  return table.concat(parts, ", ")
end

S.load()
return S
