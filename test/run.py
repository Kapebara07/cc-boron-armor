import sys, lupa.lua52 as L
SRC = sys.argv[1]
def run(scn, limit=20000, events=True, pre=""):
    lua = L.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.SRC = SRC
    g.LIMIT = limit
    if pre: lua.execute(pre)
    g.SCENARIO = lua.eval('function(s) return load("return " .. s)() end')(scn)
    lua.execute(open(SRC + '/test/mock.lua', encoding='utf-8').read())
    if events:
        lua.execute('EVENTS = {}; for i = 2, SCENARIO.qty or 1 do EVENTS[#EVENTS+1] = {"key", keys.up} end; EVENTS[#EVENTS+1] = {"key", keys.enter}')
    res = lua.eval('''function(src)
      local ok, err = pcall(dofile, "boron.lua")
      return tostring(err)
    end''')(SRC)
    return lua, res
