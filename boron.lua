-- boron.lua — автоматическое производство arcon:hull_boron_snow (Карбид-борная броня, Снежная)
-- CC: Tweaked 1.116, Create 6.0.10, Create: Armored Constructs 1.05.
-- Механизмы находятся сами по проводной сети; склады один раз назначаются в настройке (клавиша S).

local VERSION = "v11"   -- видна на экранах: так понятно, что обновление встало
local STATUS_MON = "left"   -- монитор вплотную слева от компьютера: экран «что подключено»
local DIR = (shell and fs.getDir(shell.getRunningProgram())) or ""
local R = dofile(fs.combine(DIR, "recipes.lua"))
local CFG_FILE = fs.combine(DIR, "armor.cfg")

---------------------------------------------------------------- настройки и мелочи
local TICK = 1            -- секунд между циклами
local PER_CRUSH = 16      -- сколько предметов класть в дробилку за раз
local PER_WASH = 16       -- на депо промывки
local PER_MILL = 16       -- в жернова
local PER_BASIN = 16      -- партий в бассейн
local PER_FURNACE = 16    -- партий в печь
local BASIN_TRIAL = 40    -- сек: если бассейн за это время не тронул ингредиенты — у него другой механизм
local STALL = 300         -- сек без прогресса -> предупреждение

local cfg = {raw = {}, stock = {}, output = {}, waste = {}, basins = {}, lines = {}, lineJobs = {}, active = false, target = 1, done = 0}
local AUTO_EVERY = 10     -- сек: как часто при работе проверять, хватает ли на следующую броню
local MAX_BATCH = 4      -- сколько брони планировать за один заход
local function loadCfg()
  if fs.exists(CFG_FILE) then
    local f = fs.open(CFG_FILE, "r"); local t = textutils.unserialize(f.readAll()); f.close()
    if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
  end
end
local function saveCfg()
  local f = fs.open(CFG_FILE, "w"); f.write(textutils.serialize(cfg)); f.close()
end

