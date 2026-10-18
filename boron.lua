-- boron.lua — автоматическое производство arcon:hull_boron_snow (Карбид-борная броня, Снежная)
-- CC: Tweaked 1.116, Create 6.0.10, Create: Armored Constructs 1.05.
-- Механизмы находятся сами по проводной сети; склады один раз назначаются в настройке (клавиша S).

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

local cfg = {raw = {}, stock = {}, output = {}, waste = {}, basins = {}, auto = true}
local AUTO_EVERY = 10     -- сек: как часто в авторежиме проверять, хватает ли на следующую броню
local function loadCfg()
  if fs.exists(CFG_FILE) then
    local f = fs.open(CFG_FILE, "r"); local t = textutils.unserialize(f.readAll()); f.close()
    if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
  end
end
local function saveCfg()
  local f = fs.open(CFG_FILE, "w"); f.write(textutils.serialize(cfg)); f.close()
end

local function ru(i) return R.ru[i] or i end
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
local function discover()
  M = {crush = {}, wash = {}, mill = {}, basin = {}, furnace = {}, furnaceOut = {}, deployer = {}, belt = {},
       buffers = {}, ignored = {}, monitors = {}}
  for _, n in ipairs(peripheral.getNames()) do
    local b = baseName(n)
    local k = KIND[b]
    if peripheral.hasType(n, "monitor") then
      table.insert(M.monitors, n)
    elseif k == "furnace" then
      local size = call(n, "size") or 0
      if size == 4 then table.insert(M.furnaceOut, {name = n, from = 1})       -- модем на передней грани
      elseif size >= 12 then
        table.insert(M.furnace, {name = n})
        table.insert(M.furnaceOut, {name = n, from = 9})
      else table.insert(M.furnace, {name = n}) end
    elseif k then
      table.insert(M[k], {name = n})
    elseif peripheral.hasType(n, "inventory") then
      if isStorage(n) then -- склады отдельно
      elseif IGNORE[b] then table.insert(M.ignored, n)
      else table.insert(M.buffers, n) end
    end
  end
  for _, bs in ipairs(M.basin) do bs.role = cfg.basins[bs.name] end
  table.sort(M.deployer, function(a, c) return a.name < c.name end)
end

local function stationCount(kind)
  if kind == "line" then return #M.belt end
  if kind == "mix" or kind == "compact" then
    local c = 0
    for _, b in ipairs(M.basin) do if b.role == nil or b.role == kind then c = c + 1 end end
    return c
  end
  return #M[kind]
end
local STATION_RU = {crush = "drobilnye kolesa", wash = "depo promyvki", mill = "zhernova",
  water = "voda v bassein s mikserom (truba ot pompy)", mix = "bassein s mikserom",
  compact = "bassein s pressom", furnace = "promyshlennaya pech", line = "lenta sborki",
  deployer = "razvertyvateli na lente (nuzhno 2)", belt1 = "modem tolko na PERVOM segmente lenty"}

