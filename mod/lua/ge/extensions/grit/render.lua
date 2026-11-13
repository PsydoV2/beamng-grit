-- Grit – Zeichnen pro Fahrzeug (Weg A′, Ergebnis Spikes 2–4, siehe FINDINGS.md).
-- Zwei DecalProjections (Farbe @GritTexture, Maske @GritMask), gebunden per veh:setTextureSet
-- (editor/api/dynamicDecals.lua:1489-1500). Neue Decals über eine virtuelle Kamera projizieren
-- (projectDynamicDecals + getDecalData, wie der Editor), einzeln dazubacken (bakeLayers ohne clear,
-- dynamicDecals.lua:1091-1095). Kein globaler Zustand: render.new(vehId, targets) liefert ein Objekt.

local R = {}
R.__index = R

-- M5.3 Lauf 2: Qualitätsstufen gestrichen (Sebastian). 4096×2048 kaum sichtbar besser, Bake Ø 7 ms statt ≈ 1 ms.
local RESOLUTION = Point2I(2048, 1024)
local UV_LAYER = 1
R.COLOR_PREFIX, R.MASK_PREFIX = "@GritTexture", "@GritMask"
-- M5.3 Lauf 3 (Weg A, Sebastian): Schäden (Kratzer, Risse) in einem eigenen Texturpaar und einer eigenen
-- Material-Stage UNTER dem Dreck. Waschen und Trocknen ändern nur das Dreck-Paar → nichts muss neu gebacken werden
-- (vorher ≈ 2 ms je Schaden pro Waschschritt). Waschen legt Kratzer frei.
R.DMG_COLOR_PREFIX, R.DMG_MASK_PREFIX = "@GritDamage", "@GritDamageMask"
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

-- schwarz = unsichtbar in der Maske (Spike 2 Lauf 3: Deckkraft = Helligkeit). M5.3 Lauf 3: nach Strg+L war das ganze
-- Auto blau gefleckt (Datenreste, Screenshot 12-44-07) trotz Grundebene → Alpha 1 statt 0, damit die Fill-Ebene den
-- alten Inhalt sicher überschreibt statt ihn transparent stehen zu lassen.
local function baseLayer()
  return { type = 1, blendMode = 1, color = Point4F(0, 0, 0, 1), colorPaletteMapId = 0,
           enabled = true, locked = false, uid = uid("base"), name = "Grit Base", children = {} }
end

-- aus einem Grit-Layer (gritColor, gritStrength) die Farb- und die Masken-Variante
local function variants(l)
  if l.gritErase then   -- Radierer (Spike 7): nur Maske, schwarz mit Alpha = Stärke; Farbe bleibt
    local ml = shallowcopy(l); ml.color = Point4F(0, 0, 0, l.gritErase); ml.uid = l.uid .. "-m"
    return nil, ml
  end
  local c, s = l.gritColor, l.gritStrength
  local dk = 1 - R.WET_DARK * (l.gritWet or 0)   -- M3.2: nass = dunkler (ohne Glanz, Stage-Rauheit fest)
  local cl = shallowcopy(l); cl.color = Point4F(enc(c[1] * dk), enc(c[2] * dk), enc(c[3] * dk), 1); cl.uid = l.uid .. "-c"
  local e = enc(s); local ml = shallowcopy(l); ml.color = Point4F(e, e, e, 1); ml.uid = l.uid .. "-m"
  return cl, ml
end

function R.new(veh, targets, log)
  local self = setmetatable({}, R)
  self.vehId, self.log = veh:getID(), log
  self.layers, self.queue = {}, {}
  self.color = newProj(veh, targets)
  self.mask = newProj(veh, targets)
  self.dcolor = newProj(veh, targets)
  self.dmask = newProj(veh, targets)
  self.colorSet, self.maskSet = self.color:getTextureSet(), self.mask:getTextureSet()
  self.dcolorSet, self.dmaskSet = self.dcolor:getTextureSet(), self.dmask:getTextureSet()
  self:refresh(veh, true)
  self:rebake(veh)
  -- M5.1 Lauf 4: frisch gespawnte ETK zeigte ein buntes Punktraster (ungelöschter Speicher?) → leeren Stapel nach
  -- einigen Frames noch einmal backen, wenn die Render-Ziele sicher stehen
  self.initBake = { 5, 60 }
  return self
end

