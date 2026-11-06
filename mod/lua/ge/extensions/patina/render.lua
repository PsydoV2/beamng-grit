-- Patina – Zeichnen pro Fahrzeug (Weg A′, Ergebnis Spikes 2–4, siehe FINDINGS.md).
-- Zwei DecalProjections (Farbe @PatinaTexture, Maske @PatinaMask), gebunden per veh:setTextureSet
-- (editor/api/dynamicDecals.lua:1489-1500). Neue Decals über eine virtuelle Kamera projizieren
-- (projectDynamicDecals + getDecalData, wie der Editor), einzeln dazubacken (bakeLayers ohne clear,
-- dynamicDecals.lua:1091-1095). Kein globaler Zustand: render.new(vehId, targets) liefert ein Objekt.

local R = {}
R.__index = R

local RESOLUTION = Point2I(2048, 1024)
local UV_LAYER = 1
R.COLOR_PREFIX, R.MASK_PREFIX = "@PatinaTexture", "@PatinaMask"
local USE_MOUSE_POS = bit.lshift(1, 2)
local FRAMES_BEFORE_READ, FRAMES_MAX = 3, 30
R.PROJECT_EVERY = 3        -- Projektion einmal, dann 3 Frames warten bis getDecalData (Spike 3: 3 Frames nötig)
R.MAX_LAYERS = 500   -- Budget. Spike 3: Voll-Bake wächst überlinear – gebraucht nur bei clear (leer) und Neuanlage (leer);
                     -- inkrementell 0.8 ms/Decal unabhängig von der Anzahl. M2: 100 reicht für Kratzer + Dreck nicht.

-- Layer-Farben werden beim Bake sRGB → linear gewandelt (Spike 2b Lauf 5) → vorher kodieren
local function enc(v) return math.pow(v, 1 / 2.2) end
local function uid(p) return string.format("%s-%06X", p, math.random(0, 0xFFFFFF)) end

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

local function baseLayer()   -- schwarz = unsichtbar in der Maske (Spike 2 Lauf 3)
  return { type = 1, blendMode = 1, color = Point4F(0, 0, 0, 0), colorPaletteMapId = 0,
           enabled = true, locked = false, uid = uid("base"), name = "Patina Base", children = {} }
end

-- aus einem Patina-Layer (patinaColor, patinaStrength) die Farb- und die Masken-Variante
local function variants(l)
  local c, s = l.patinaColor, l.patinaStrength
  local cl = shallowcopy(l); cl.color = Point4F(enc(c[1]), enc(c[2]), enc(c[3]), 1); cl.uid = l.uid .. "-c"
  local e = enc(s); local ml = shallowcopy(l); ml.color = Point4F(e, e, e, 1); ml.uid = l.uid .. "-m"
  return cl, ml
end

function R.new(veh, targets, log)
  local self = setmetatable({}, R)
  self.vehId, self.log = veh:getID(), log
  self.layers, self.queue = {}, {}
  self.color = newProj(veh, targets)
  self.mask = newProj(veh, targets)
  self.colorSet, self.maskSet = self.color:getTextureSet(), self.mask:getTextureSet()
  self:refresh(veh, true)
  self:rebake(veh)
  return self
end

-- full: Form neu setzen. M2.2 Lauf 4: projectDynamicDecals kostet 8–16 ms CPU je Aufruf; Verdacht, dass setShape
-- jeden Frame die Mesh-Aufbereitung neu anstößt → Form nur bei Neuanlage/Rebake setzen.
function R:refresh(veh, full)
  for _, x in ipairs({ { self.color, R.COLOR_PREFIX, self.colorSet }, { self.mask, R.MASK_PREFIX, self.maskSet } }) do
    local p = x[1]
    veh:setTextureSet(x[2], x[3])
    if full or not self.shapeSet then p:setShape(veh:getDecalProjectionShape()) end
    p:setWorldTransform(veh:getRefNodeMatrix())
    p:setTransform(veh:getRefNodeMatrix():copy():setPosition(vec3(0, 0, 0)):inverse())
  end
  self.shapeSet = true
end

-- alles neu backen (teuer, nur bei Spawn/Reset)
function R:rebake(veh)
  local cs, ms = { baseLayer() }, { baseLayer() }
  for _, l in ipairs(self.layers) do
    local cl, ml = variants(l); table.insert(cs, cl); table.insert(ms, ml)
  end
  local t = hptimer()
  self.color:clearBakedTextures(); self.color:bakeLayers(cs, veh.jbeam)
  self.mask:clearBakedTextures();  self.mask:bakeLayers(ms, veh.jbeam)
  self.idleFrames = 0   -- danach wieder zusammenführen
  return t:stopAndReset()
