"""Генерирует recipes.lua для armorcraft: все рецепты цепочки arcon:hull_ceramic_snow из jar'ов сборки."""
import json, re, sys, zipfile

MODS = r'C:/Users/timur/Downloads/Instances/1231231/mods/'
JARS = [MODS + 'arcon-1.05-prerelease.jar', MODS + 'create-1.21.1-6.0.10.jar', MODS + 'cuftweaks-1.0.0.jar']
OUT = sys.argv[1]
TARGET = sys.argv[2] if len(sys.argv) > 2 else 'arcon:hull_boron_snow'

# тип рецепта -> станция ПК
STATION = {
    'create:crushing': 'crush', 'create:splashing': 'wash', 'create:mixing': 'mix',
    'create:compacting': 'compact', 'create:milling': 'mill', 'create:pressing': 'line', 'create:sequenced_assembly': 'line',
    'arcon:industrial_furnace': 'furnace',
}
TAGS = {
    'c:raw_materials/iron': ['minecraft:raw_iron'],
    'c:storage_blocks/raw_iron': ['minecraft:raw_iron_block'],
    'c:ingots/iron': ['minecraft:iron_ingot'],
}
SKIP = {
    # порошки делаются смешиванием с супернагревом в бассейне — ПК их не делает, только берёт со склада
    'arcon:mixing/manganese_powder', 'arcon:mixing/tungsten_powder',
    # круговой путь карбид -> порошок -> карбид
    'arcon:crushing/tungsten_carbide_powder', 'arcon:industrial_furnace/tungsten_carbide_from_powder',
    # переплавка повреждённой брони — вход задаётся тегом брони, не автоматизируем
    'arcon:industrial_furnace/recycle_damaged_armor',
    'create:crushing/iron_horse_armor',
}
VANILLA_RU = {
    'minecraft:iron_ingot': 'Железный слиток', 'minecraft:iron_nugget': 'Железный самородок',
    'minecraft:coal': 'Уголь', 'minecraft:charcoal': 'Древесный уголь', 'minecraft:raw_iron': 'Рудное железо',
    'minecraft:raw_iron_block': 'Блок рудного железа', 'minecraft:iron_ore': 'Железная руда',
    'minecraft:deepslate_iron_ore': 'Глубинная железная руда', 'minecraft:redstone': 'Редстоун',
    'minecraft:clay_ball': 'Комок глины', 'minecraft:sand': 'Песок', 'minecraft:obsidian': 'Обсидиан',
    'minecraft:crying_obsidian': 'Плачущий обсидиан', 'minecraft:magma_block': 'Магмовый блок', 'minecraft:amethyst_shard': 'Осколок аметиста',
    'minecraft:cobblestone': 'Булыжник', 'minecraft:coal_ore': 'Угольная руда',
    'minecraft:deepslate_coal_ore': 'Глубинная угольная руда', 'minecraft:cobbled_deepslate': 'Глубинный булыжник',
}

recipes, ru = {}, dict(VANILLA_RU)
for jar in JARS:
    z = zipfile.ZipFile(jar)
    for n in z.namelist():
        m = re.match(r'data/(\w+)/recipe/(.+)\.json$', n)
        if m:
            try:
                d = json.loads(z.read(n))
            except Exception:
                continue
            if d.get('type') in STATION and 'neoforge:conditions' not in d:
                recipes[m.group(1) + ':' + m.group(2)] = d
        m = re.match(r'assets/(\w+)/lang/ru_ru\.json$', n)
        if m:
            for k, v in json.loads(z.read(n)).items():
                km = re.match(r'(?:item|block)\.(\w+)\.(\w+)$', k)
                if km:
                    ru.setdefault(km.group(1) + ':' + km.group(2), v)

def is_fluid(x):
    return isinstance(x, dict) and 'fluid' in x

def ing(x):
    """ингредиент -> список подходящих предметов"""
    if isinstance(x, list):
        return [i for y in x for i in ing(y)]
    if 'item' in x:
        return [x['item']]
    if 'tag' in x:
        if x['tag'] not in TAGS:
            raise KeyError(x['tag'])
        return TAGS[x['tag']]
    raise KeyError(json.dumps(x)[:60])

