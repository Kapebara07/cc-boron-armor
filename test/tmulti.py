import sys
sys.path.insert(0, '.')
from run import run
BASE = '''["minecraft:iron_ingot"]=56, ["minecraft:raw_iron"]=10, ["minecraft:iron_nugget"]=10, ["minecraft:coal"]=66,
 ["arcon:borate_ore"]=32, ["arcon:raw_nickel"]=8, ["arcon:raw_chromium"]=8, ["arcon:raw_manganese"]=8,
 ["minecraft:clay_ball"]=8, ["minecraft:sand"]=8, ["minecraft:obsidian"]=8'''
# 1) две линии без назначения -> вторая лента без развёртывателей; назначаем через меню
ev = '''{ {"tap","STOP"}, {"tap","< MENU"}, {"tap","DEP","belt_1"}, {"dump"}, {"tap","deployer_2"}, {"tap","deployer_3"}, {"tap","DONE"}, {"tap","DEP","belt_0"}, {"tap","deployer_0"}, {"tap","deployer_1"}, {"tap","DONE"}, {"dump"}, {"tap","START SYSTEM"}, {"tap","START","MENU"} }'''
lua, res = run('{qty=2, raw={' + BASE + '}}', limit=60000, events=ev, pre='MULTI = true')
for i in (1, 2):
    d = lua.eval('DUMPS[%d]' % i)
    if d: print('------ screen', i); print('\n'.join(l for l in d.split('\n') if l.strip()))
print('MULTI RES', res, 'T', lua.eval('TIME()'), '| out:', lua.eval('DUMP("minecraft:chest_2")'))
print('used:', lua.eval('(function() local t={} for k,v in pairs(USED) do t[#t+1]=k.."="..v end table.sort(t) return table.concat(t,", ") end)()'))
print('stock:', lua.eval('DUMP("minecraft:chest_1")'))
for n in ['create:deployer_0','create:deployer_1','create:deployer_2','create:deployer_3','minecraft:dropper_0','minecraft:dropper_1']:
    print(' ', n, lua.eval('DUMP("%s")' % n))
log = lua.eval('GETLOG()')
if log: print('LOG', log[-800:])