end

function R:clear(veh)
  self:refresh(veh, true)   -- Reparatur kann die Form ändern
  self.layers, self.queue = {}, {}
  self:rebake(veh)
end

-- Decal anfragen. d = { pos, normal, up (vec3, Fahrzeugraum), width, length, depth, texture, color{r,g,b}, strength, name }
function R:request(d)
  if #self.layers + #self.queue >= R.MAX_LAYERS then self.dropped = (self.dropped or 0) + 1; return false end
  local n = d.normal:normalized()
  local up = d.up - n * d.up:dot(n)
  if up:length() < 1e-3 then up = math.abs(n.z) < 0.9 and vec3(0, 0, 1) or vec3(0, 1, 0) end
  up = up:normalized()
  -- Ausrichtung: Die Projektion ignoriert die Kamera-Rolle (M1.2 Lauf 2/3: up gedreht → keine Änderung).
  -- Sie richtet nach Normale + decalRotation aus (Layer-Felder decalNorm/decalRotation,
  -- editor/api/dynamicDecals.lua:905,1789-1794). Gemessen bei Rotation 0: Seite (n=±x) Länge entlang z,
  -- Dach (n=z) entlang y (M1.2 Lauf 1, Screenshot 20-52-12) → Bezugsachse = z in die Fläche projiziert,
  -- auf waagerechten Flächen y (Annahme). Drehsinn gemessen M1.2 Lauf 4: negativ.
  local function inPlane(a) return a - n * a:dot(n) end
  local ref = inPlane(vec3(0, 0, 1))
  if ref:length() < 0.3 then ref = inPlane(vec3(0, 1, 0)) end
  ref = ref:normalized()
  local rot = -math.atan2(ref:cross(up):dot(n), ref:dot(up))
  if rot < 0 then rot = rot + 2 * math.pi end
  d.rot = rot
  local camPos = d.pos + n * (d.depth * 0.5 + 0.2)
  local q = quatFromDir(-n, up:normalized())
  local camM = QuatF(q.x, q.y, q.z, q.w):getMatrix()
  camM:setPosition(camPos)
  table.insert(self.queue, { d = d, camM = camM, projM = getCameraProjMatrix(), frames = 0 })
  return true
end