def res(r):
    return {'item': r.get('id') or r['item'], 'n': r.get('count', 1), 'chance': r.get('chance', 1)}

by_out = {}
for rid, d in recipes.items():
    if rid in SKIP:
        continue
    for r in d.get('results', []):
        if isinstance(r, dict) and isinstance(r.get('id') or r.get('item'), str):
            by_out.setdefault(res(r)['item'], []).append(rid)

used, order, items = set(), [], set()
# простые ванильные вещи берём готовыми, их цепочки (жернова, гравий...) не тянем
LEAVES = {'minecraft:sand', 'minecraft:clay_ball'}
def walk(item):
    if item in items:
        return
    items.add(item)
    if item in LEAVES:
        return
    for rid in by_out.get(item, []):
        if 'recoloring' in rid:
            continue
        d = recipes[rid]
        if res(d['results'][0])['item'] != item or res(d['results'][0])['chance'] < 1:
            continue  # item лишь побочный / случайный выход
        try:
            if d['type'] == 'create:sequenced_assembly':
                subs = ing(d['ingredient'])
                for st in d['sequence']:
                    for x in st.get('ingredients', [])[1:]:
                        subs += ing(x)
            else:
                subs = [i for x in d.get('ingredients', []) if not is_fluid(x) for i in ing(x)]
        except KeyError as e:
            print('пропущен', rid, '(тег', e, ')')
            continue
        if rid not in used:
            used.add(rid); order.append(rid)
        for s in subs:
            walk(s)
walk(TARGET)

TR = dict(zip('абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
              ['a','b','v','g','d','e','yo','zh','z','i','y','k','l','m','n','o','p','r','s','t','u','f','h','c','ch',
               'sh','sch','','y','','e','yu','ya']))
def translit(t):
    # мониторы CC не умеют кириллицу — пишем латиницей
    out = ''
    for ch in t:
        lo = ch.lower()
        if lo in TR:
            r = TR[lo]
            out += r.capitalize() if ch != lo else r
        else:
            out += ch
    return out

def lua(v):
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, list):
        return '{' + ', '.join(lua(x) for x in v) + '}'
    return '{' + ', '.join(f'{k} = {lua(x)}' for k, x in v.items()) + '}'

out = ['-- СГЕНЕРИРОВАНО gen.py из jar\'ов сборки (arcon 1.05, Create 6.0.10). Руками не править.',
       'local R = {}', f'R.target = "{TARGET}"', 'R.list = {']
for rid in order:
    d = recipes[rid]
    r = {'id': rid, 'station': STATION[d['type']]}
    if d['type'] == 'create:sequenced_assembly':
        r['base'] = ing(d['ingredient'])
        r['loops'] = d.get('loops', 1)
        r['transitional'] = d['transitional_item'].get('id') or d['transitional_item']['item']
        r['deploy'] = []
        for st in d['sequence']:
            if st['type'] == 'create:deploying':
                r['deploy'].append(ing(st['ingredients'][1]))
        r['steps'] = [st['type'].split(':')[1] for st in d['sequence']]
    else:
        r['ins'] = [ing(x) for x in d.get('ingredients', []) if not is_fluid(x)]
        fl = [{'fluid': x['fluid'], 'amount': x.get('amount', 1000)} for x in d.get('ingredients', []) if is_fluid(x)]
        if fl:
            r['fluids'] = fl
    r['outs'] = [res(x) for x in d['results']]
    if d.get('heat_requirement'):
        r['heat'] = d['heat_requirement']
    out.append('  ' + lua(r) + ',')
out.append('}')
names = sorted(items | {o['item'] for rid in order for o in (res(x) for x in recipes[rid]['results'])})
out.append('R.ru = {')
for i in names:
    out.append(f'  ["{i}"] = {lua(translit(ru.get(i, i)))},')
out.append('}')
out.append('return R')
open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
print(len(order), 'рецептов,', len(names), 'предметов')
for i in names:
    if i not in ru:
        print('нет перевода:', i)
