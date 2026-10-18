import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=28, ["minecraft:raw_iron"]=5, ["minecraft:iron_nugget"]=5, ["minecraft:coal"]=33,
 ["arcon:borate_ore"]=16, ["arcon:raw_nickel"]=4, ["arcon:raw_chromium"]=4, ["arcon:raw_manganese"]=4,
 ["minecraft:clay_ball"]=4, ["minecraft:sand"]=4, ["minecraft:obsidian"]=4'''
# 1) депо под прессом + лента только для сборок с развёртывателями
JOBS = '''lineJobs = {["create:belt_0"] = {["arcon:sequenced_assembly/structural_steel_casing"] = true,
 ["arcon:sequenced_assembly/boron_composite_armor_plate"] = true, ["arcon:sequenced_assembly/hull_boron_snow"] = true}}'''
lua, res = run('{qty=1, depots = {["create:depot_2"] = "press"}, ' + JOBS + ', raw={' + BASE + '}}', limit=30000, events=False, pre='PDEP = true')
print('PRESS DEPOT', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'),
      '| presses on depot:', lua.eval('USED["create:depot_2"]'), '| belt passes:', lua.eval('USED["create:belt_0"]'),
      '| wash depots used:', lua.eval('DUMP("create:depot_0")'), lua.eval('DUMP("create:depot_1")'))
print('\n'.join(l for l in lua.eval('LEFTMON.dump()').split('\n') if 'Press' in l or 'depot_2' in l))
# 2) меню: переключатель WASH/PRESS
ev = '''{ {"tap","STOP"}, {"tap","< MENU"}, {"tap","WASH","depot_2"}, {"tap","PRESS","depot_2"}, {"tap","WASH","depot_2"}, {"tap","REFRESH"}, {"tap","REFRESH"}, {"dump"} }'''
lua, res = run('{qty=1, raw={}}', limit=40, events=ev, pre='PDEP = true')
d = lua.eval('DUMPS[1]')
print('\n'.join(l for l in d.split('\n') if 'depot' in l.lower()))