local FLUID_NAMES = {["minecraft:water"] = "Water (mB)", ["minecraft:lava"] = "Lava (mB)"}
local function iname(i) return R.names[i] or FLUID_NAMES[i] or i end
local function sortedKeys(t)
  local k = {}
  for x in pairs(t or {}) do k[#k + 1] = x end
  table.sort(k)
  return k
end
local function call(p, m, ...)
  local ok, a, b = pcall(peripheral.call, p, m, ...)
  if ok then return a, b end
  return nil, a
end

---------------------------------------------------------------- рецепты
local byId, byOut, useful, transOf = {}, {}, {}, {}
for _, r in ipairs(R.list) do
  byId[r.id] = r
  r.main = r.outs[1].item
  r.gain = {}
  for _, o in ipairs(r.outs) do
    if o.chance >= 1 then r.gain[o.item] = (r.gain[o.item] or 0) + o.n end
  end
  r.ingr = {}
  if r.base then
    -- недоделанная заготовка (после перезапуска) заменяет новую: доделывается на той же линии
    local alts = {}
    for _, a in ipairs(r.base) do alts[#alts + 1] = a end
    alts[#alts + 1] = r.transitional
    r.ingr[#r.ingr + 1] = {alts = alts, n = 1}
    for _, d in ipairs(r.deploy) do r.ingr[#r.ingr + 1] = {alts = d, n = r.loops} end
    transOf[r.transitional] = r
  else
    for _, a in ipairs(r.ins) do r.ingr[#r.ingr + 1] = {alts = a, n = 1} end
  end
  byOut[r.main] = byOut[r.main] or {}
  table.insert(byOut[r.main], r)
end
for _, r in ipairs(R.list) do
  useful[r.main] = true
  if r.transitional then useful[r.transitional] = true end
  for _, g in ipairs(r.ingr) do for _, a in ipairs(g.alts) do useful[a] = true end end
end
local TARGET_RECIPE = byOut[R.target][1]

---------------------------------------------------------------- планировщик
-- Симулирует склад: берёт готовое, недостающее крафтит партиями по рецептам (альтернативы по порядку),
-- излишки партий остаются на складе-симуляции и идут в следующие крафты. Неудачная ветка откатывается.
local function jset(st, tbl, key, val)
  st.log[#st.log + 1] = {tbl, key, tbl[key]}
  tbl[key] = val
end
local function rollback(st, mark)
  for i = #st.log, mark + 1, -1 do
    local e = st.log[i]; e[1][e[2]] = e[3]; st.log[i] = nil
  end
end

local need, batch
local function takeSim(st, it, n)
  local have = st.sim[it] or 0
  if have <= 0 then return n end
  local t = math.min(have, n)
  jset(st, st.sim, it, have - t)
  return n - t
end

need = function(st, alts, n, depth, lenient)
  for _, it in ipairs(alts) do
    n = takeSim(st, it, n)
    if n == 0 then return true end
  end
  while n > 0 do
    local done = false
    if depth < 16 then
      for _, it in ipairs(alts) do
        for _, r in ipairs(byOut[it] or {}) do
          local mark = #st.log
          if batch(st, r, depth + 1, false) then
            n = takeSim(st, it, n); done = true; break
          end
          rollback(st, mark)
        end
        if done then break end
      end
    end
    if not done then
      if not lenient then return false end
      local it = alts[1]
      local r = (byOut[it] or {})[1]
      local craftable = 0
      for _, a in ipairs(alts) do if byOut[a] then craftable = craftable + 1 end end
      -- ванильные предметы (самородки и т.п.) называем как есть, а не их редкий крафт
      if depth > 0 and (craftable > 1 or #(byOut[it] or {}) > 1 or it:find("^minecraft:")) then
        -- развилка (руда/сырьё/блок, уголь/древесный уголь): сообщаем о самом предмете
        jset(st, st.missing, it, (st.missing[it] or 0) + n)
        return false
      elseif r and depth < 16 then
        batch(st, r, depth + 1, true)
        n = takeSim(st, it, n)
      else
        jset(st, st.missing, it, (st.missing[it] or 0) + n)
        return false
      end
    end
  end
  return true
end

batch = function(st, r, depth, lenient)
  local ok = true
  for _, g in ipairs(r.ingr) do
    if not need(st, g.alts, g.n, depth, lenient) then
      ok = false
      if not lenient then return false end
    end
  end
  for it, c in pairs(r.gain) do jset(st, st.sim, it, (st.sim[it] or 0) + c) end
  jset(st, st.runs, r.id, (st.runs[r.id] or 0) + 1)
  return ok
end

-- stock: {item=count}. Возвращает true, runs  |  false, missing (по базовым ресурсам)
local function plan(stock, qty)
  local function fresh()
    local sim = {}
    for k, v in pairs(stock) do sim[k] = v end
    return {sim = sim, runs = {}, missing = {}, log = {}}
  end
  local st = fresh()
  local ok = true
  for _ = 1, qty do
    if not batch(st, TARGET_RECIPE, 0, false) then ok = false; break end
  end
  if ok then return true, st.runs end
  st = fresh()
  for _ = 1, qty do batch(st, TARGET_RECIPE, 0, true) end
  return false, st.missing
end

---------------------------------------------------------------- поиск механизмов
local KIND = {
  ["create:crushing_wheel_controller"] = "crush",
  ["create:depot"] = "wash",
  ["create:millstone"] = "mill",
  ["create:basin"] = "basin",
  ["create:deployer"] = "deployer",
  ["create:belt"] = "belt",
  ["arcon:furnace_multiblock"] = "furnace",
}
-- машины Create с инвентарём, которые трогать нельзя (если модем случайно касается)
local IGNORE = {
  ["create:mechanical_saw"] = true, ["create:chute"] = true,
  ["create:smart_chute"] = true, ["create:mechanical_crafter"] = true, ["create:item_drain"] = true,
  ["create:spout"] = true, ["create:packager"] = true, ["create:repackager"] = true,
  ["create:andesite_funnel"] = true, ["create:brass_funnel"] = true, ["create:andesite_tunnel"] = true,
  ["create:brass_tunnel"] = true, ["create:blaze_burner"] = true, ["create:mechanical_press"] = true,
  ["create:mechanical_mixer"] = true, ["create:encased_fan"] = true,
}
local function baseName(n) return (n:gsub("_%d+$", "")) end

local function inList(list, n)
  for _, x in ipairs(list) do if x == n then return true end end
  return false
end
local function isStorage(n)
  return inList(cfg.raw, n) or inList(cfg.stock, n) or inList(cfg.output, n) or inList(cfg.waste, n)
end

local M
local LASTSEEN = {}   -- имя периферии -> когда последний раз была в сети
local GRACE = 5       -- сек: столько «помним» пропавшую машину
local function discover()
  -- собираем заново в N и подменяем M целиком: обращения к периферии отдают управление
  -- другому потоку (экрану), и он не должен увидеть недособранный список
  local N = {crush = {}, wash = {}, mill = {}, basin = {}, furnace = {}, furnaceOut = {}, deployer = {}, belt = {},
       buffers = {}, ignored = {}, monitors = {}, tanks = {}}
  local here = {}
  for _, n in ipairs(peripheral.getNames()) do
    here[n] = true
    local b = baseName(n)
    local k = KIND[b]
    if peripheral.hasType(n, "monitor") then
      table.insert(N.monitors, n)
    elseif k == "furnace" then
      local size = call(n, "size") or 0
      if size == 4 then table.insert(N.furnaceOut, {name = n, from = 1})       -- модем на передней грани
      elseif size >= 12 then
        table.insert(N.furnace, {name = n})
        table.insert(N.furnaceOut, {name = n, from = 9})
      else table.insert(N.furnace, {name = n}) end
    elseif k then
      table.insert(N[k], {name = n})
    elseif peripheral.hasType(n, "inventory") then
      if isStorage(n) then -- склады отдельно
      elseif IGNORE[b] then table.insert(N.ignored, n)
      else table.insert(N.buffers, n) end
    end
    -- баки: любое хранилище жидкости, кроме машин (Create Fluid Tank, шланговый шкив и т.п.)
    if not k and not IGNORE[b] and peripheral.hasType(n, "fluid_storage") then table.insert(N.tanks, n) end
  end
  -- машины Create иногда на миг «переподключаются» (модем заново спрашивает блок); такие короткие
  -- пропадания не считаем, иначе экран мигает [ NO ] / [ OK ] и работа дёргается
  local t = os.epoch("utc") / 1000
  for n in pairs(here) do LASTSEEN[n] = t end
  if M then
    for cat, list in pairs(M) do
      if N[cat] and cat ~= "lines" then
        for _, e in ipairs(list) do
          local n = type(e) == "table" and e.name or e
          if not here[n] and LASTSEEN[n] and t - LASTSEEN[n] < GRACE then table.insert(N[cat], e) end
        end
      end
    end
  end
  -- постоянный порядок: строки на экране не переставляются местами
  for _, cat in pairs(N) do
    table.sort(cat, function(a, c)
      return (type(a) == "table" and a.name or a) < (type(c) == "table" and c.name or c)
    end)
  end
  for _, bs in ipairs(N.basin) do bs.role = cfg.basins[bs.name] end
  -- линии: если лента одна и ничего не назначено — все развёртыватели её
  N.lines = {}
  local present = {}
  for _, d in ipairs(N.deployer) do present[d.name] = true end
  for _, b in ipairs(N.belt) do
    local deps = {}
    if cfg.lines[b.name] then
      for _, d in ipairs(cfg.lines[b.name]) do if present[d] then deps[#deps + 1] = d end end
    elseif #N.belt == 1 then
      for _, d in ipairs(N.deployer) do deps[#deps + 1] = d.name end
    end
    N.lines[#N.lines + 1] = {belt = b.name, deps = deps, auto = cfg.lines[b.name] == nil,
      jobs = cfg.lineJobs[b.name]}   -- nil = линия делает все сборки
  end
  -- бассейнов два, про один уже известно - второй, значит, другой
  local unknown, known = {}, {}
  for _, bs in ipairs(N.basin) do
    if bs.role then known[bs.role] = true else unknown[#unknown + 1] = bs end
  end
  if #unknown == 1 and #N.basin >= 2 and (known.mix ~= known.compact) then
    unknown[1].role = known.mix and "compact" or "mix"
    cfg.basins[unknown[1].name] = unknown[1].role
    saveCfg()
  end
  M = N
end

local function stationCount(kind)
  if kind == "line" then return #M.lines end
  if kind == "mix" or kind == "compact" then
    local c = 0
    for _, b in ipairs(M.basin) do if b.role == nil or b.role == kind then c = c + 1 end end
    return c
  end
  return #M[kind]
end
local lackText   -- ниже: текст «чего не хватает» для экрана
local STATION_RU = {crush = "crushing wheels", wash = "washing depot", mill = "millstone",
  water = "water: a tank with water in the network, or a pipe into the mixer basin", mix = "basin with mixer",
  compact = "basin with press", furnace = "industrial furnace", line = "assembly belt",
  deployer = "a line with 2 deployers (menu > assembly lines)"}

lackText = function(k)
  if k:sub(1, 5) == "line:" then
    local r = byId[k:sub(6)]
    return "no line for " .. (r and iname(r.main) or k) ..
      ((r and r.base and #r.deploy > 0) and " (needs 2 deployers + JOBS)" or " (menu > lines > JOBS)")
  end
  return STATION_RU[k] or k
end

---------------------------------------------------------------- склад
local idx -- item -> {{inv, slot, count}}
local function sources()
  local t = {}
  for _, n in ipairs(cfg.stock) do t[#t + 1] = n end   -- сначала излишки, потом сырьё
  for _, n in ipairs(cfg.raw) do t[#t + 1] = n end
  return t
end
local function scan()
  local new = {}
  local counts = {}
  for _, inv in ipairs(sources()) do
    local l = call(inv, "list") or {}
    for slot, it in pairs(l) do
      new[it.name] = new[it.name] or {}
      table.insert(new[it.name], {inv = inv, slot = slot, count = it.count})
      counts[it.name] = (counts[it.name] or 0) + it.count
    end
  end
  idx = new
  return counts
end
local function have(item)
  local c = 0
  for _, e in ipairs(idx[item] or {}) do c = c + e.count end
  return c
end
-- перенести n штук item со склада в машину (toSlot необязателен). Возвращает сколько перенесли.
local function give(item, n, target, toSlot)
  local moved = 0
  for _, e in ipairs(idx[item] or {}) do
    if moved >= n then break end
    if e.count > 0 then
      local m = call(e.inv, "pushItems", target, e.slot, math.min(n - moved, e.count), toSlot) or 0
      e.count = e.count - m
      moved = moved + m
      if m == 0 then break end -- машина полна
    end
  end
  return moved
end
local function storeTo(list, src, slot, count)
  local left = count
  for _, d in ipairs(list) do
    local m = call(src, "pushItems", d, slot, left) or 0
    left = left - m
    if left <= 0 then return true end
  end
  return false
end

---------------------------------------------------------------- состояние производства
local S = {mode = "idle", qty = 1, runs = {}, missing = nil, msg = "", startOut = 0, lastProgress = 0,
           stall = nil, line = nil, basinJob = {}, washJob = {}, millJob = {}, lineJob = {}, furnaceJob = {}}
local function now() return os.epoch("utc") / 1000 end

local function countOutput()
  local c = 0
  for _, inv in ipairs(cfg.output) do
    for _, it in pairs(call(inv, "list") or {}) do
      if it.name == R.target then c = c + it.count end
    end
  end
  return c
end

local function progress() S.lastProgress = now(); S.stall = nil end

-- какие предметы машина держит как ВХОД текущей работы (их не выгружаем)
local function inputsOf(r)
  local t = {}
  if r then for _, g in ipairs(r.ingr) do for _, a in ipairs(g.alts) do t[a] = true end end end
  return t
end

local function routeItem(src, slot, it)
  if it.name == R.target then
    local ok = storeTo(cfg.output, src, slot, it.count)
    if ok then progress() end
    return ok
  elseif useful[it.name] then
    return storeTo(cfg.stock, src, slot, it.count)
  end
  return storeTo(cfg.waste, src, slot, it.count)
end

-- забрать результаты из приёмников и машин
local function drain()
  local function activeSeq(seq)
    if #seq.deploy == 0 then return S.seqPress and S.seqPress[seq.id] ~= nil end
    for _, j in pairs(S.lineJob) do if j.rid == seq.id then return true end end
    return false
  end
  local function credit(name, count)
    -- готовые изделия сборки засчитываем линиям, которые их собирают
    for _, j in pairs(S.lineJob) do
      if count > 0 and name == byId[j.rid].main and j.done < j.k then
        local c = math.min(count, j.k - j.done); j.done = j.done + c; count = count - c; progress()
      end
    end
    for rid, sp in pairs(S.seqPress or {}) do
      if count > 0 and name == byId[rid].main then sp.done = sp.done + count; count = 0; progress() end
    end
  end
  local function fromBuffer(src)
    for slot, it in pairs(call(src, "list") or {}) do
      local seq = transOf[it.name]
      if seq and activeSeq(seq) then
        -- полуфабрикат активной сборки: вернётся на ленту в dispatchLine
      elseif routeItem(src, slot, it) then
        credit(it.name, it.count)
      end
    end
  end
  for _, b in ipairs(M.buffers) do fromBuffer(b) end
  for _, fo in ipairs(M.furnaceOut) do
    for slot, it in pairs(call(fo.name, "list") or {}) do
      if slot >= fo.from then routeItem(fo.name, slot, it); progress() end
    end
  end
  for _, d in ipairs(M.mill) do
    local keep = inputsOf(S.millJob[d.name])
    for slot, it in pairs(call(d.name, "list") or {}) do
      if not keep[it.name] then routeItem(d.name, slot, it); progress() end
    end
  end
  for _, d in ipairs(M.wash) do
    local keep = inputsOf(S.washJob[d.name])
    for slot, it in pairs(call(d.name, "list") or {}) do
      if not keep[it.name] then routeItem(d.name, slot, it); progress() end
    end
  end
  for _, b in ipairs(M.basin) do
    local job = S.basinJob[b.name]
    local keep = inputsOf(job and job.r)
    for slot, it in pairs(call(b.name, "list") or {}) do
      if not keep[it.name] then
        routeItem(b.name, slot, it); progress()
        if job and job.trial and it.name == job.r.main then
          b.role = job.r.station; cfg.basins[b.name] = b.role; saveCfg(); job.trial = nil
        end
      end
    end
  end
end

local function isEmpty(name)
  return next(call(name, "list") or {}) == nil
end

-- сколько партий рецепта r можно собрать прямо сейчас (с учётом альтернатив), выбор альтернатив
local function pickAltsWith(r, maxK, first)
  local choice, k = {}, maxK
  local used = {}
  for i, g in ipairs(r.ingr) do
    local best, bestK = nil, 0
    for _, a in ipairs(i == 1 and {first} or g.alts) do
      local can = math.floor((have(a) - (used[a] or 0)) / g.n)
      if can > bestK then best, bestK = a, can end
    end
    if not best then return nil, 0 end
    choice[i] = best
    used[best] = (used[best] or 0) + g.n * math.min(k, bestK)
    k = math.min(k, bestK)
  end
  -- повторная проверка: одинаковые предметы в разных строках (4 жел. слитка) делят запас
  local need = {}
  for i, g in ipairs(r.ingr) do need[choice[i]] = (need[choice[i]] or 0) + g.n end
  for it, per in pairs(need) do k = math.min(k, math.floor(have(it) / per)) end
  if k <= 0 then return nil, 0 end
  return choice, k
end

-- сколько партий рецепта r можно запустить сейчас; перебираем варианты основы (новая / недоделанная)
local function pickAlts(r, maxK)
  local best, bestK = nil, 0
  for _, a in ipairs(r.ingr[1].alts) do
    local c, k = pickAltsWith(r, maxK, a)
    if c and k > bestK then best, bestK = c, k end
  end
  return best, bestK
end

local function runsFor(station)
  local t = {}
  for rid, n in pairs(S.runs) do
    local r = byId[rid]
    if n > 0 and r.station == station then t[#t + 1] = r end
  end
  table.sort(t, function(a, b) return a.id < b.id end)
  return t
end

---------------------------------------------------------------- раздача работы
-- сколько партий дать одной машине: поровну между всеми машинами этого типа
local function share(r, per, count)
  return math.min(per, math.max(1, math.ceil(S.runs[r.id] / math.max(1, count))))
end

local function dispatchSimple(station, machines, per, jobs)
  for _, m in ipairs(machines) do
    if isEmpty(m.name) then
      if jobs then jobs[m.name] = nil end
      for _, r in ipairs(runsFor(station)) do
        local choice, k = pickAlts(r, share(r, per, #machines))
        if choice then
          local moved = give(choice[1], k * r.ingr[1].n, m.name)
          if moved > 0 then
            S.runs[r.id] = S.runs[r.id] - math.floor(moved / r.ingr[1].n)
            if jobs then jobs[m.name] = r end
            progress()
            break
          end
        end
      end
    end
  end
end

local function dispatchFurnace()
  for _, f in ipairs(M.furnace) do
    local l = call(f.name, "list") or {}
    local busy = false
    for slot in pairs(l) do if slot <= 8 then busy = true end end
    if not busy then
      for _, r in ipairs(runsFor("furnace")) do
        local choice, k = pickAlts(r, share(r, PER_FURNACE, #M.furnace))
        if choice then
          -- каждый ингредиент в свой входной слот, по k штук
          local got = k
          for i, g in ipairs(r.ingr) do
            local m = give(choice[i], g.n * k, f.name, i)
            got = math.min(got, math.floor(m / g.n))
          end
          S.runs[r.id] = S.runs[r.id] - got
          progress()
          break
        end
      end
    end
  end
end

-- сколько жидкости (мБ) в бассейне; вода приходит трубой, ПК её только проверяет
local function fluidIn(basin, fluid)
  local c = 0
  for _, t in pairs(call(basin, "tanks") or {}) do
    if t.name == fluid then c = c + t.amount end
  end
  return c
end
local function fluidBatches(basin, r, k)
  for _, f in ipairs(r.fluids or {}) do k = math.min(k, math.floor(fluidIn(basin, f.fluid) / f.amount)) end
  return k
end
-- сколько жидкости во всех баках сети
local function tankFluid(fluid)
  local c = 0
  for _, t in ipairs(M.tanks) do c = c + fluidIn(t, fluid) end
  return c
end
-- долить из баков в бассейн, чтобы хватило на k партий (бассейн держит 1000 мБ)
local function topUp(basin, r, k)
  for _, f in ipairs(r.fluids or {}) do
    local need = math.min(1000, f.amount * k) - fluidIn(basin, f.fluid)
    for _, t in ipairs(M.tanks) do
      if need <= 0 then break end
      need = need - (call(t, "pushFluid", basin, need, f.fluid) or 0)
    end
  end
end

local function dispatchBasins()
  for _, b in ipairs(M.basin) do
    local job = S.basinJob[b.name]
    if job and job.trial and now() - job.t0 > BASIN_TRIAL then
      -- ингредиенты не тронуты: у этого бассейна другой механизм
      local other = job.r.station == "mix" and "compact" or "mix"
      b.role = other; cfg.basins[b.name] = other; saveCfg()
      for slot, it in pairs(call(b.name, "list") or {}) do routeItem(b.name, slot, it) end
      S.runs[job.r.id] = S.runs[job.r.id] + job.k
      S.basinJob[b.name] = nil
    elseif isEmpty(b.name) then
      S.basinJob[b.name] = nil
      local cands = {}
      for _, st in ipairs({"mix", "compact"}) do
        if b.role == nil or b.role == st then
          for _, r in ipairs(runsFor(st)) do cands[#cands + 1] = r end
        end
      end
      -- воду льём только в опознанный миксер; в неопознанный бассейн - лишь в крайнем случае
      -- (миксера ещё нет и рецептов смешивания без воды не осталось), иначе вода пропадёт в прессе
      local knownMix, dryMix = false, false
      for _, b2 in ipairs(M.basin) do if b2.role == "mix" then knownMix = true end end
      for _, r in ipairs(runsFor("mix")) do if not r.fluids then dryMix = true end end
      for _, r in ipairs(cands) do
       if not (r.fluids and b.role == nil and (knownMix or dryMix)) then
        local want = share(r, PER_BASIN, #M.basin)
        if r.fluids and b.role ~= "compact" then topUp(b.name, r, want) end
        local choice, k = pickAlts(r, fluidBatches(b.name, r, want))
        if choice then
          local total = {}
          for i, g in ipairs(r.ingr) do total[choice[i]] = (total[choice[i]] or 0) + g.n * k end
          for it, c in pairs(total) do give(it, c, b.name) end
          S.runs[r.id] = S.runs[r.id] - k
          S.basinJob[b.name] = {r = r, k = k, t0 = now(), trial = (b.role == nil)}
          progress()
          break
        end
       end
      end
    end
  end
end

-- развёртыватели: все (deps == nil) или одной линии
local function unloadDeployers(deps)
  if not deps then
    deps = {}
    for _, d in ipairs(M.deployer) do deps[#deps + 1] = d.name end
  end
  for _, d in ipairs(deps) do
    for slot, it in pairs(call(d, "list") or {}) do routeItem(d, slot, it) end
  end
end

-- Пустой развёртыватель над лентой ДЕРЖИТ предметы (так устроен Create), а с предметом, для которого
-- нет рецепта, - пропускает. Поэтому ни один развёртыватель не оставляем пустым: кладём «заглушку» -
-- 1 ненужный предмет (опыт, булыжник из побочки). Перед сборкой заглушка уходит, детали кончились -
-- снова заглушка. Так и линия не встаёт, и развёртыватели в любом порядке не застревают.
local function fillerSource()
  for _, inv in ipairs(cfg.waste) do
    for slot in pairs(call(inv, "list") or {}) do return inv, slot end
  end
  for _, inv in ipairs(sources()) do
    for slot, it in pairs(call(inv, "list") or {}) do
      if not useful[it.name] then return inv, slot end
    end
  end
end
local function fillDeployers()
  S.noFiller = false
  for _, d in ipairs(M.deployer) do
    if isEmpty(d.name) then
      local inv, slot = fillerSource()
      if not inv then S.noFiller = true; return end
      call(inv, "pushItems", d.name, slot, 1)
    end
  end
end

-- линия делает эту сборку? (в меню JOBS; по умолчанию - все)
local function lineAllows(line, r)
  return line.jobs == nil or line.jobs[r.id] == true
end

-- сколько заготовок линия может взять под рецепт с развёртывателями (0 = не может)
local function lineCap(line, r)
  if not lineAllows(line, r) then return 0 end
  local n = #line.deps
  if n == 0 then return 0 end
  if n >= #r.deploy then return math.floor(64 / r.loops) end
  -- один развёртыватель тянет два шага, только если предмет одинаковый
  if n == 1 and #r.deploy == 2 and r.deploy[1][1] == r.deploy[2][1] then return math.floor(64 / (r.loops * 2)) end
  return 0
end

-- полуфабрикат из приёмников на ленту этой линии
local function feedTransitional(line)
  local job = S.lineJob[line.belt]
  for _, src in ipairs(M.buffers) do
    for slot, it in pairs(call(src, "list") or {}) do
      local seq = transOf[it.name]
      if seq then
        local mine = (#seq.deploy == 0 and S.seqPress and S.seqPress[seq.id] and lineAllows(line, seq))
          or (job and job.rid == seq.id)
        if mine and call(src, "pushItems", line.belt, slot, 1) == 1 then return true end
      end
    end
  end
  return false
end

local function dispatchLine()
  if #M.lines == 0 then return end
  S.seqPress = S.seqPress or {}
  for rid, sp in pairs(S.seqPress) do if sp.done >= sp.k and sp.fed >= sp.k then S.seqPress[rid] = nil end end
  -- линии, где сборка готова, освобождаются; свободные берут новую сборку с развёртывателями
  local able = {}
  for _, line in ipairs(M.lines) do
    local job = S.lineJob[line.belt]
    if job and job.done >= job.k then unloadDeployers(line.deps); S.lineJob[line.belt] = nil end
  end
  for _, line in ipairs(M.lines) do
    if not S.lineJob[line.belt] then
      for _, r in ipairs(runsFor("line")) do
        -- один рецепт сборки - только на одной линии: тогда полуфабрикат однозначно возвращается
        -- на свою ленту, а развёртыватели разных линий не путаются; разные рецепты идут параллельно
        local busyElsewhere = false
        for _, j in pairs(S.lineJob) do if j.rid == r.id then busyElsewhere = true end end
        if r.base and #r.deploy > 0 and lineCap(line, r) > 0 and not busyElsewhere then
          local choice, k = pickAlts(r, math.min(lineCap(line, r), S.runs[r.id]))
          if choice and k > 0 then
            unloadDeployers(line.deps)
            for i = 2, #r.ingr do
              give(choice[i], r.ingr[i].n * k, line.deps[math.min(i - 1, #line.deps)])
            end
            S.runs[r.id] = S.runs[r.id] - k
            S.lineJob[line.belt] = {rid = r.id, k = k, fed = 0, done = 0, base = choice[1]}
            progress()
            break
          end
        end
      end
    end
  end
  -- сборки только с прессом (броневая плита) — без развёртывателей, на любой линии
  for _, r in ipairs(runsFor("line")) do
    if r.base and #r.deploy == 0 and not S.seqPress[r.id] then
      local choice, k = pickAlts(r, S.runs[r.id])
      if choice then
        S.runs[r.id] = S.runs[r.id] - k
        S.seqPress[r.id] = {k = k, fed = 0, done = 0, base = choice[1]}
      end
    end
  end
  -- каждая свободная лента берёт по предмету
  for _, line in ipairs(M.lines) do
    if isEmpty(line.belt) then
      local job = S.lineJob[line.belt]
      local fed = feedTransitional(line)   -- возврат полуфабриката прогрессом не считаем
      local new = false
      if not fed and job and job.fed < job.k and give(job.base, 1, line.belt) == 1 then
        job.fed = job.fed + 1; fed = true; new = true
      end
      if not fed then
        for rid, sp in pairs(S.seqPress) do
          if sp.fed < sp.k and lineAllows(line, byId[rid]) and give(sp.base, 1, line.belt) == 1 then
            sp.fed = sp.fed + 1; fed = true; new = true; break
          end
        end
      end
      if not fed then
        for _, r in ipairs(runsFor("line")) do
          if not r.base and lineAllows(line, r) and have(r.ingr[1].alts[1]) > 0
             and give(r.ingr[1].alts[1], 1, line.belt) == 1 then
            S.runs[r.id] = S.runs[r.id] - 1; fed = true; new = true; break
          end
        end
      end
      if new then progress() end
    end
  end
  fillDeployers()
end

local function allDone()
  for _, n in pairs(S.runs) do if n > 0 then return false end end
  if next(S.lineJob) or next(S.seqPress or {}) then return false end
  return countOutput() >= S.startOut + S.qty
end

---------------------------------------------------------------- проверка перед запуском
local function check()
  local stock = scan()
  local ok, res = plan(stock, S.qty)
  S.missing, S.noMachine = nil, nil
  if not ok then S.missing = res; return false end
  local lack = {}
  for rid, n in pairs(res) do
    local st = byId[rid].station
    if n > 0 and stationCount(st) == 0 then lack[st] = true end
  end
  local needMix, needCompact = false, false
  for rid, n in pairs(res) do
    local r = byId[rid]
    if n > 0 and r.station == "line" then
      local ok = false
      for _, line in ipairs(M.lines) do
        if r.base and #r.deploy > 0 then
          if lineCap(line, r) > 0 then ok = true end
        elseif lineAllows(line, r) then ok = true end
      end
      if not ok and #M.lines > 0 then lack["line:" .. rid] = true end
    end
    if n > 0 and r.station == "mix" then needMix = true end
    if n > 0 and r.station == "compact" then needCompact = true end
  end
  if needMix and needCompact and #M.basin < 2 then lack.mix = true; lack.compact = true end
  -- жидкости: есть баки - считаем, хватит ли их на весь заказ; нет баков - вода должна идти трубой в бассейн
  local needF = {}
  for rid, n in pairs(res) do
    for _, f in ipairs(byId[rid].fluids or {}) do needF[f.fluid] = (needF[f.fluid] or 0) + f.amount * n end
  end
  local short = {}
  for fluid, need in pairs(needF) do
    local inBasins = 0
    for _, b in ipairs(M.basin) do
      if b.role ~= "compact" then inBasins = inBasins + fluidIn(b.name, fluid) end
    end
    if #M.tanks > 0 then
      if tankFluid(fluid) + inBasins < need then short[fluid] = need - tankFluid(fluid) - inBasins end
    elseif inBasins < 250 then
      lack.water = true
    end
  end
  if next(short) then S.missing = short; return false end
  if next(lack) then S.noMachine = lack; return false end
  if #cfg.output == 0 or #cfg.stock == 0 or #cfg.waste == 0 then S.noMachine = {storage = true}; return false end
  return true, res
end

local function start()
  discover()
  scan(); drain(); unloadDeployers()
  local ok, runs = check()
  if not ok then S.mode = "idle"; return false end
  S.runs = runs
  S.mode = "run"
  S.startOut = countOutput()
  S.t0 = now()
  progress()
  return true
end

local function stop()
  S.mode = "idle"; S.runs = {}; S.lineJob = {}; S.seqPress = {}
  unloadDeployers()
end

---------------------------------------------------------------- экран
-- Одно и то же меню на компьютере (мышь) и на всех мониторах (касание).
-- Экраны: menu (настройка), pick (выбор хранилищ), list (что найдено), start (сколько делать), work (работа).
local function fmtTime(s)
  s = math.floor(s)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function short(n) return (n:gsub("^minecraft:", "")) end

local ROLES = {
  {key = "raw", name = "RAW", hint = "players drop ore, coal, ingots here"},
  {key = "stock", name = "STOCK", hint = "surplus and intermediates"},
  {key = "output", name = "ARMOR OUT", hint = "finished armor goes here"},
  {key = "waste", name = "BYPRODUCTS", hint = "xp nuggets, cobblestone etc."},
}
local UI = {screen = "menu", scroll = 0, role = nil, cand = {}, canMake = nil, editQty = 1, inf = false}
local BTN = {}   -- кнопки по устройствам: BTN["term"] / BTN["monitor_0"] = {{x1,x2,y,id,arg}}

local function storagesReady()
  return #cfg.raw > 0 and #cfg.stock > 0 and #cfg.output > 0 and #cfg.waste > 0
end
local function roleOf(n)
  for _, r in ipairs(ROLES) do if inList(cfg[r.key], n) then return r end end
end

-- сборки, которые идут на линиях (листы, плиты, корпус, броня)
local LINE_RECIPES = {}
for _, r in ipairs(R.list) do if r.station == "line" then LINE_RECIPES[#LINE_RECIPES + 1] = r end end
-- нужны ли этой линии развёртыватели (есть ли среди её сборок такие, где они работают)
local function lineNeedsDeps(line)
  for _, r in ipairs(LINE_RECIPES) do
    if lineAllows(line, r) and r.base and #r.deploy > 0 then return true end
  end
  return false
end

-- все хранилища сети, которые можно назначить складом (не машины)
local function candidates()
  local t = {}
  for _, n in ipairs(peripheral.getNames()) do
    local b = baseName(n)
    if peripheral.hasType(n, "inventory") and not KIND[b] and not IGNORE[b] then
      local l = call(n, "list") or {}
      local used, first = 0, nil
      for _, it in pairs(l) do used = used + 1; first = first or it.name end
      t[#t + 1] = {name = n, size = call(n, "size") or 0, used = used, first = first}
    end
  end
  table.sort(t, function(a, b) return a.name < b.name end)
  return t
end

-- на сколько брони хватает прямо сейчас (бинпоиск по планировщику)
local function maxMakeable()
  local stock = scan()
  if not plan(stock, 1) then return 0 end
  local lo, hi = 1, 64
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if plan(stock, mid) then lo = mid else hi = mid - 1 end
  end
  return lo
end

local function draw(t, dev)
  local w, h = t.getSize()
  local B = {}
  t.setBackgroundColor(colors.black); t.clear()
  local function put(x, y, s, fg, bg)
    if y < 1 or y > h then return end
    t.setCursorPos(x, y)
    if bg then t.setBackgroundColor(bg) end
    t.setTextColor(fg or colors.white); t.write(s:sub(1, math.max(0, w - x + 1)))
    t.setBackgroundColor(colors.black)
  end
  local function bar(y, s, fg, bg)
    t.setCursorPos(1, y); t.setBackgroundColor(bg); t.write(string.rep(" ", w))
    put(1, y, s, fg, bg)
  end
  local function btn(x, y, label, bg, id, arg)
    put(x, y, " " .. label .. " ", colors.white, bg)
    B[#B + 1] = {x1 = x, x2 = x + #label + 1, y = y, id = id, arg = arg}
    return x + #label + 3
  end
  local function machinesLine(y)
    local nb = {mix = 0, compact = 0, unk = 0}
    for _, b in ipairs(M.basin) do
      if b.role then nb[b.role] = nb[b.role] + 1 else nb.unk = nb.unk + 1 end
    end
    put(1, y, string.format(" Furnaces %d  Crushers %d  Millstones %d  Washers %d  Basins %d (mix %d/press %d/? %d)",
      #M.furnace, #M.crush, #M.mill, #M.wash, #M.basin, nb.mix, nb.compact, nb.unk), colors.lightGray)
    put(1, y + 1, string.format(" Lines %d  Deployers %d  Tanks %d  Receivers %d  Monitors %d",
      #M.lines, #M.deployer, #M.tanks, #M.buffers, #M.monitors), colors.lightGray)
  end
  local title = " " .. iname(R.target)

  if UI.screen == "menu" then
    bar(1, title .. " - SETUP", colors.white, colors.gray)
    local gap = h >= 30 and 1 or 0         -- на экране компьютера без пустых строк
    local y = 2 + gap
    put(1, y, " Storages (press SELECT, several per role allowed):", colors.yellow)
    y = y + 1
    for _, r in ipairs(ROLES) do
      put(2, y, string.format("%-16s", r.name), colors.white)
      local names = {}
      for _, n in ipairs(cfg[r.key]) do names[#names + 1] = short(n) end
      local txt = #names > 0 and table.concat(names, ", ") or "- not selected -"
      put(19, y, txt:sub(1, math.max(1, w - 30)), #names > 0 and colors.lime or colors.red)
      btn(w - 9, y, "SELECT", colors.blue, "pick", r.key)
      y = y + 1
    end
    y = y + gap
    put(1, y, " Basins (what is above them; AUTO = detect itself):", colors.yellow); y = y + 1
    if #M.basin == 0 then put(2, y, "- no basins in the network -", colors.red); y = y + 1 end
    for _, b in ipairs(M.basin) do
      put(2, y, short(b.name), colors.white)
      local lbl = b.role == "mix" and "MIXER" or (b.role == "compact" and "PRESS" or "AUTO")
      btn(w - 9, y, string.format("%-6s", lbl), b.role and colors.cyan or colors.gray, "basin", b.name)
      y = y + 1
    end
    y = y + gap
    put(1, y, " Assembly lines (DEP = its deployers, JOBS = what it makes):", colors.yellow); y = y + 1
    if #M.lines == 0 then put(2, y, "- no belt in the network -", colors.red); y = y + 1 end
    for _, line in ipairs(M.lines) do
      local names = {}
      for _, d in ipairs(line.deps) do names[#names + 1] = short(d) end
      local nj = 0
      for _ in pairs(line.jobs or {}) do nj = nj + 1 end
      local jobs = line.jobs and (nj .. " jobs") or "all jobs"
      local txt = (#names > 0 and (#names .. " deployers") or "no deployers") .. ", " .. jobs
      put(2, y, short(line.belt), colors.white)
      put(19, y, txt:sub(1, math.max(1, w - 33)), (#names >= 2 or not lineNeedsDeps(line)) and colors.lime or colors.red)
      btn(w - 13, y, "DEP", colors.blue, "line", line.belt)
      btn(w - 7, y, "JOBS", colors.blue, "jobs", line.belt)
      y = y + 1
    end
    y = y + gap
    put(1, y, " Found in the network:", colors.yellow)
    btn(w - 9, y, "DETAILS", colors.blue, "list")
    machinesLine(y + 1)
    if S.msg ~= "" then put(1, h - 1, " " .. S.msg, colors.orange) end
    local x = btn(1, h, "REFRESH", colors.gray, "refresh")
    btn(w - 19, h, "START SYSTEM >", storagesReady() and colors.green or colors.gray, "tostart")

  elseif UI.screen == "pick" then
    local role
    for _, r in ipairs(ROLES) do if r.key == UI.role then role = r end end
    bar(1, " SELECT: " .. role.name .. " (" .. role.hint .. ")", colors.white, colors.gray)
    put(1, 2, " Tap a row. [x] = selected, grey = other role (will be moved).", colors.lightGray)
    local rows = h - 4
    local maxScroll = math.max(0, #UI.cand - rows)
    UI.scroll = math.max(0, math.min(UI.scroll, maxScroll))
    for i = 1, rows do
      local c = UI.cand[i + UI.scroll]
      if not c then break end
      local y = 2 + i
      local mine = inList(cfg[UI.role], c.name)
      local other = roleOf(c.name)
      local mark = mine and "[x] " or "[ ] "
      local info = string.format("%s%-28s %3d/%-3d %s", mark, short(c.name), c.used, c.size,
        c.first and iname(c.first) or "empty")
      if other and not mine then info = info .. "  (" .. other.name .. ")" end
      put(1, y, string.rep(" ", w), colors.white, mine and colors.green or colors.black)
      put(2, y, info, mine and colors.black or (other and colors.gray or colors.white), mine and colors.green or nil)
      B[#B + 1] = {x1 = 1, x2 = w, y = y, id = "toggle", arg = c.name}
    end
    if #UI.cand == 0 then put(2, 4, "No storages in the network. Put a modem on a chest and right-click it.", colors.red) end
    local x = btn(1, h, "^", colors.gray, "up")
    x = btn(x, h, "v", colors.gray, "down")
    put(x, h, string.format("%d-%d of %d", UI.scroll + 1, math.min(#UI.cand, UI.scroll + rows), #UI.cand), colors.lightGray)
    btn(w - 9, h, "DONE", colors.green, "back")

  elseif UI.screen == "pickdeps" then
    bar(1, " DEPLOYERS FOR " .. short(UI.belt) .. " (pick the 2 above this belt)", colors.white, colors.gray)
    put(1, 2, " Tap a row. [x] = on this belt, grey = on another belt (will be moved).", colors.lightGray)
    local mine = cfg.lines[UI.belt] or {}
    local rows = h - 4
    UI.scroll = math.max(0, math.min(UI.scroll, math.max(0, #M.deployer - rows)))
    for i = 1, rows do
      local d = M.deployer[i + UI.scroll]
      if not d then break end
      local y = 2 + i
      local on = inList(mine, d.name)
      local other
      for belt, list in pairs(cfg.lines) do
        if belt ~= UI.belt and inList(list, d.name) then other = belt end
      end
      local held = next(call(d.name, "list") or {}) and "holds items" or "empty"
      local info = string.format("%s%-28s %s", on and "[x] " or "[ ] ", short(d.name), held)
      if other then info = info .. "  (" .. short(other) .. ")" end
      put(1, y, string.rep(" ", w), colors.white, on and colors.green or colors.black)
      put(2, y, info, on and colors.black or (other and colors.gray or colors.white), on and colors.green or nil)
      B[#B + 1] = {x1 = 1, x2 = w, y = y, id = "toggledep", arg = d.name}
    end
    if #M.deployer == 0 then put(2, 4, "No deployers in the network. Put a modem on them and right-click it.", colors.red) end
    local x = btn(1, h, "^", colors.gray, "up")
    btn(x, h, "v", colors.gray, "down")
    btn(w - 9, h, "DONE", colors.green, "back")

  elseif UI.screen == "pickjobs" then
    bar(1, " JOBS FOR " .. short(UI.belt) .. " (what this line makes)", colors.white, colors.gray)
    put(1, 2, " Tap a job to switch it. ALL = the line takes any job.", colors.lightGray)
    local jobs = cfg.lineJobs[UI.belt]
    local y = 3
    put(1, y, string.rep(" ", w), colors.white, jobs == nil and colors.green or colors.black)
    put(2, y, (jobs == nil and "[x] " or "[ ] ") .. "ALL JOBS", jobs == nil and colors.black or colors.white,
      jobs == nil and colors.green or nil)
    B[#B + 1] = {x1 = 1, x2 = w, y = y, id = "jobsall"}
    for _, r in ipairs(LINE_RECIPES) do
      y = y + 1
      local on = jobs == nil or jobs[r.id]
      local what = (r.base and #r.deploy > 0) and "deployers + saw + press" or "press only"
      put(1, y, string.rep(" ", w), colors.white, on and colors.green or colors.black)
      put(2, y, string.format("%s%-36s %s", on and "[x] " or "[ ] ", iname(r.main), what),
        on and colors.black or colors.white, on and colors.green or nil)
      B[#B + 1] = {x1 = 1, x2 = w, y = y, id = "togglejob", arg = r.id}
    end
    btn(w - 9, h, "DONE", colors.green, "back")

  elseif UI.screen == "list" then
    bar(1, " FOUND IN THE NETWORK", colors.white, colors.gray)
    local rows = {}
    local function add(n, what) rows[#rows + 1] = {n, what} end
    for _, f in ipairs(M.furnace) do add(f.name, "industrial furnace") end
    for _, f in ipairs(M.furnaceOut) do if f.from == 1 then add(f.name, "furnace (output, modem on front)") end end
    for _, x in ipairs(M.crush) do add(x.name, "crushing wheels") end
    for _, x in ipairs(M.mill) do add(x.name, "millstone") end
    for _, x in ipairs(M.wash) do add(x.name, "washing (depot)") end
    for _, x in ipairs(M.basin) do
      add(x.name, "basin: " .. (x.role == "mix" and "mixer" or (x.role == "compact" and "press" or "auto-detect")))
    end
    local depOf = {}
    for _, line in ipairs(M.lines) do
      local js = {}
      for _, r in ipairs(LINE_RECIPES) do if lineAllows(line, r) then js[#js + 1] = iname(r.main) end end
      add(line.belt, "line, " .. #line.deps .. " deployers: " .. (line.jobs and table.concat(js, ", ") or "all jobs"))
      for _, d in ipairs(line.deps) do depOf[d] = line.belt end
    end
    for _, x in ipairs(M.deployer) do
      add(x.name, depOf[x.name] and ("deployer (" .. short(depOf[x.name]) .. ")") or "deployer (no line)")
    end
    for _, r in ipairs(ROLES) do for _, n in ipairs(cfg[r.key]) do add(n, "storage: " .. r.name) end end
    for _, n in ipairs(M.tanks) do add(n, "tank: " .. fluidIn(n, "minecraft:water") .. " mB water") end
    for _, n in ipairs(M.buffers) do add(n, "receiver (emptied by the PC)") end
    for _, n in ipairs(M.ignored) do add(n, "not used") end
    for _, n in ipairs(M.monitors) do
      add(n, n == STATUS_MON and "monitor (connections screen)" or "monitor (menu)")
    end
    local lines = h - 3
    UI.scroll = math.max(0, math.min(UI.scroll, math.max(0, #rows - lines)))
    for i = 1, lines do
      local r = rows[i + UI.scroll]
      if not r then break end
      put(2, 1 + i, string.format("%-32s %s", short(r[1]), r[2]),
        r[2]:find("receiver") and colors.orange or colors.white)
    end
    local x = btn(1, h, "^", colors.gray, "up")
    btn(x, h, "v", colors.gray, "down")
    btn(w - 8, h, "BACK", colors.blue, "back")

  elseif UI.screen == "start" then
    bar(1, title .. " - START", colors.white, colors.gray)
    put(2, 3, "How many armor blocks to make?", colors.yellow)
    local x = 2
    x = btn(x, 5, "-10", colors.gray, "qty", -10)
    x = btn(x, 5, "-1", colors.gray, "qty", -1)
    put(x + 1, 5, UI.inf and "ENDLESS" or string.format("%4d", UI.editQty), colors.white)
    x = x + (UI.inf and 13 or 6)
    x = btn(x, 5, "+1", colors.gray, "qty", 1)
    x = btn(x, 5, "+10", colors.gray, "qty", 10)
    btn(x + 1, 5, UI.inf and "[x] ENDLESS" or "[ ] ENDLESS", UI.inf and colors.green or colors.gray, "inf")
    local y = 7
    if UI.canMake == nil then
      put(2, y, "Press CHECK to see how many you can make now.", colors.lightGray)
    else
      put(2, y, "Resources are enough for: " .. UI.canMake, UI.canMake > 0 and colors.lime or colors.red)
      y = y + 1
      if S.noMachine then
        for _, k in ipairs(sortedKeys(S.noMachine)) do put(4, y, "missing: " .. lackText(k), colors.red); y = y + 1 end
      end
      if UI.canMake == 0 and S.missing then
        put(2, y, "Missing for 1 armor:", colors.red); y = y + 1
        local list = {}
        for it, n in pairs(S.missing) do list[#list + 1] = {it, n} end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for _, e in ipairs(list) do
          if y < h - 2 then put(4, y, string.format("x%-4d %s", e[2], iname(e[1])), colors.red); y = y + 1 end
        end
      end
    end
    put(2, h - 2, "You can start without resources: it will wait and begin by itself.", colors.lightGray)
    if S.msg ~= "" then put(1, h - 1, " " .. S.msg, colors.orange) end
    local bx = btn(1, h, "< MENU", colors.gray, "menu")
    btn(bx, h, "CHECK", colors.blue, "probe")
    btn(w - 9, h, "START", colors.green, "go")

  else -- work
    bar(1, title .. " - RUNNING", colors.white, colors.gray)
    local goal = cfg.target > 0 and tostring(cfg.target) or "endless"
    local y = 3
    if S.mode == "run" then
      bar(2, string.format(" CRAFTING: batch of %d, done %d of %s, time %s", S.qty, cfg.done, goal,
        fmtTime(now() - S.t0)), colors.black, colors.yellow)
      if S.stall then put(1, y, " ! No progress for " .. fmtTime(now() - S.lastProgress) .. ": " .. S.stall, colors.red); y = y + 1 end
      local list = {}
      for rid, n in pairs(S.runs) do if n > 0 then list[#list + 1] = {rid, n} end end
      table.sort(list, function(a, b) return a[1] < b[1] end)
      put(1, y, " Still to start:", colors.lightGray); y = y + 1
      for _, e in ipairs(list) do
        local r = byId[e[1]]
        if y < h - 3 then put(1, y, string.format("  %-8s x%-3d %s", r.station, e[2], iname(r.main)), colors.white); y = y + 1 end
      end
      for _, line in ipairs(M.lines) do
        local j = S.lineJob[line.belt]
        if j and y < h - 3 then
          put(1, y, string.format(" %s: %s  %d/%d", short(line.belt), iname(byId[j.rid].main), j.done, j.k), colors.cyan)
          y = y + 1
        end
      end
    elseif S.noMachine then
      bar(2, " MISSING MACHINES  (done " .. cfg.done .. " of " .. goal .. ")", colors.white, colors.red)
      for _, k in ipairs(sortedKeys(S.noMachine)) do
        local txt = k == "storage" and "storages not selected (STOP > MENU)" or lackText(k)
        put(3, y, txt, colors.red); y = y + 1
      end
    elseif S.missing then
      bar(2, " WAITING FOR RESOURCES - put them into RAW  (done " .. cfg.done .. " of " .. goal .. ")", colors.white, colors.red)
      local list = {}
      for it, n in pairs(S.missing) do list[#list + 1] = {it, n} end
      table.sort(list, function(a, b) return a[1] < b[1] end)
      for _, e in ipairs(list) do
        local via = {}
        for _, r in ipairs(byOut[e[1]] or {}) do
          if #r.ingr == 1 then via[#via + 1] = iname(r.ingr[1].alts[1]) end
        end
        local txt = string.format("  x%-4d %s", e[2], iname(e[1]))
        if #via > 0 then txt = txt .. "  (from: " .. table.concat(via, ", ") .. ")" end
        if y < h - 3 then put(1, y, txt, colors.red); y = y + 1 end
      end
    else
      bar(2, " CHECKING STORAGE...  (done " .. cfg.done .. " of " .. goal .. ")", colors.black, colors.lime)
    end
    if S.msg ~= "" then put(1, h - 3, " " .. S.msg, colors.orange) end
    if S.noFiller then
      put(1, h - 4, " ! Deployers need a filler: put a few cobblestone (any junk) into BYPRODUCTS", colors.red)
    end
    machinesLine(h - 2)
    btn(1, h, "STOP", colors.red, "stop")
  end
  put(w - #VERSION, 1, VERSION, colors.lightGray, colors.gray)
  BTN[dev] = B   -- кнопки публикуем после отрисовки целиком
end

-- монитор слева от компьютера: чек-лист «что подключено, а что нет»
local function drawStatus(t, dev)
  local w, h = t.getSize()
  local B = {}
  t.setBackgroundColor(colors.black); t.clear()
  local y = 1
  local function put(x, s, fg, bg)
    if y > h then return end
    t.setCursorPos(x, y)
    if bg then t.setBackgroundColor(bg) end
    t.setTextColor(fg or colors.white); t.write(s:sub(1, math.max(0, w - x + 1)))
    t.setBackgroundColor(colors.black)
  end
  -- текст с переносом по словам (узкие мониторы)
  local function para(x, s, fg)
    local line = ""
    for word in s:gmatch("%S+") do
      if #line > 0 and x + #line + 1 + #word - 1 > w then
        put(x, line, fg); y = y + 1; line = word
      else
        line = #line > 0 and (line .. " " .. word) or word
      end
    end
    if #line > 0 then put(x, line, fg); y = y + 1 end
  end
  local function tiny(n) return (n:gsub("^%w+:", "")) end
  t.setCursorPos(1, 1); t.setBackgroundColor(colors.gray); t.write(string.rep(" ", w))
  put(1, " CONNECTIONS", colors.white, colors.gray)
  put(w - #VERSION, VERSION, colors.lightGray, colors.gray)
  y = 3
  local allOk = true
  -- state: true = OK, false = NET, "warn" = zhyoltoe preduprezhdenie
  local function item(state, label, names, note)
    if state ~= true and state ~= "warn" then allOk = false end
    local tag, col = "[ OK ]", colors.lime
    if state == "warn" then tag, col = "[ !! ]", colors.yellow
    elseif state ~= true then tag, col = "[ NO ]", colors.red end
    put(1, tag, col)
    put(8, label, colors.white)
    y = y + 1
    if names and #names > 0 then
      local s = {}
      for _, n in ipairs(names) do s[#s + 1] = tiny(n) end
      para(9, table.concat(s, ", "), colors.lightGray)
    end
    if note then para(9, note, state == true and colors.lightGray or col) end
  end
  local function namesOf(list)
    local t2 = {}
    for _, x in ipairs(list) do t2[#t2 + 1] = type(x) == "table" and x.name or x end
    return t2
  end
  local mixN, pressN, water = {}, {}, false
  for _, b in ipairs(M.basin) do
    if b.role ~= "compact" then mixN[#mixN + 1] = b.name end
    if b.role ~= "mix" then pressN[#pressN + 1] = b.name end
    if b.role ~= "compact" and fluidIn(b.name, "minecraft:water") >= 250 then water = true end
  end
  local tankW = tankFluid("minecraft:water")
  if tankW >= 250 then water = true end
  put(1, "Machines:", colors.yellow); y = y + 1
  item(#M.furnace > 0, "Industrial furnace", namesOf(M.furnace),
    #M.furnace == 0 and "modem on any furnace block except the front" or nil)
  item(#M.crush > 0, "Crushing wheels", namesOf(M.crush),
    #M.crush == 0 and "modem next to the controller (between the wheels)" or nil)
  item(#M.mill > 0, "Millstone", namesOf(M.mill))
  item(#M.wash > 0, "Washing (depot)", namesOf(M.wash))
  item(#M.basin >= 2 and #mixN > 0, "Basin with mixer", mixN,
    #M.basin < 2 and "need 2 basins (mixer + press)" or nil)
  item(#M.basin >= 2 and #pressN > 0, "Basin with press", pressN)
  local tankNames = {}
  for _, t in ipairs(M.tanks) do tankNames[#tankNames + 1] = t .. " " .. fluidIn(t, "minecraft:water") .. "mB" end
  item(water, "Water (tank or mixer basin)", tankNames,
    not water and "connect a tank with water, or a pipe into the mixer basin" or nil)
  if #M.lines == 0 then
    item(false, "Assembly line", nil, "modem on the FIRST segment of the belt")
  end
  for _, line in ipairs(M.lines) do
    local js = {}
    for _, r in ipairs(LINE_RECIPES) do if lineAllows(line, r) then js[#js + 1] = iname(r.main) end end
    local okDeps = #line.deps >= 2 or not lineNeedsDeps(line)
    item(okDeps, "Line " .. tiny(line.belt) .. ": " .. (line.jobs and (#js .. " jobs") or "all jobs"), line.deps,
      (not okDeps and ("deployers " .. #line.deps .. " of 2 (menu > lines > DEP)") or nil))
    if line.jobs and #js > 0 then para(9, table.concat(js, ", "), colors.lightGray) end
  end
  -- каждой сборке нужна линия
  for _, r in ipairs(LINE_RECIPES) do
    local ok = false
    for _, line in ipairs(M.lines) do
      if lineAllows(line, r) and (#line.deps >= (r.base and #r.deploy > 0 and 1 or 0)) then ok = true end
    end
    if not ok and #M.lines > 0 then item(false, "Line for " .. iname(r.main), nil, "menu > lines > JOBS") end
  end
  if S.noFiller then
    item(false, "Deployer filler", nil, "empty deployers hold the belt: put a few cobblestone (any junk) into BYPRODUCTS")
  end
  item(#M.buffers >= 3 and true or "warn", "Receivers (" .. #M.buffers .. ")", M.buffers,
    #M.buffers < 3 and "need: chest in front of furnace, hopper under crusher, receiver at belt end" or nil)
  y = y + 1
  put(1, "Storages:", colors.yellow); y = y + 1
  for _, r in ipairs(ROLES) do
    local present = {}
    local lost = false
    for _, n in ipairs(cfg[r.key]) do
      if peripheral.isPresent(n) then present[#present + 1] = n else lost = true end
    end
    item(#present > 0 and not lost, r.name, present,
      #cfg[r.key] == 0 and "not selected (menu > SELECT)" or (lost and "chest is gone from the network" or nil))
  end
  y = y + 1
  para(1, "PC cannot see: blaze burners (superheat), rotation, fan with water", colors.gray)
  if allOk then
    put(1, " ALL CONNECTED ", colors.black, colors.lime)
  else
    put(1, " SOMETHING IS MISSING ", colors.white, colors.red)
  end
  t.setCursorPos(w - 9, h); t.setBackgroundColor(colors.blue); t.setTextColor(colors.white); t.write(" REFRESH ")
  t.setBackgroundColor(colors.black)
  B[#B + 1] = {x1 = w - 9, x2 = w - 1, y = h, id = "refresh"}
  BTN[dev] = B   -- кнопки публикуем после отрисовки целиком
end

-- Кадр рисуется в невидимое окно и выводится целиком: пока рисуем, программа опрашивает
-- баки и бассейны (это отдаёт управление), и без буфера экран мигал пустым.
local WIN = {}
local function frame(dev, target, fn)
  local w, h = target.getSize()
  local b = WIN[dev]
  if not b or b.w ~= w or b.h ~= h then
    b = {w = w, h = h, win = window.create(target, 1, 1, w, h, false)}
    WIN[dev] = b
  end
  b.win.setVisible(false)
  fn(b.win, dev)
  -- содержимое не поменялось - монитор не трогаем вовсе (иначе он перерисовывается и мигает)
  local sig = {}
  for y = 1, h do
    local t, f, bg = b.win.getLine(y)
    sig[#sig + 1] = t .. f .. bg
  end
  sig = table.concat(sig, "\n")
  if sig ~= b.last then
    b.win.setVisible(true)
    b.last = sig
  end
end

local drawing, again = false, false
local function redraw()
  if drawing then again = true; return end   -- второй поток уже рисует: дорисует и он
  drawing = true
  repeat
    again = false
    for _, m in ipairs(M.monitors) do
      local mon = peripheral.wrap(m)
      if mon then
        if mon.getTextScale() ~= 0.5 then mon.setTextScale(0.5) end
        frame(m, mon, m == STATUS_MON and drawStatus or draw)
      end
    end
    frame("term", term.native(), draw)
  until not again
  drawing = false
end

---------------------------------------------------------------- запуск заходов
-- следующий заход: самая большая партия, на которую хватает (до MAX_BATCH и до остатка заказа)
local function startNext()
  discover()
  scan(); drain(); unloadDeployers()
  local left = cfg.target > 0 and (cfg.target - cfg.done) or MAX_BATCH
  for k = math.min(MAX_BATCH, left), 1, -1 do
    S.qty = k
    local ok, runs = check()
    if ok then
      S.runs = runs
      S.mode = "run"
      S.startOut = countOutput()
      S.t0 = now()
      S.msg = ""
      progress()
      return true
    end
    if S.noMachine then break end
  end
  S.mode = "wait"
  return false
end

local function press(id, arg)
  S.msg = ""
  if id == "pick" then
    UI.role = arg; UI.scroll = 0; UI.cand = candidates(); UI.screen = "pick"
  elseif id == "toggle" then
    local list = cfg[UI.role]
    if inList(list, arg) then
      for i, n in ipairs(list) do if n == arg then table.remove(list, i) break end end
    else
      for _, r in ipairs(ROLES) do       -- у хранилища одна роль
        for i, n in ipairs(cfg[r.key]) do if n == arg then table.remove(cfg[r.key], i) break end end
      end
      list[#list + 1] = arg
    end
    saveCfg(); discover()
  elseif id == "basin" then
    local cur = cfg.basins[arg]
    cfg.basins[arg] = cur == nil and "mix" or (cur == "mix" and "compact" or nil)
    saveCfg(); discover()
  elseif id == "line" then UI.belt = arg; UI.scroll = 0; UI.screen = "pickdeps"
  elseif id == "toggledep" then
    -- первая ручная настройка ленты берёт то, что было назначено автоматически
    if not cfg.lines[UI.belt] then
      cfg.lines[UI.belt] = {}
      for _, line in ipairs(M.lines) do
        if line.belt == UI.belt then for _, d in ipairs(line.deps) do table.insert(cfg.lines[UI.belt], d) end end
      end
    end
    local list = cfg.lines[UI.belt]
    if inList(list, arg) then
      for i, n in ipairs(list) do if n == arg then table.remove(list, i) break end end
    else
      for _, other in pairs(cfg.lines) do         -- развёртыватель стоит над одной лентой
        for i, n in ipairs(other) do if n == arg then table.remove(other, i) break end end
      end
      list[#list + 1] = arg
    end
    saveCfg(); discover()
  elseif id == "jobs" then UI.belt = arg; UI.screen = "pickjobs"
  elseif id == "jobsall" then cfg.lineJobs[UI.belt] = nil; saveCfg(); discover()
  elseif id == "togglejob" then
    local jobs = cfg.lineJobs[UI.belt]
    if jobs == nil then      -- из «все» в выбор: снимаем только нажатую
      jobs = {}
      for _, r in ipairs(LINE_RECIPES) do jobs[r.id] = true end
    end
    if jobs[arg] then jobs[arg] = nil else jobs[arg] = true end
    cfg.lineJobs[UI.belt] = jobs
    saveCfg(); discover()
  elseif id == "list" then UI.scroll = 0; UI.screen = "list"
  elseif id == "up" then UI.scroll = math.max(0, UI.scroll - 5)
  elseif id == "down" then UI.scroll = UI.scroll + 5
  elseif id == "back" then UI.screen = "menu"
  elseif id == "refresh" then discover(); S.msg = "Network rescanned"
  elseif id == "tostart" then
    if storagesReady() then
      UI.screen = "start"; UI.canMake = nil
    else
      S.msg = "Select all 4 storages first"
    end
  elseif id == "menu" then UI.screen = "menu"
  elseif id == "qty" then UI.inf = false; UI.editQty = math.max(1, math.min(999, UI.editQty + arg))
  elseif id == "inf" then UI.inf = not UI.inf
  elseif id == "probe" then
    S.msg = "Counting..."; redraw()
    discover(); S.qty = 1; check()
    UI.canMake = maxMakeable()
    S.msg = ""
  elseif id == "go" then
    cfg.target = UI.inf and 0 or UI.editQty
    cfg.done = 0
    cfg.active = true
    saveCfg()
    UI.screen = "work"; S.mode = "wait"; S.lastAuto = 0
  elseif id == "stop" then
    stop()
    cfg.active = false; saveCfg()
    UI.screen = "start"; S.msg = "Stopped. Done: " .. cfg.done
  end
end

---------------------------------------------------------------- главный цикл
local function worker()
  while true do
    if cfg.active then
      if S.mode == "run" then
        discover()
        scan()
        drain()
        scan()
        dispatchSimple("crush", M.crush, PER_CRUSH, nil)
        dispatchSimple("wash", M.wash, PER_WASH, S.washJob)
        dispatchSimple("mill", M.mill, PER_MILL, S.millJob)
        dispatchFurnace()
        dispatchBasins()
        dispatchLine()
        if allDone() then
          cfg.done = cfg.done + S.qty
          unloadDeployers()
          S.mode = "wait"; S.lastAuto = 0
          if cfg.target > 0 and cfg.done >= cfg.target then
            cfg.active = false
            UI.screen = "start"
            S.msg = "FINISHED: made " .. cfg.done
          end
          saveCfg()
        elseif now() - S.lastProgress > STALL then
          local wait = {}
          for rid, n in pairs(S.runs) do if n > 0 then wait[#wait + 1] = iname(byId[rid].main) end end
          S.stall = #wait > 0 and ("waiting for: " .. table.concat(wait, ", ")) or "machines give no output"
        end
      elseif now() - (S.lastAuto or 0) >= AUTO_EVERY then
        S.lastAuto = now()
        startNext()
      end
    end
    redraw()
    sleep(TICK)
  end
end

local function ui()
  while true do
    local e, a, x, y = os.pullEvent()
    if e == "monitor_touch" or e == "mouse_click" then
      local dev = e == "monitor_touch" and a or "term"
      for _, b in ipairs(BTN[dev] or {}) do
        if y == b.y and x >= b.x1 and x <= b.x2 then press(b.id, b.arg); break end
      end
      redraw()
    elseif e == "mouse_scroll" then
      UI.scroll = math.max(0, UI.scroll + a * 3)
      redraw()
    elseif e == "peripheral" or e == "peripheral_detach" then
      -- без немедленной перерисовки: экран обновится в обычном цикле раз в секунду
      discover()
      if UI.screen == "pick" then UI.cand = candidates() end
    end
  end
end

loadCfg()
-- автозапуск при включении компьютера (после рестарта сервера тоже)
if shell and not fs.exists("startup.lua") then
  local f = fs.open("startup.lua", "w")
  f.write('shell.run("' .. shell.getRunningProgram() .. '")\n'); f.close()
end
discover()
if cfg.active then
  UI.screen = "work"; S.mode = "wait"; S.lastAuto = 0   -- заказ продолжается после перезапуска
  UI.editQty = cfg.target > 0 and cfg.target or 1
else
  UI.screen = "menu"
end
redraw()
parallel.waitForAny(worker, ui)
