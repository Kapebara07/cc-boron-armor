import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=28, ["minecraft:raw_iron"]=5, ["minecraft:iron_nugget"]=5, ["minecraft:coal"]=33,
 ["arcon:borate_ore"]=16, ["arcon:raw_nickel"]=4, ["arcon:raw_chromium"]=4, ["arcon:raw_manganese"]=4,
 ["minecraft:clay_ball"]=4, ["minecraft:sand"]=4, ["minecraft:obsidian"]=4'''
# 1) развёртыватели в обратном порядке (пустой держит ленту, как в Create)
lua, res = run('{qty=1, raw={' + BASE + '}}', limit=30000, events=False, pre='SWAP_DEPLOYERS = true')
print('SWAPPED', res, 'T', lua.eval('TIME()'), lua.eval('DUMP("minecraft:chest_2")'), '| held:', lua.eval('HELD'),
      '| deployers:', lua.eval('DUMP("create:deployer_0")'), '/', lua.eval('DUMP("create:deployer_1")'))
# 2) всё уже переработано, дробить нечего -> нет ни опыта, ни булыжника для заглушки
INTER = '''["minecraft:iron_ingot"]=28, ["arcon:iron_powder"]=5, ["arcon:recarburizer"]=5, ["arcon:coke_dust"]=28,
 ["arcon:boron_powder"]=16, ["arcon:nickel_ingot"]=4, ["arcon:ferrochrome"]=4, ["arcon:ferromanganese"]=4,
 ["arcon:refractory_compound"]=4'''
lua, res = run('{qty=1, stock={' + INTER + '}}', limit=400, events=False)
print('NO JUNK', res, '| out:', lua.eval('DUMP("minecraft:chest_2")'))
print('\n'.join(l for l in lua.eval('SCREEN()').split('\n') if 'filler' in l))
print('\n'.join(l for l in lua.eval('LEFTMON.dump()').split('\n') if 'filler' in l.lower() or 'junk' in l))
# 3) то же + 2 булыжника в сырье
lua, res = run('{qty=1, stock={' + INTER + '}, raw={["minecraft:cobblestone"]=2}}', limit=30000, events=False)
print('WITH COBBLE', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'), '| raw left:', lua.eval('DUMP("minecraft:chest_0")'), '| waste:', lua.eval('DUMP("minecraft:chest_3")'))