-- Diagnose M5.3: UV-Karte über das ganze Auto (Textur-Füllung, Layer-Felder wie editor/api/dynamicDecals.lua:1232-1243,
-- 307-315). Schaden-Paar zeigt die Karte voll deckend, Dreck wird ausgeblendet. Zurück mit R:clear.
function R:uvCheck(veh)
  local tf = { type = 2, blendMode = 1, color = Point4F(1, 1, 1, 1), colorPaletteMapId = 0,
    fillTexturePath = "/art/grit/uvcheck.png", scale = Point2F(1, 1), offset = Point2F(0, 0),
    enabled = true, locked = false, uid = uid("uv"), name = "Grit UV-Karte", children = {} }
  local white = baseLayer(); white.color = Point4F(1, 1, 1, 1)
  self.dcolor:clearBakedTextures(); self.dcolor:bakeLayers({ baseLayer(), tf }, veh.jbeam)
  self.dmask:clearBakedTextures();  self.dmask:bakeLayers({ white }, veh.jbeam)
  self.mask:clearBakedTextures();   self.mask:bakeLayers({ baseLayer() }, veh.jbeam)
  self.idleFrames = 0
end

-- Test M5.1 Lauf 4: Projektion nur auf bestimmte Meshes (geteilte UVs zwischen Meshes?)
function R:setTargets(veh, targets)
  for _, p in ipairs({ self.color, self.mask, self.dcolor, self.dmask }) do
    p:clearMaterialIdx()
    local seen = {}
    for _, t in ipairs(targets) do
      if not seen[t.idx] then p:addMaterialIdx(t.idx); seen[t.idx] = true end
    end
  end
  self:clear(veh)
end