---------------------------------------------------------------- склад
local idx -- item -> {{inv, slot, count}}
local function sources()
  local t = {}
  for _, n in ipairs(cfg.stock) do t[#t + 1] = n end   -- сначала излишки, потом сырьё
  for _, n in ipairs(cfg.raw) do t[#t + 1] = n end
  return t
end
local function scan()
  idx = {}
  local counts = {}
  for _, inv in ipairs(sources()) do
    local l = call(inv, "list") or {}
    for slot, it in pairs(l) do
      idx[it.name] = idx[it.name] or {}
      table.insert(idx[it.name], {inv = inv, slot = slot, count = it.count})
      counts[it.name] = (counts[it.name] or 0) + it.count
    end
  end
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
           stall = nil, line = nil, basinJob = {}, washJob = {}, millJob = {}, furnaceJob = {}}
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
  local L = S.line
  local function fromBuffer(src)
    for slot, it in pairs(call(src, "list") or {}) do
      local seq = transOf[it.name]
      if seq and ((L and L.rid == seq.id) or (#seq.deploy == 0 and S.seqPress and S.seqPress[seq.id])) then
        -- полуфабрикат активной сборки: вернётся на ленту в feedLine
      else
        if routeItem(src, slot, it) then
          if L and it.name == byId[L.rid].main then L.done = L.done + it.count; progress() end
          for rid, sp in pairs(S.seqPress or {}) do
            if it.name == byId[rid].main then sp.done = sp.done + it.count; progress() end
          end
        end
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
local function dispatchSimple(station, machines, per, jobs)
  for _, m in ipairs(machines) do
    if isEmpty(m.name) then
      if jobs then jobs[m.name] = nil end
      for _, r in ipairs(runsFor(station)) do
        local choice, k = pickAlts(r, math.min(per, S.runs[r.id]))
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
        local choice, k = pickAlts(r, math.min(PER_FURNACE, S.runs[r.id]))
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
      for _, r in ipairs(cands) do
        local choice, k = pickAlts(r, fluidBatches(b.name, r, math.min(PER_BASIN, S.runs[r.id])))
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

-- развёртыватели линии
local function unloadDeployers()
  for _, d in ipairs(M.deployer) do
    for slot, it in pairs(call(d.name, "list") or {}) do routeItem(d.name, slot, it) end
  end
end

local function beltFree()
  local b = M.belt[1]
  return b and isEmpty(b.name)
end

local function feedOne(item)
  return give(item, 1, M.belt[1].name) == 1
end

local function feedTransitional()
  for _, src in ipairs(M.buffers) do
    for slot, it in pairs(call(src, "list") or {}) do
      local seq = transOf[it.name]
      if seq then
        local active = (S.line and S.line.rid == seq.id) or (S.seqPress and S.seqPress[seq.id])
        if active and call(src, "pushItems", M.belt[1].name, slot, 1) == 1 then return true end
      end
    end
  end
  return false
end

local function dispatchLine()
  if #M.belt == 0 then return end
  S.seqPress = S.seqPress or {}
  -- завершение сборки с развёртывателями
  local L = S.line
  if L and L.done >= L.k then unloadDeployers(); S.line = nil; L = nil end
  for rid, sp in pairs(S.seqPress) do if sp.done >= sp.k and sp.fed >= sp.k then S.seqPress[rid] = nil end end
  -- запуск новой сборки с развёртывателями
  if not L then
    for _, r in ipairs(runsFor("line")) do
      if r.base and #r.deploy > 0 then
        local cap = math.floor(64 / r.loops)
        if #M.deployer < #r.deploy then
          -- один развёртыватель тянет два шага, только если предмет одинаковый
          if not (#M.deployer == 1 and r.deploy[1][1] == r.deploy[2][1]) then cap = 0
          else cap = math.floor(64 / (r.loops * 2)) end
        end
        local choice, k = pickAlts(r, math.min(cap, S.runs[r.id]))
        if choice and k > 0 then
          unloadDeployers()
          for i = 2, #r.ingr do
            local d = M.deployer[math.min(i - 1, #M.deployer)]
            give(choice[i], r.ingr[i].n * k, d.name)
          end
          S.runs[r.id] = S.runs[r.id] - k
          S.line = {rid = r.id, k = k, fed = 0, done = 0, base = choice[1]}
          L = S.line
          progress()
          break
        end
      end
    end
  end
  -- сборки только с прессом (броневая плита) — без развёртывателей
  for _, r in ipairs(runsFor("line")) do
    if r.base and #r.deploy == 0 and not S.seqPress[r.id] then
      local choice, k = pickAlts(r, S.runs[r.id])
      if choice then
        S.runs[r.id] = S.runs[r.id] - k
        S.seqPress[r.id] = {k = k, fed = 0, done = 0, base = choice[1]}
      end
    end
  end
  if not beltFree() then return end
  -- 1) полуфабрикаты обратно на ленту
  if feedTransitional() then progress(); return end
  -- 2) заготовки активной сборки (или недоделанные со склада — pickAlts выбрал их как основу)
  if L and L.fed < L.k and feedOne(L.base) then L.fed = L.fed + 1; progress(); return end
  for _, sp in pairs(S.seqPress) do
    if sp.fed < sp.k and feedOne(sp.base) then sp.fed = sp.fed + 1; progress(); return end
  end
  -- 3) простое прессование (листы)
  for _, r in ipairs(runsFor("line")) do
    if not r.base and have(r.ingr[1].alts[1]) > 0 and feedOne(r.ingr[1].alts[1]) then
      S.runs[r.id] = S.runs[r.id] - 1; progress(); return
    end
  end
end

local function allDone()
  for _, n in pairs(S.runs) do if n > 0 then return false end end
  if S.line or next(S.seqPress or {}) then return false end
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
    if n > 0 and r.base and #r.deploy > 0 then
      local same = #r.deploy == 2 and r.deploy[1][1] == r.deploy[2][1]
      if #M.deployer == 0 or (#M.deployer < #r.deploy and not same) then lack.deployer = true end
    end
    if n > 0 and r.station == "line" and #M.belt > 1 then lack.belt1 = true end
    if n > 0 and r.station == "mix" then needMix = true end
    if n > 0 and r.station == "compact" then needCompact = true end
  end
  if needMix and needCompact and #M.basin < 2 then lack.mix = true; lack.compact = true end
  -- рецепты с жидкостью: хоть в одном бассейне (миксер или ещё не опознан) должна быть вода
  for rid, n in pairs(res) do
    local r = byId[rid]
    if n > 0 and r.fluids then
      local ok = false
      for _, b in ipairs(M.basin) do
        if b.role ~= "compact" and fluidBatches(b.name, r, 1) >= 1 then ok = true end
      end
      if not ok then lack.water = true end
    end
  end
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
  S.mode = "idle"; S.runs = {}; S.line = nil; S.seqPress = {}
  unloadDeployers()
end

---------------------------------------------------------------- экран
local function fmtTime(s)
  s = math.floor(s)
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local buttons = {}
local function draw(t, isMon)
  local w, h = t.getSize()
  t.setBackgroundColor(colors.black); t.clear()
  local function line(y, text, fg, bg)
    if y > h then return end
    t.setCursorPos(1, y)
    if bg then t.setBackgroundColor(bg); t.write(string.rep(" ", w)); t.setCursorPos(1, y) end
    t.setTextColor(fg or colors.white); t.write(text:sub(1, w))
    t.setBackgroundColor(colors.black)
  end
  line(1, " " .. ru(R.target), colors.white, colors.gray)
  local y = 3
  if S.mode == "run" then
    local done = countOutput() - S.startOut
    line(2, string.format(" IDET SBORKA  %d/%d  vremya %s", done, S.qty, fmtTime(now() - S.t0)), colors.black, colors.yellow)
    if S.stall then line(y, " ! Net progressa " .. fmtTime(now() - S.lastProgress) .. ": " .. S.stall, colors.red); y = y + 1 end
    local list = {}
    for rid, n in pairs(S.runs) do if n > 0 then list[#list + 1] = {rid, n} end end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    line(y, " Ostalos zapustit:", colors.lightGray); y = y + 1
    for _, e in ipairs(list) do
      local r = byId[e[1]]
      line(y, string.format("  %-9s x%-3d %s", r.station, e[2], ru(r.main)), colors.white); y = y + 1
    end
    if S.line then
      line(y, string.format(" Lenta: %s  %d/%d", ru(byId[S.line.rid].main), S.line.done, S.line.k), colors.cyan); y = y + 1
    end
  elseif S.missing then
    line(2, cfg.auto and " NE HVATAET RESURSOV - avto zhdet, dokladyvay v syre" or " NE HVATAET RESURSOV",
      colors.white, colors.red)
    local list = {}
    for it, n in pairs(S.missing) do list[#list + 1] = {it, n} end
    table.sort(list, function(a, b) return a[1] < b[1] end)
    for _, e in ipairs(list) do
      local via = {}
      for _, r in ipairs(byOut[e[1]] or {}) do
        local a = r.ingr[1].alts[1]
        if #r.ingr == 1 then via[#via + 1] = ru(a) end
      end
      local txt = string.format("  x%-4d %s", e[2], ru(e[1]))
      if #via > 0 then txt = txt .. "  (iz: " .. table.concat(via, ", ") .. ")" end
      line(y, txt, colors.red); y = y + 1
    end
  elseif S.noMachine then
    line(2, " NE HVATAET MEHANIZMOV", colors.white, colors.red)
    for k in pairs(S.noMachine) do
      local txt = k == "storage" and "sklady ne naznacheny (klavisha S na PK)" or (STATION_RU[k] or k)
      line(y, "  " .. txt, colors.red); y = y + 1
    end
  else
    line(2, " VSE EST - MOZHNO SOZDAT", colors.black, colors.lime)
  end
  if S.msg ~= "" then line(y, " " .. S.msg, colors.orange); y = y + 1 end
  -- механизмы
  local nb = {mix = 0, compact = 0, unk = 0}
  for _, b in ipairs(M.basin) do
    if b.role then nb[b.role] = nb[b.role] + 1 else nb.unk = nb.unk + 1 end
  end
  line(h - 2, string.format(" Pechi %d  Drobilki %d  Zhernova %d  Promyvka %d  Bassein mix %d/press %d/? %d",
    #M.furnace, #M.crush, #M.mill, #M.wash, nb.mix, nb.compact, nb.unk), colors.lightGray)
  line(h - 1, string.format(" Lenta %s  Razvertyvateli %d  Priemniki %d",
    #M.belt == 1 and "da" or (#M.belt == 0 and "NET" or "LISHNYAYA (" .. #M.belt .. ")"),
    #M.deployer, #M.buffers), colors.lightGray)
  -- кнопки
  buttons = {}
  t.setCursorPos(1, h)
  local function btn(label, bg, id)
    local x = t.getCursorPos()
    t.setBackgroundColor(bg); t.setTextColor(colors.white); t.write(" " .. label .. " ")
    t.setBackgroundColor(colors.black); t.write(" ")
    buttons[#buttons + 1] = {x1 = x, x2 = x + #label + 1, id = id}
  end
  if S.mode == "run" then
    btn("STOP", colors.red, "stop")
  else
    btn("-", colors.gray, "minus")
    t.setTextColor(colors.white); t.write(tostring(S.qty) .. " ")
    btn("+", colors.gray, "plus")
    btn("SOZDAT", (S.missing or S.noMachine) and colors.gray or colors.green, "go")
    btn("PROVERIT", colors.blue, "check")
    btn(cfg.auto and "AVTO: VKL" or "AVTO: VYKL", cfg.auto and colors.green or colors.gray, "auto")
  end
  if not isMon then
    t.setBackgroundColor(colors.black); t.setTextColor(colors.gray); t.write(" S-sklady")
  end
end

local function redraw()
  for _, m in ipairs(M.monitors) do
    local mon = peripheral.wrap(m)
    mon.setTextScale(0.5)
    draw(mon, true)
  end
  if not S.inSetup then draw(term, false) end
end

local function press(id)
  if id == "minus" then S.qty = math.max(1, S.qty - 1); check()
  elseif id == "plus" then S.qty = math.min(16, S.qty + 1); check()
  elseif id == "check" then discover(); check()
  elseif id == "go" then
    if not start() then S.msg = "Zapusk otmenen: chego-to ne hvataet" else S.msg = "" end
  elseif id == "stop" then
    stop(); cfg.auto = false; saveCfg(); S.msg = "Ostanovleno, avtorezhim vyklyuchen"
  elseif id == "auto" then
    cfg.auto = not cfg.auto; saveCfg(); S.lastAuto = 0
    S.msg = cfg.auto and "Avtorezhim vklyuchen" or "Avtorezhim vyklyuchen"
  end
end

---------------------------------------------------------------- настройка складов
local function setup()
  S.inSetup = true
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  local invs = {}
  for _, n in ipairs(peripheral.getNames()) do
    local b = baseName(n)
    if peripheral.hasType(n, "inventory") and not KIND[b] and not IGNORE[b] then invs[#invs + 1] = n end
  end
  table.sort(invs)
  print("Hranilischa v seti:")
  for i, n in ipairs(invs) do
    local l = call(n, "list") or {}
    local c = 0
    for _ in pairs(l) do c = c + 1 end
    print(string.format("%2d) %s  (zanyato slotov %d/%d)", i, n, c, call(n, "size") or 0))
  end
  local function ask(q)
    write(q .. " (nomera cherez probel): ")
    local t = {}
    for num in read():gmatch("%d+") do
      local n = invs[tonumber(num)]
      if n then t[#t + 1] = n end
    end
    return t
  end
  cfg.raw = ask("SYRE (kuda ty kladesh rudu/ugol/slitki)")
  cfg.stock = ask("ZAPASY (izlishki i polufabrikaty)")
  cfg.output = ask("GOTOVAYA BRONYA")
  cfg.waste = ask("POBOCHNOE (opyt, bulyzhnik i t.p.)")
  saveCfg()
  print("Sohraneno. Vse ostalnye sunduki = priemniki rezultatov mashin.")
  sleep(2)
  S.inSetup = false
end

---------------------------------------------------------------- главный цикл
local function worker()
  while true do
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
        S.mode = "idle"; S.msg = "GOTOVO: sozdano " .. S.qty
        unloadDeployers()
        check()
      elseif now() - S.lastProgress > STALL then
        local wait = {}
        for rid, n in pairs(S.runs) do if n > 0 then wait[#wait + 1] = ru(byId[rid].main) end end
        S.stall = #wait > 0 and ("zhdu: " .. table.concat(wait, ", ")) or "mashiny ne vydayut rezultat"
      end
    elseif cfg.auto and not S.inSetup and now() - (S.lastAuto or 0) >= AUTO_EVERY then
      -- авторежим: как только на складе хватает на броню — начинаем сами
      S.lastAuto = now()
      if start() then S.msg = "Avto: sborka nachata" end
    end
    redraw()
    sleep(TICK)
  end
end

local function ui()
  while true do
    local e, a, x, y = os.pullEvent()
    if e == "monitor_touch" or e == "mouse_click" then
      local t = e == "monitor_touch" and peripheral.wrap(a) or term
      local _, h = t.getSize()
      if y == h then
        for _, b in ipairs(buttons) do if x >= b.x1 and x <= b.x2 then press(b.id) end end
      end
      redraw()
    elseif e == "key" and S.mode ~= "run" then
      if a == keys.s then setup(); discover(); check()
      elseif a == keys.enter then press("go")
      elseif a == keys.up then press("plus")
      elseif a == keys.down then press("minus") end
      redraw()
    elseif e == "peripheral" or e == "peripheral_detach" then
      discover(); if S.mode ~= "run" then check() end
      redraw()
    end
  end
end

loadCfg()
-- автозапуск при включении компьютера (после рестарта сервера тоже)
if shell and not fs.exists("startup.lua") then
  local f = fs.open("startup.lua", "w")
  f.write('shell.run("' .. shell.getRunningProgram() .. '")\n'); f.close()
end
if #cfg.output == 0 then setup() end
discover()
-- выгрузить остатки прошлой работы
scan(); drain(); unloadDeployers()
check()
redraw()
parallel.waitForAny(worker, ui)
