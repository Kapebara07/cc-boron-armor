-- Установщик/обновлятор автозавода Карбид-борной брони.
-- В компьютере: wget run https://raw.githubusercontent.com/Kapebara07/cc-boron-armor/main/install.lua
local REPO = "Kapebara07/cc-boron-armor"
local FILES = {"boron.lua", "recipes.lua"}

-- Берём файлы по номеру последнего коммита: ссылка на "main" кэшируется GitHub до 5 минут,
-- и сразу после обновления можно было скачать старую версию.
local ref = "main"
local api = http.get("https://api.github.com/repos/" .. REPO .. "/commits/main",
  {["User-Agent"] = "cc-boron-armor", ["Accept"] = "application/vnd.github+json"})
if api then
  local ok, data = pcall(textutils.unserializeJSON, api.readAll())
  api.close()
  if ok and type(data) == "table" and type(data.sha) == "string" then ref = data.sha end
end
print("Version source: " .. (ref == "main" and "main (cache possible)" or ref:sub(1, 7)))
local BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. ref .. "/"

for _, f in ipairs(FILES) do
  local h, err = http.get({url = BASE .. f .. "?t=" .. os.epoch("utc"), binary = true})
  if not h then error("Failed to download " .. f .. ": " .. tostring(err), 0) end
  local data = h.readAll(); h.close()
  local out = fs.open(f, "wb"); out.write(data); out.close()
  local v = data:match('local VERSION = "([^"]+)"')
  print("OK " .. f .. " (" .. #data .. " bytes)" .. (v and (", " .. v) or ""))
end

-- автозапуск; чужой startup.lua сохраняем рядом
local START = 'shell.run("boron")\n'
if fs.exists("startup.lua") then
  local h = fs.open("startup.lua", "r"); local cur = h.readAll(); h.close()
  if not cur:find('shell.run%("boron') then
    if fs.exists("startup.lua.bak") then fs.delete("startup.lua.bak") end
    fs.move("startup.lua", "startup.lua.bak")
    print("Old startup.lua saved as startup.lua.bak")
  end
end
local s = fs.open("startup.lua", "w"); s.write(START); s.close()

print("Done. Settings (armor.cfg) kept if they existed.")
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
