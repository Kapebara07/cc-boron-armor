import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=28, ["minecraft:raw_iron"]=5, ["minecraft:iron_nugget"]=5, ["minecraft:coal"]=33,
 ["arcon:borate_ore"]=16, ["arcon:raw_nickel"]=4, ["arcon:raw_chromium"]=4, ["arcon:raw_manganese"]=4,
 ["minecraft:clay_ball"]=4, ["minecraft:sand"]=4, ["minecraft:obsidian"]=4'''
def show(lua, res, tag):
    print(tag, res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'))
    print('   raw:', lua.eval('DUMP("minecraft:chest_0")'))
    print('   stock:', lua.eval('DUMP("minecraft:chest_1")'))
    log = lua.eval('GETLOG()')
    if log: print('   LOG:', log[-600:])
# 1) пустой склад -> список нехватки
lua, res = run('{qty=1, raw={}}', limit=3, events=False)
print('\n'.join(lua.eval('SCREEN()').split('\n')[:16]))
# 2) ровно минимум из исходных предметов, авторежим без нажатий
lua, res = run('{qty=1, raw={' + BASE + '}}', limit=30000, events=False)
show(lua, res, 'MIN-AUTO')
if res != 'DONE': print(lua.eval('SCREEN()'))
# 3) заказ на 2 брони (ручной), с заменами: глубинная руда, древесный уголь, плачущий обсидиан
scn = '''{qty=2, raw={["minecraft:iron_ingot"]=56, ["minecraft:deepslate_iron_ore"]=5, ["minecraft:iron_nugget"]=10,
 ["minecraft:charcoal"]=66, ["arcon:borate_ore"]=32, ["arcon:deepslate_nickel_ore"]=4, ["arcon:chromite_ore"]=8,
 ["arcon:deepslate_manganese_ore"]=4, ["minecraft:clay_ball"]=8, ["minecraft:sand"]=8, ["minecraft:crying_obsidian"]=8}}'''
lua, res = run(scn, limit=60000)
show(lua, res, 'TWO-ALT')
# 4) готовые промежуточные на складе
scn = '''{qty=1, stock={["arcon:coke_dust"]=33, ["arcon:boron_powder"]=16, ["arcon:refractory_compound"]=4, ["arcon:nickel_ingot"]=4},
 raw={["minecraft:iron_ingot"]=28, ["minecraft:raw_iron"]=5, ["minecraft:iron_nugget"]=5,
 ["arcon:raw_chromium"]=4, ["arcon:raw_manganese"]=4}}'''
lua, res = run(scn, limit=30000, events=False)
show(lua, res, 'INTERMED')
# 5) нет воды
lua, res = run('{qty=1, raw={' + BASE + '}}', limit=3, events=False, pre='NO_WATER = true')
print('\n'.join(lua.eval('SCREEN()').split('\n')[:6]))