-- full: Form neu setzen. M2.2 Lauf 4: projectDynamicDecals kostet 8–16 ms CPU je Aufruf; Verdacht, dass setShape
-- jeden Frame die Mesh-Aufbereitung neu anstößt → Form nur bei Neuanlage/Rebake setzen.
function R:refresh(veh, full)
  for _, x in ipairs({ { self.color, R.COLOR_PREFIX, self.colorSet }, { self.mask, R.MASK_PREFIX, self.maskSet },
                       { self.dcolor, R.DMG_COLOR_PREFIX, self.dcolorSet }, { self.dmask, R.DMG_MASK_PREFIX, self.dmaskSet } }) do
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
  local cs, ms, dcs, dms = { baseLayer() }, { baseLayer() }, { baseLayer() }, { baseLayer() }
  for _, l in ipairs(self.layers) do
    local cl, ml = variants(l)
    if R.isDamage(l) then dcs[#dcs + 1] = cl; dms[#dms + 1] = ml
    else if cl then cs[#cs + 1] = cl end; ms[#ms + 1] = ml end
  end
  local t = hptimer()
  self.color:clearBakedTextures(); self.color:bakeLayers(cs, veh.jbeam)
  self.mask:clearBakedTextures();  self.mask:bakeLayers(ms, veh.jbeam)
  self.dcolor:clearBakedTextures(); self.dcolor:bakeLayers(dcs, veh.jbeam)
  self.dmask:clearBakedTextures();  self.dmask:bakeLayers(dms, veh.jbeam)
  self.idleFrames = 0   -- danach wieder zusammenführen
  return t:stopAndReset()
end

function R:clear(veh)
  self:refresh(veh, true)   -- Reparatur kann die Form ändern
  self.layers, self.queue, self.dryQueue, self.baked, self.committed = {}, {}, {}, 0, 0
  self.cells = {}            -- Oberflächen-Abstände neu lernen
  -- Test 2026-11-13: das zuletzt projizierte Decal blieb sichtbar, obwohl exportTextures danach leere Texturen
  -- zeigte. Der Editor leert beim Abschalten die dynamischen Texturen und kombiniert sofort
  -- (editor/api/dynamicDecals.lua:2242-2247) → hier ebenso für alle vier Projektionen.
  local all = { { self.color, self.colorSet }, { self.mask, self.maskSet }, { self.dcolor, self.dcolorSet },
                { self.dmask, self.dmaskSet } }
  for _, x in ipairs(all) do x[1]:flushDynamicTextures() end
  local ms = self:rebake(veh)
  for _, x in ipairs(all) do x[1]:combineTextures(x[2]) end
  return ms
end

-- Spike 6: Decals ohne Projektion. projectDynamicDecals kostet 12–15 ms CPU je Aufruf (M2.2 Lauf 5). Layer-Daten
-- lassen sich aus einer Vorlage selbst bauen (Dump Spike 6, FINDINGS): camPosition = Kamera, camDirection =
-- decalNorm = surfaceNormal = −n, viewToScreen = projM, worldToViewToScreen = projM · camM⁻¹ (nachgerechnet),
-- decalPos = Oberflächenpunkt. Unbekannt ist nur der Oberflächenpunkt → pro Zelle (0.4-m-Raster je Bereich) einmal
-- echt projizieren und den Abstand entlang n merken; danach synthetisch. Zellen, deren Strahl zweimal verfehlt,
-- werden übersprungen (Lücken, Radkästen).
R.SYNTHETIC = true
R.CELL = 0.4
R.SYN_PER_FRAME = 4
local function cellKey(d)
  local q = function(v) return math.floor(v / R.CELL + 0.5) end
  return string.format("%s:%d,%d,%d", d.region or "-", q(d.pos.x), q(d.pos.y), q(d.pos.z))
end

-- Kamera, Ausrichtung und Zelle für ein Decal. d = { pos, normal, up (vec3, Fahrzeugraum), width, length, depth,
-- texture, color{r,g,b}, strength, name, tolAlong?, region? }
local function buildReq(d)
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
  d.cell = cellKey(d)
  local camPos = d.pos + n * (d.depth * 0.5 + 0.2)
  local q = quatFromDir(-n, up)
  local camM = QuatF(q.x, q.y, q.z, q.w):getMatrix()
  camM:setPosition(camPos)
  return { d = d, n = n, camPos = camPos, camM = camM, projM = getCameraProjMatrix(), frames = 0 }
end

function R:request(d)
  if #self.layers + #self.queue >= R.MAX_LAYERS then self.dropped = (self.dropped or 0) + 1; return false end
  table.insert(self.queue, buildReq(d))
  return true
end

-- Spike 7 (M3 Waschen): Radierer. Eine große synthetische Box (Spike 6) wird schwarz nur in die Maske gebacken,
-- Alpha = Stärke (decal.ps.hlsl:222 alpha *= color.a) → Dreck darunter verblasst um diesen Anteil. Die Box färbt
-- ohne Winkeltest alles in ihr (decal.ps.hlsl:116-121) → eine Projektion von der Seite mit Tiefe = Fahrzeugbreite
-- trifft beide Seiten. Kratzer liegen in derselben Maske → danach die Kratzer in der Box neu darüber backen
-- (ans Ende der Liste verschoben, damit ein Voll-Bake dieselbe Reihenfolge hat). Inkrementell, kein Voll-Bake.
-- box = { pos (Mitte), normal, up, width, length, depth, strength, isKeep(layer) → true = neu darüber backen }
function R:erase(veh, box)
  if not self.template then return false, "noch keine Vorlage (erst ein echtes Decal nötig)" end
  local t = hptimer()
  local req = buildReq({ pos = box.pos, normal = box.normal, up = box.up, width = box.width, length = box.length,
    depth = box.depth, texture = R.SOLID, region = "radierer" })
  local data = self:synth(req, 0)
  data.uid, data.name, data.enabled, data.locked, data.children = uid("e"), "Grit Radierer", true, false, {}
  data.mirrored = false
  data.gritErase = box.strength
  local _, ml = variants(data)
  self.mask:bakeLayers({ ml }, veh.jbeam)   -- M5.3 Lauf 3: Schäden liegen im eigenen Paar, bleiben unberührt
  self.idleFrames = 0
  self.baked = (self.baked or 0) + 1
  return true, string.format("%.1f ms", t:stopAndReset())
end
R.SOLID = "/art/grit/solid.png"

-- M5.3 Zusammenführen (Konzept „Budget“: alte, stabile Ablagerungen in eine gebackene Ebene). Die Textur IST diese
-- gebackene Ebene: Die Liste braucht Grit nur noch für Schäden (Waschen backt sie neu obenauf, R:erase), nasse
-- Layer (R:dry) und das volle Neu-Backen – das läuft nur bei leerer Liste (R.new, R:clear). Trockener Dreck und
-- Radierer werden nie wieder gelesen → aus der Liste nehmen, sie bleiben in der Textur. Das Budget zählt danach nur
-- Schäden und nassen Dreck.
function R:retire()
  local keep, n = {}, 0
  for _, l in ipairs(self.layers) do
    if l.gritWet or l.gritDryQueued then keep[#keep + 1] = l else n = n + 1 end   -- M5.3 Lauf 3: Schäden auch nur in der Textur
  end
  if n > 0 then
    self.layers = keep
    self.baked = (self.baked or 0) + n
  end
  return n
end
-- Schäden (Kratzer, Test, Risse) bleiben beim Waschen und Trocknen obenauf
function R.isDamage(l)
  local n = l.name
  return n and (n:find("^Grit Kratzer") or n == "Grit Test" or n:find("^Grit Riss")) and true or false
end

-- M3.2 Trocknen. Nasse Layer (gritWet > 0) altern mit dt · rate (rate wächst mit Fahrtwind). Nach DRY_TIME/2 halb,
-- nach DRY_TIME ganz trocken. Dann nur die Farb-Variante neu backen: Die Maske bleibt, also kommt gewaschener Dreck
-- nicht zurück, und es entsteht kein neuer Layer. Kratzer in der Nähe bekommen danach ihre Farbe neu darüber
-- (sonst überdeckt die neue Dreckfarbe sie in der Farb-Textur).
R.WET_DARK = 0.45
R.DRY_TIME = 90
R.DRY_PER_FRAME = 4
local function stageOf(age) return age >= R.DRY_TIME and 0 or (age >= R.DRY_TIME * 0.5 and 0.5 or 1) end
function R:dry(veh, dt, rate)
  self.dryQueue = self.dryQueue or {}
  for _, l in ipairs(self.layers) do
    if l.gritWet and l.gritWet > 0 and not l.gritDryQueued then
      l.gritDryAge = (l.gritDryAge or 0) + dt * rate
      if stageOf(l.gritDryAge) < l.gritWet then l.gritDryQueued = true; table.insert(self.dryQueue, l) end
    end
  end
  if #self.dryQueue == 0 then return end
  local t, cs = hptimer(), {}
  for _ = 1, math.min(R.DRY_PER_FRAME, #self.dryQueue) do
    local l = table.remove(self.dryQueue, 1)
    l.gritWet, l.gritDryQueued = stageOf(l.gritDryAge), nil
    if l.gritWet <= 0 then l.gritWet = nil end
    local cl = variants(l); cs[#cs + 1] = cl
  end
  -- M5.3 Lauf 3: Schäden liegen im eigenen Paar, kein Neu-Färben mehr nötig
  self.color:bakeLayers(cs, veh.jbeam)
  self.idleFrames = 0
  self:retire()
  local ms = t:stopAndReset()
  self.dryN, self.drySum, self.dryMax = (self.dryN or 0) + 1, (self.drySum or 0) + ms, math.max(self.dryMax or 0, ms)
end

-- fertige Layer-Daten übernehmen und dazubacken
function R:commit(data, d, veh, how, mark)
  data.uid, data.name, data.enabled, data.locked, data.children = uid("p"), d.name or "Grit", true, false, {}
  data.gritColor, data.gritStrength = d.color, d.strength
  if (d.wet or 0) > 0 then data.gritWet, data.gritDryAge = d.wet, 0 end
  data.mirrored = false   -- Layer-Feld „mirrored“ (editor/api/dynamicDecals.lua:520,929); M1.1 Lauf 4
  -- M5.3: trockener Dreck bleibt nur in der Textur (R:retire), Schäden und nasser Dreck auch in der Liste
  if data.gritWet then table.insert(self.layers, data) else self.baked = (self.baked or 0) + 1 end
  self.committed = (self.committed or 0) + 1
  if self.log and self.committed <= 15 then
    self.log("I", "Decal %d (%s): pos %s (angefragt %s), Drehung %.0f°", self.committed, how, tostring(data.decalPos),
      tostring(d.pos), math.deg(d.rot or 0))
  end
  local cl, ml = variants(data)
  local tb = hptimer()
  local dmg = R.isDamage(data)
  ;(dmg and self.dcolor or self.color):bakeLayers({ cl }, veh.jbeam)
  ;(dmg and self.dmask or self.mask):bakeLayers({ ml }, veh.jbeam)
  local ms = tb:stopAndReset(); mark("bake")
  self.bakeN, self.bakeSum = (self.bakeN or 0) + 1, (self.bakeSum or 0) + ms
  self.bakeMax = math.max(self.bakeMax or 0, ms)
end

-- Layer-Daten ohne Projektion aus der Vorlage
function R:synth(req, off)
  local d, n = req.d, req.n
  local data = shallowcopy(self.template)
  data.decalColorTexturePath = d.texture
  data.camPosition, data.camDirection = vec3(req.camPos), -n
  data.decalNorm, data.surfaceNormal = -n, -n
  data.decalPos = d.pos + n * off
  data.viewToScreen = req.projM
  data.worldToViewToScreen = req.projM * req.camM:copy():inverse()
  data.decalScale = vec3(d.width, d.depth, d.length)
  data.decalRotation = d.rot or 0
  data.useSurfaceNormal, data.useLockedSurfaceNormal = false, false
  data.cursorPosScreenUv = { x = 0.5, y = 0.5 }
  return data
end

function R:update(veh)
  -- Abschnitts-Zeiten (M2.2 Lauf 3: render:update CPU max 36 ms) → bei > 8 ms aufschlüsseln
  local T, sec, total = hptimer(), {}, 0
  local function mark(name) local ms = T:stopAndReset(); total = total + ms; sec[#sec + 1] = string.format("%s %.1f", name, ms) end
  self:refresh(veh); mark("refresh")
  self.frameN = (self.frameN or 0) + 1
  if self.initBake and self.frameN == self.initBake[1] then
    table.remove(self.initBake, 1)
    if #self.initBake == 0 then self.initBake = nil end
    if #self.layers == 0 then self:rebake(veh) end
  end
  self.cells = self.cells or {}
  local worked = #self.queue > 0
  -- synthetische zuerst, mehrere pro Frame
  local syn = 0
  while syn < R.SYN_PER_FRAME do
    local req = self.queue[1]
    if not req or req.frames > 0 then break end
    local c = self.cells[req.d.cell]
    if c and (c.miss or 0) >= 2 and not c.off then
      self.skipped = (self.skipped or 0) + 1; table.remove(self.queue, 1)
    elseif R.SYNTHETIC and self.template and c and c.off then
      self:commit(self:synth(req, c.off), req.d, veh, "synthetisch", mark)
      self.synthN = (self.synthN or 0) + 1
      table.remove(self.queue, 1); syn = syn + 1
    else
      break
    end
  end
  local req = self.queue[1]
  if req and syn == 0 then
    local p, d = self.color, req.d
    if req.frames == 0 then
      -- Textur nur bei Wechsel setzen (Verdacht Ladespitze: render:update CPU max 30 ms, M2.2 Lauf 2)
      if self.curTexture ~= d.texture then p:setDecalTexturePath("color", d.texture); self.curTexture = d.texture end
      -- Vorschau während der Projektions-Frames unsichtbar: sie landet in der Live-Textur und blitzte weiß auf
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
      -- Treffer weit weg = Strahl hat das Auto verfehlt (M1.1 Lauf 3) oder ging durch eine Lücke (M1.3) →
      -- entlang der Normalen ≤ tolAlong, seitlich ≤ 0.25 m.
      local near, along = false, 0
      if hit and hit.x == hit.x then
        local off = hit - d.pos
        along = off:dot(req.n)
        near = math.abs(along) <= (d.tolAlong or 0.2) and (off - req.n * along):length() <= 0.25
      end
      local c = self.cells[d.cell] or {}
      self.cells[d.cell] = c
      if near then
        -- Zelle lernt den Abstand zur Oberfläche (gleitender Mittelwert)
        c.off = c.off and (c.off * 0.5 + along * 0.5) or along
        if not self.template then self.template = shallowcopy(data) end
        self:commit(data, d, veh, "projiziert", mark)
        p:flushDynamicTextures(); table.remove(self.queue, 1)
      elseif (hit and hit.x == hit.x) or req.frames >= FRAMES_MAX then   -- verfehlt: verwerfen, Zelle merkt es
        c.miss = (c.miss or 0) + 1
        self.misses = (self.misses or 0) + 1
        if self.log and self.misses <= 10 then
          self.log("I", "Decal verworfen: Treffer %s, angefragt %s", tostring(hit), tostring(d.pos))
        end
        p:flushDynamicTextures(); table.remove(self.queue, 1)
      end
    end
  end
  -- Zusammenführen nur, solange gearbeitet wird, und sonst alle 60 Frames (Leerlauf kostete 0.6 ms CPU je Frame)
  self.idleFrames = worked and 0 or (self.idleFrames or 0) + 1
  if worked or self.idleFrames <= 3 or self.idleFrames % 60 == 0 then
    self.color:combineTextures(self.colorSet)
    self.mask:combineTextures(self.maskSet)
    self.dcolor:combineTextures(self.dcolorSet)
    self.dmask:combineTextures(self.dmaskSet)
  end
  mark("combine")
  if total > 8 and self.log and (self.spikes or 0) < 10 then
    self.spikes = (self.spikes or 0) + 1
    self.log("I", "render:update %.1f ms: %s", total, table.concat(sec, ", "))
  end
end

return R
