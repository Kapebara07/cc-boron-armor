-- Установщик/обновлятор автозавода Карбид-борной брони.
-- В компьютере: wget run https://raw.githubusercontent.com/Kapebara07/cc-boron-armor/main/install.lua
local BASE = "https://raw.githubusercontent.com/Kapebara07/cc-boron-armor/main/"
local FILES = {"boron.lua", "recipes.lua"}

for _, f in ipairs(FILES) do
  -- ?t= обходит кэш raw.githubusercontent.com после обновлений
  local h, err = http.get({url = BASE .. f .. "?t=" .. os.epoch("utc"), binary = true})
  if not h then error("Failed to download " .. f .. ": " .. tostring(err), 0) end
  local data = h.readAll(); h.close()
  local out = fs.open(f, "wb"); out.write(data); out.close()
  print("OK " .. f .. " (" .. #data .. " bytes)")
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
