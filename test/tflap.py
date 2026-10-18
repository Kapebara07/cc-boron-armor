import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=28, ["minecraft:raw_iron"]=5, ["minecraft:iron_nugget"]=5, ["minecraft:coal"]=33,
 ["arcon:borate_ore"]=16, ["arcon:raw_nickel"]=4, ["arcon:raw_chromium"]=4, ["arcon:raw_manganese"]=4,
 ["minecraft:clay_ball"]=4, ["minecraft:sand"]=4, ["minecraft:obsidian"]=4'''
flap = 'FLAP = {["create:crushing_wheel_controller_0"]=true, ["create:depot_1"]=true, ["create:belt_0"]=true, ["create:basin_0"]=true}'
# экран статичен (нет ресурсов): сколько раз меняется монитор слева за 120 сек при «моргающих» машинах
lua, res = run('{qty=1, raw={}}', limit=120, events=False, pre=flap)
print('static screen, frames in 120 s:', lua.eval('FRAMES'))
print('\n'.join(l for l in lua.eval('LEFTMON.dump()').split('\n') if 'NO ]' in l))
# производство с моргающими машинами
lua, res = run('{qty=1, raw={' + BASE + '}}', limit=30000, events=False, pre=flap)
print('FLAP RUN', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'))
