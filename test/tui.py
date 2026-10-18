import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=56, ["minecraft:raw_iron"]=10, ["minecraft:iron_nugget"]=10, ["minecraft:coal"]=66,
 ["arcon:borate_ore"]=32, ["arcon:raw_nickel"]=8, ["arcon:raw_chromium"]=8, ["arcon:raw_manganese"]=8,
 ["minecraft:clay_ball"]=8, ["minecraft:sand"]=8, ["minecraft:obsidian"]=8'''
ev = '''{ {"dump"},
 {"tap","SELECT","RAW"}, {"dump"}, {"tap","chest_0"}, {"tap","DONE"},
 {"tap","SELECT","STOCK"}, {"tap","chest_1"}, {"tap","DONE"},
 {"tap","SELECT","ARMOR OUT"}, {"tap","chest_2"}, {"tap","DONE"},
 {"tap","SELECT","BYPRODUCTS"}, {"tap","chest_3"}, {"tap","DONE"},
 {"tap","AUTO","basin_1"}, {"tap","AUTO","basin_0"}, {"tap","MIXER","basin_0"},
 {"dump"}, {"tap","DETAILS"}, {"dump"}, {"tap","BACK"},
 {"tap","START SYSTEM"}, {"tap","+1"}, {"tap","CHECK","MENU"}, {"dump"}, {"tap","START","MENU"} }'''
lua, res = run('{qty=2, fresh=true, raw={' + BASE + '}}', limit=60000, events=ev)
for i in range(1, 6):
    d = lua.eval('DUMPS[%d]' % i)
    if d: print('------ screen', i); print('\n'.join(l for l in d.split('\n') if l.strip()))
print('RES', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'))
print('------ final'); print('\n'.join(l for l in lua.eval('SCREEN()').split('\n') if l.strip()))
print('cfg:', lua.eval('FILES and FILES["armor.cfg"]'))
print('------ term (51x19) final'); print(lua.eval('term.dump()'))
