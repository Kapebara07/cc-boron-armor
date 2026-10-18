import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=56, ["minecraft:raw_iron"]=10, ["minecraft:iron_nugget"]=10, ["minecraft:coal"]=66,
 ["arcon:borate_ore"]=32, ["arcon:raw_nickel"]=8, ["arcon:raw_chromium"]=8, ["arcon:raw_manganese"]=8,
 ["minecraft:clay_ball"]=8, ["minecraft:sand"]=8, ["minecraft:obsidian"]=8'''
LINES = '''lines = {["create:belt_0"] = {"create:deployer_0", "create:deployer_1"}, ["create:belt_1"] = {"create:deployer_2", "create:deployer_3"}}'''
# 1) выделенные линии: belt_0 = корпус + броня, belt_1 = листы + броневые плиты + борные плиты
JOBS = '''lineJobs = {["create:belt_0"] = {["arcon:sequenced_assembly/structural_steel_casing"] = true, ["arcon:sequenced_assembly/hull_boron_snow"] = true},
 ["create:belt_1"] = {["create:pressing/iron_ingot"] = true, ["arcon:sequenced_assembly/armor_steel_plate"] = true, ["arcon:sequenced_assembly/boron_composite_armor_plate"] = true}}'''
lua, res = run('{qty=2, ' + LINES + ', ' + JOBS + ', raw={' + BASE + '}}', limit=60000, events=False, pre='MULTI = true')
print('DEDICATED', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'), '| passes b0/b1:', lua.eval('USED["create:belt_0"]'), lua.eval('USED["create:belt_1"]'))
# 2) никто не делает железные листы -> понятная нехватка линии
JOBS2 = '''lineJobs = {["create:belt_0"] = {["arcon:sequenced_assembly/structural_steel_casing"] = true, ["arcon:sequenced_assembly/hull_boron_snow"] = true},
 ["create:belt_1"] = {["arcon:sequenced_assembly/armor_steel_plate"] = true, ["arcon:sequenced_assembly/boron_composite_armor_plate"] = true}}'''
lua, res = run('{qty=1, ' + LINES + ', ' + JOBS2 + ', raw={' + BASE + '}}', limit=15, events=False, pre='MULTI = true')
print('\n'.join(l for l in lua.eval('SCREEN()').split('\n')[:4] if l.strip()))
print('\n'.join(l for l in lua.eval('LEFTMON.dump()').split('\n') if 'Line' in l or 'menu' in l))
# 3) меню: экран JOBS
ev = '''{ {"tap","STOP"}, {"tap","< MENU"}, {"dump"}, {"tap","JOBS","belt_1"}, {"tap","Iron Sheet"}, {"dump"}, {"tap","DONE"}, {"dump"} }'''
lua, res = run('{qty=1, ' + LINES + ', raw={' + BASE + '}}', limit=40, events=ev, pre='MULTI = true')
for i in (1, 2, 3):
    d = lua.eval('DUMPS[%d]' % i)
    if d: print('------ screen', i); print('\n'.join(l for l in d.split('\n') if l.strip()))
