-- Эмулятор CC: Tweaked + машин Create/arcon для прогонки armor.lua без игры.
-- Глобалы: SRC (папка с armor.lua), SCENARIO (таблица со складом), LIMIT (сек виртуального времени)
local T = 0
local LOG = {}
local function log(...) LOG[#LOG + 1] = string.format("[%5d] ", T) .. string.format(...) end
local rng = 12345
local function rand() rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648 end

-- файловая система в памяти
local FILES = {}
fs = {
  combine = function(a, b) if a == "" then return b end return a .. "/" .. b end,
  getDir = function(p) return p:match("^(.*)/[^/]*$") or "" end,
  exists = function(p) return FILES[p] ~= nil or p == "recipes.lua" end,
  open = function(p, mode)
    if mode == "r" then
      local data = FILES[p]
      return {readAll = function() return data end, close = function() end}
    end
    local buf = {}
    return {write = function(s) buf[#buf + 1] = s end, close = function() FILES[p] = table.concat(buf) end}
  end,
}
local function ser(v)
  if type(v) == "table" then
    local t = {}
    for k, x in pairs(v) do t[#t + 1] = "[" .. ser(k) .. "]=" .. ser(x) end
    return "{" .. table.concat(t, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end
textutils = {
  serialize = ser,
  unserialize = function(s) local f = load("return " .. s); return f and f() end,
}
colors = setmetatable({}, {__index = function(_, k) return k end})
keys = {s = 31, enter = 28, up = 200, down = 208}
os.epoch = function() return T * 1000 end
local realDofile = dofile
dofile = function(p) return realDofile(SRC .. "/" .. p) end
shell = nil

-- экран
local function mkTerm(w, h)
  local t = {lines = {}, x = 1, y = 1}
  function t.getSize() return w, h end
  function t.clear() t.lines = {} end
  function t.setCursorPos(x, y) t.x, t.y = x, y end
  function t.getCursorPos() return t.x, t.y end
  function t.write(s)
    local l = t.lines[t.y] or string.rep(" ", w)
    s = tostring(s)
    l = l:sub(1, t.x - 1) .. s .. l:sub(t.x + #s)
    t.lines[t.y] = l:sub(1, w); t.x = t.x + #s
  end
  function t.setTextColor() end
  function t.setBackgroundColor() end
  function t.setTextScale() end
  function t.dump() local o = {} for i = 1, h do o[#o + 1] = (t.lines[i] or ""):gsub("%s+$", "") end return table.concat(o, "\n") end
  return t
end
term = mkTerm(51, 19)
local MON = mkTerm(79, 38)
print = function(...) end
write = function() end
read = function() return "" end

---------------------------------------------------------------- инвентари
local P = {}         -- name -> объект
local R = realDofile(SRC .. "/recipes.lua")

local function newInv(size, opts)
  local inv = {size = size, slots = {}, opts = opts or {}}
  function inv.list()
    local o = {}
    for i = 1, size do local s = inv.slots[i]; if s then o[i] = {name = s.name, count = s.count} end end
    return o
  end
  -- вставка: возвращает сколько вставлено
  function inv.insert(stack, n, toSlot)
    if inv.opts.accept and not inv.opts.accept(stack, toSlot) then return 0 end
    local moved = 0
    local function tryslot(i)
      if inv.opts.inputSlots and not inv.opts.inputSlots[i] then return end
      local s = inv.slots[i]
      local cap = inv.opts.cap or 64
      if s == nil then
        local m = math.min(cap, n - moved)
        inv.slots[i] = {name = stack.name, count = m, seq = stack.seq}; moved = moved + m
      elseif s.name == stack.name and not s.seq and not stack.seq then
        local m = math.min(cap - s.count, n - moved)
        s.count = s.count + m; moved = moved + m
      end
    end
    if toSlot then tryslot(toSlot) else
      for i = 1, size do if moved < n then tryslot(i) end end
    end
    return moved
  end
  return inv
end

local function move(from, fromSlot, to, limit, toSlot)
  local s = from.slots[fromSlot]
  if not s then return 0 end
  if from.opts.noExtract then return 0 end
  local n = math.min(limit or 64, s.count)
  local m = to.insert(s, n, toSlot)
  s.count = s.count - m
  if s.count <= 0 then from.slots[fromSlot] = nil end
  return m
end

local function addPeripheral(name, inv)
  P[name] = inv
  inv.name = name
  inv.pushItems = function(to, slot, limit, toSlot)
    assert(P[to], "no peripheral " .. tostring(to)); return move(inv, slot, P[to], limit, toSlot)
  end
  inv.pullItems = function(from, slot, limit, toSlot) return move(P[from], slot, inv, limit, toSlot) end
  inv.getItemDetail = function(slot) return inv.slots[slot] end
  inv.size_ = inv.size
end

peripheral = {
  getNames = function() local o = {} for n in pairs(P) do o[#o + 1] = n end table.sort(o) return o end,
  hasType = function(n, t)
    if t == "monitor" then return n == "monitor_0" end
    return P[n] ~= nil and n ~= "monitor_0"
  end,
  call = function(n, m, ...)
    local p = P[n]
    if not p then error("no peripheral " .. n) end
    if m == "size" then return p.size end
    return p[m](...)
  end,
  wrap = function(n) return MON end,
}
P.monitor_0 = {}

---------------------------------------------------------------- машины
local function recipesOf(station)
  local t = {}
  for _, r in ipairs(R.list) do if r.station == station then t[#t + 1] = r end end
  return t
end
local function rollOuts(r, put)
  for _, o in ipairs(r.outs) do
    if o.chance >= 1 or rand() < o.chance then put(o.item, o.n) end
  end
end

-- склады
addPeripheral("minecraft:chest_0", newInv(108))  -- сырьё
addPeripheral("minecraft:chest_1", newInv(108))  -- запасы
addPeripheral("minecraft:chest_2", newInv(27))   -- броня
addPeripheral("minecraft:chest_3", newInv(54))   -- побочка
-- приёмники
addPeripheral("minecraft:hopper_0", newInv(5))   -- под дробилкой
addPeripheral("minecraft:dropper_0", newInv(9))  -- конец ленты
addPeripheral("minecraft:chest_9", newInv(27))   -- перед печью
addPeripheral("minecraft:barrel_0", newInv(27))  -- лишний приёмник
addPeripheral("create:mechanical_saw_0", newInv(1)) -- пила (не трогать)

local function putInto(inv, item, n)
  local m = inv.insert({name = item}, n)
  if m < n then log("ПОТЕРЯ %d %s (нет места в %s)", n - m, item, inv.name) end
end

-- дробилка
addPeripheral("create:crushing_wheel_controller_0", newInv(1))
-- промывка: 2 депо (слот 1 вход, 2..9 выход)
for i = 0, 1 do
  addPeripheral("create:depot_" .. i, newInv(9, {inputSlots = {[1] = true}}))
end
-- бассейны: 0 = пресс (compact), 1 = миксер
local BASIN_TRUTH = {["create:basin_0"] = "compact", ["create:basin_1"] = "mix"}
for n in pairs(BASIN_TRUTH) do
  addPeripheral(n, newInv(18, {inputSlots = {[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true}}))
end
-- жернова: слот 1 вход, 2..10 выход
addPeripheral("create:millstone_0", newInv(10, {inputSlots = {[1] = true}}))
-- вода в бассейне с миксером (труба доливает 250 мБ/сек до 1000)
WATER = {["create:basin_1"] = NO_WATER and 0 or 1000, ["create:basin_0"] = 0}
for n in pairs(BASIN_TRUTH) do
  P[n].tanks = function() return {{name = "minecraft:water", amount = WATER[n]}} end
end
-- печь: входной обработчик 8 слотов
addPeripheral("arcon:furnace_multiblock_0", newInv(8))
-- лента
addPeripheral("create:belt_0", newInv(1, {cap = 1}))
addPeripheral("create:deployer_0", newInv(1))
addPeripheral("create:deployer_1", newInv(1))

local FURN = {busy = 0, r = nil}
local function tickMachines()
  -- дробилка: 1 предмет/сек
  local c = P["create:crushing_wheel_controller_0"]
  local s = c.slots[1]
  if s then
    for _, r in ipairs(recipesOf("crush")) do
      if r.ins[1][1] == s.name then
        s.count = s.count - 1; if s.count == 0 then c.slots[1] = nil end
        rollOuts(r, function(it, n) putInto(P["minecraft:hopper_0"], it, n) end)
        break
      end
    end
  end
  -- промывка: стак целиком, раз в 3 сек
  if T % 3 == 0 then
    for i = 0, 1 do
      local d = P["create:depot_" .. i]; local s = d.slots[1]
      if s then
        for _, r in ipairs(recipesOf("wash")) do
          if r.ins[1][1] == s.name then
            local n = s.count; d.slots[1] = nil
            for _ = 1, n do rollOuts(r, function(it, k) putInto(d, it, k) end) end
            break
          end
        end
      end
    end
  end
  -- жернова: 1 предмет/сек
  local ms = P["create:millstone_0"]
  local s1 = ms.slots[1]
  if s1 then
    for _, r in ipairs(recipesOf("mill")) do
      if r.ins[1][1] == s1.name then
        s1.count = s1.count - 1; if s1.count == 0 then ms.slots[1] = nil end
        rollOuts(r, function(it, n)
          for i = 2, 10 do
            local o = ms.slots[i]
            if o and o.name == it and o.count + n <= 64 then o.count = o.count + n; return end
            if not o then ms.slots[i] = {name = it, count = n}; return end
          end
          log("ПОТЕРЯ жернова %s", it)
        end)
        break
      end
    end
  end
  if not NO_WATER then
    for n, v in pairs(WATER) do if n == "create:basin_1" then WATER[n] = math.min(1000, v + 250) end end
  end
  -- бассейны: одна партия в 2 сек
  if T % 2 == 0 then
    for name, role in pairs(BASIN_TRUTH) do
      local b = P[name]
      for _, r in ipairs(recipesOf(role)) do
        local need = {}
        for _, a in ipairs(r.ins) do need[a[1]] = (need[a[1]] or 0) + 1 end
        local ok = true
        for it, n in pairs(need) do
          local c = 0
          for i = 1, 9 do if b.slots[i] and b.slots[i].name == it then c = c + b.slots[i].count end end
          if c < n then ok = false end
        end
        for _, f in ipairs(r.fluids or {}) do
          if WATER[name] < f.amount then ok = false end
        end
        if ok then
          for _, f in ipairs(r.fluids or {}) do WATER[name] = WATER[name] - f.amount end
          for it, n in pairs(need) do
            for i = 1, 9 do
              local s = b.slots[i]
              if s and s.name == it and n > 0 then
                local m = math.min(n, s.count); s.count = s.count - m; n = n - m
                if s.count == 0 then b.slots[i] = nil end
              end
            end
          end
          rollOuts(r, function(it, n)
            local s = nil
            for i = 10, 18 do
              if b.slots[i] and b.slots[i].name == it then s = b.slots[i] break end
            end
            if s then s.count = s.count + n else
              for i = 10, 18 do if not b.slots[i] then b.slots[i] = {name = it, count = n} break end end
            end
          end)
          break
        end
      end
    end
  end
  -- печь: партия = 5 сек; ингредиент -> отдельный слот
  local f = P["arcon:furnace_multiblock_0"]
  if FURN.r then
    FURN.busy = FURN.busy - 1
    if FURN.busy <= 0 then
      rollOuts(FURN.r, function(it, n) putInto(P["minecraft:chest_9"], it, n) end)
      FURN.r = nil
    end
  else
    for _, r in ipairs(recipesOf("furnace")) do
      local used, ok = {}, true
      for _, alts in ipairs(r.ins) do
        local found = false
        for i = 1, 8 do
          local s = f.slots[i]
          if s and not used[i] then
            for _, a in ipairs(alts) do if s.name == a then found = true end end
            if found then used[i] = true; break end
          end
        end
        if not found then ok = false; break end
      end
      if ok then
        for i in pairs(used) do
          f.slots[i].count = f.slots[i].count - 1
          if f.slots[i].count == 0 then f.slots[i] = nil end
        end
        FURN.r = r; FURN.busy = 5
        break
      end
    end
  end
  -- лента: предмет проходит развёртыватели, пилу, пресс за 1 сек и падает в дроппер
  local b = P["create:belt_0"]
  local it = b.slots[1]
  if it then
    b.slots[1] = nil
    local item = {name = it.name, seq = it.seq}
    if not item.seq then
      -- недоделанная со склада без сохранённого прогресса: считаем, что она на первом шаге
      for _, r in ipairs(R.list) do
        if r.transitional == item.name then item.seq = {r = r, step = 1, loop = 1} end
      end
    end
    local d0, d1 = P["create:deployer_0"], P["create:deployer_1"]
    if SWAP_DEPLOYERS then d0, d1 = d1, d0 end
    local stations = {{"deploying", d0}, {"deploying", d1},
                      {"cutting"}, {"pressing"}}
    for _, st in ipairs(stations) do
      -- начало сборки
      if not item.seq then
        for _, r in ipairs(R.list) do
          if r.base and r.base[1] == item.name and r.steps[1] == st[1] then
            local okStart = true
            if st[1] == "deploying" then
              local h = st[2].slots[1]
              okStart = h and h.name == r.deploy[1][1]
            end
            if okStart then item.seq = {r = r, step = 1, loop = 1, di = 1}; item.name = r.transitional; break end
          end
        end
        if not item.seq and st[1] == "pressing" then
          for _, r in ipairs(R.list) do
            if not r.base and r.station == "line" and r.ins[1][1] == item.name then item.name = r.outs[1].item; break end
          end
        end
      end
      local q = item.seq
      if q and q.r.steps[q.step] == st[1] then
        local ok = true
        if st[1] == "deploying" then
          -- номер шага развёртывателя среди deploy-шагов
          local di = 0
          for i = 1, q.step do if q.r.steps[i] == "deploying" then di = di + 1 end end
          local h = st[2].slots[1]
          ok = h and h.name == q.r.deploy[di][1]
          if ok then h.count = h.count - 1; if h.count == 0 then st[2].slots[1] = nil end end
        end
        if ok then
          q.step = q.step + 1
          if q.step > #q.r.steps then
            q.step = 1; q.loop = q.loop + 1
            if q.loop > q.r.loops then item = {name = q.r.outs[1].item} ; q = nil end
          end
        end
      end
    end
    putInto(P["minecraft:dropper_0"], item.name, 1)
    if item.seq then
      -- сохранить прогресс полуфабриката в слоте
      local d = P["minecraft:dropper_0"]
      for i = 9, 1, -1 do
        local s = d.slots[i]
        if s and s.name == item.name and not s.seq and s.count == 1 then s.seq = item.seq break end
      end
    end
  end
end

sleep = function(t)
  for _ = 1, math.max(1, t) do
    T = T + 1
    tickMachines()
  end
  if T > LIMIT then error("LIMIT", 0) end
  if CHECK_DONE and CHECK_DONE() then error("DONE", 0) end
end
EVENTS = {}
os.pullEvent = function()
  if #EVENTS > 0 then return table.unpack(table.remove(EVENTS, 1)) end
  coroutine.yield()
end
parallel = {waitForAny = function(w, u)
  local co = coroutine.create(u)
  repeat
    local ok, err = coroutine.resume(co)
    if not ok then error(err, 0) end
  until #EVENTS == 0
  w()
end}

-- склад сценария
for item, n in pairs(SCENARIO.raw or {}) do putInto(P["minecraft:chest_0"], item, n) end
for item, n in pairs(SCENARIO.stock or {}) do putInto(P["minecraft:chest_1"], item, n) end
FILES["armor.cfg"] = textutils.serialize({raw = {"minecraft:chest_0"}, stock = {"minecraft:chest_1"},
  output = {"minecraft:chest_2"}, waste = {"minecraft:chest_3"}, basins = {}})

function COUNT(name, item)
  local c = 0
  for _, s in pairs(P[name].slots) do if s.name == item then c = c + s.count end end
  return c
end
function DUMP(name)
  local o = {}
  for _, s in pairs(P[name].slots) do o[#o + 1] = s.name .. " x" .. s.count end
  table.sort(o); return table.concat(o, ", ")
end
function SCREEN() return MON.dump() end
function GETLOG() return table.concat(LOG, "\n") end
function TIME() return T end
CHECK_DONE = function() return COUNT("minecraft:chest_2", R.target) >= (SCENARIO.qty or 1) and T > 5 end
