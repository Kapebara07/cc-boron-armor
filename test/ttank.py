import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=28, ["minecraft:raw_iron"]=5, ["minecraft:iron_nugget"]=5, ["minecraft:coal"]=33,
 ["arcon:borate_ore"]=16, ["arcon:raw_nickel"]=4, ["arcon:raw_chromium"]=4, ["arcon:raw_manganese"]=4,
 ["minecraft:clay_ball"]=4, ["minecraft:sand"]=4, ["minecraft:obsidian"]=4'''
# A) вода только в баке (трубы нет), ровно 1000 мБ
lua, res = run('{qty=1, raw={' + BASE + '}}', limit=30000, events=False, pre='NO_WATER = true; TANK = 1000')
print('TANK-1000', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'), '| tank left:', lua.eval('TANKW'))
# B) в баке 500 мБ -> не хватает воды
lua, res = run('{qty=1, raw={' + BASE + '}}', limit=15, events=False, pre='NO_WATER = true; TANK = 500')
print('\n'.join(l for l in lua.eval('SCREEN()').split('\n')[:6] if l.strip()))
print('\n'.join(l for l in lua.eval('LEFTMON.dump()').split('\n') if 'Water' in l or 'tank' in l))