-- pro Frame höchstens eine Anfrage bearbeiten (3 Frames Projektion bis getDecalData, Spike 3)
function R:update(veh)
  -- Abschnitts-Zeiten (M2.2 Lauf 3: render:update CPU max 36 ms) → bei > 8 ms aufschlüsseln
  local T, sec, total = hptimer(), {}, 0
  local function mark(name) local ms = T:stopAndReset(); total = total + ms; sec[#sec + 1] = string.format("%s %.1f", name, ms) end
  self:refresh(veh); mark("refresh")
  local req = self.queue[1]
  if req then
    local p, d = self.color, req.d
    if req.frames == 0 then
      -- Textur nur bei Wechsel setzen (Verdacht Ladespitze: render:update CPU max 30 ms, M2.2 Lauf 2)
      if self.curTexture ~= d.texture then p:setDecalTexturePath("color", d.texture); self.curTexture = d.texture end
      -- Vorschau während der 3 Projektions-Frames unsichtbar: sie landet in der Live-Textur und blitzte weiß auf
      -- (M2.1 Lauf 3). Layer-Farbe setzt variants() danach ohnehin neu.
      p.decalColor = Point4F(1, 1, 1, 0)
      p.decalScale = vec3(d.width, d.depth, d.length)
      p.decalRotation = d.rot or 0
      p.useSurfaceNormal = false
      p.mirrored = false          -- editor/api/dynamicDecals.lua:2484
    end
    if bit.band(p:getSettings(), USE_MOUSE_POS) == USE_MOUSE_POS then p:toggleSetting(USE_MOUSE_POS) end
    p.cursorPosition = Point2F(0.5, 0.5)
    mark("setup")
    -- nur jeden PROJECT_EVERY-ten Frame projizieren (vorher jeden Frame = 3 Aufrufe je Decal, M2.2 Lauf 4)
    if req.frames % R.PROJECT_EVERY == 0 then p:projectDynamicDecals(req.camM, req.projM) end; mark("project")
    req.frames = req.frames + 1
    if req.frames >= FRAMES_BEFORE_READ then
      local ok, data = pcall(function() return p:getDecalData(req.camM, req.projM) end); mark("getDecalData")
      local hit = ok and data and data.decalPos and vec3(data.decalPos)
      -- Treffer weit weg = Strahl hat das Auto verfehlt (M1.1 Lauf 3: Welt-Koordinaten wie (12711, 1490, …))
      -- M1.3: Strahl durch eine Lücke trifft innen liegende Lackflächen (D-Serie: Unterboden → Motorhaube von
      -- innen, Vertex: Seite → 0.43 m innen) → getrennt prüfen: entlang der Normalen ≤ 0.2 m, seitlich ≤ 0.25 m.
      -- Gute Treffer: ≤ 0.13 m entlang n (testScratch ab AABB), ≤ 0.1 m seitlich.
      local near = false
      if hit and hit.x == hit.x then
        local off = hit - d.pos
        local nn = d.normal:normalized()
        local along = off:dot(nn)
        near = math.abs(along) <= (d.tolAlong or 0.2) and (off - nn * along):length() <= 0.25
      end
      if near then
        data.uid, data.name, data.enabled, data.locked, data.children = uid("p"), d.name or "Patina", true, false, {}
        data.patinaColor, data.patinaStrength = d.color, d.strength
        data.mirrored = false   -- Layer-Feld „mirrored“ (editor/api/dynamicDecals.lua:520,929); M1.1 Lauf 4: Striche auf der Gegenseite
        table.insert(self.layers, data)
        -- Spike 6 (Decals ohne Projektion): Felder der ersten 3 Treffer samt eigener Kamera ins Log
        if self.log and (self.dumps or 0) < 3 then
          self.dumps = (self.dumps or 0) + 1
          local keys = {}
          for k in pairs(data) do keys[#keys + 1] = k end
          table.sort(keys)
          self.log("I", "DUMP %d: angefragt pos %s n %s up %s Breite %.2f Länge %.2f Tiefe %.2f", self.dumps,
            tostring(d.pos), tostring(d.normal), tostring(d.up), d.width, d.length, d.depth)
          self.log("I", "DUMP %d: camM %s", self.dumps, tostring(req.camM))
          self.log("I", "DUMP %d: projM %s", self.dumps, tostring(req.projM))
          for _, k in ipairs(keys) do
            local v = data[k]
            if k ~= "children" then
              self.log("I", "DUMP %d: %s = %s", self.dumps, k, type(v) == "table" and dumps(v):gsub("%s+", " ") or tostring(v))
            end
          end
        end
        if self.log and #self.layers <= 15 then
          self.log("I", "Decal %d: Treffer %s (angefragt %s), Drehung %.0f° → Layer %.0f°", #self.layers, tostring(hit),
            tostring(d.pos), math.deg(d.rot or 0), math.deg(data.decalRotation or -1))
        end
        local cl, ml = variants(data)
        local tb = hptimer()
        self.color:bakeLayers({ cl }, veh.jbeam)
        self.mask:bakeLayers({ ml }, veh.jbeam)
        local ms = tb:stopAndReset(); mark("bake")
        self.bakeN, self.bakeSum = (self.bakeN or 0) + 1, (self.bakeSum or 0) + ms
        self.bakeMax = math.max(self.bakeMax or 0, ms)
        p:flushDynamicTextures(); table.remove(self.queue, 1)
      elseif (hit and hit.x == hit.x) or req.frames >= FRAMES_MAX then   -- weit weg: sofort verwerfen
        self.misses = (self.misses or 0) + 1
        if self.log and self.misses <= 10 then
          self.log("I", "Decal verworfen: Treffer %s, angefragt %s", tostring(hit), tostring(d.pos))
        end
        p:flushDynamicTextures(); table.remove(self.queue, 1)
      end
    end
  end
  -- Zusammenführen nur, solange gearbeitet wird, und sonst alle 60 Frames (Leerlauf kostete 0.6 ms CPU je Frame)
  self.idleFrames = req and 0 or (self.idleFrames or 0) + 1
  if req or self.idleFrames <= 3 or self.idleFrames % 60 == 0 then
    self.color:combineTextures(self.colorSet)
    self.mask:combineTextures(self.maskSet)
  end
  mark("combine")
  if total > 8 and self.log and (self.spikes or 0) < 10 then
    self.spikes = (self.spikes or 0) + 1
    self.log("I", "render:update %.1f ms: %s", total, table.concat(sec, ", "))
  end
end

return R
