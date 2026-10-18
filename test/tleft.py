import sys
sys.path.insert(0, '.')
from run import run
# 1) свежая установка: склады не выбраны
lua, res = run('{qty=1, fresh=true, raw={}}', limit=2, events=False)
print('--- fresh'); print('\n'.join(l for l in lua.eval('LEFTMON.dump()').split('\n') if l.strip()))
# 2) всё настроено, нет воды, один развёртыватель убран
lua, res = run('{qty=1, raw={}}', limit=2, events=False, pre='NO_WATER = true; NO_DEPLOYER1 = true; LEFT_W = 36; LEFT_H = 40')
print('--- configured, 36x24'); print(lua.eval('LEFTMON.dump()'))
