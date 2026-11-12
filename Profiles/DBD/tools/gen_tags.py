"""Generates DBDMount/Config/Tags/DBDGameTags.ini, DBDHarvestedTags.ini and DBDMount/Config/DefaultGameplayTags.ini
from the jmap's Default__GameplayTagsSettings. GameplayTagList entries must NOT carry a '+' prefix (the engine's own
Config/Tags files list them as plain repeated keys; with '+' FConfigFile yields no array entries)."""
import json, os, glob, re
o = json.load(open(r'C:\Workspace\DeadByDaylight-Data\DBD-10.2.2.jmap'))['objects']
pv = o[[n for n in o if n.endswith('Default__GameplayTagsSettings')][0]]['property_values']
cfg = r'C:\Workspace\DBDMount\Config'
os.makedirs(cfg + r'\Tags', exist_ok=True)
NL = '\n'
def row(tag, comment=''):
    return 'GameplayTagList=(Tag="%s",DevComment="%s")' % (tag, comment.replace('"', "'")) + NL
with open(cfg + r'\Tags\DBDGameTags.ini', 'w', encoding='utf8') as f:
    f.write('[/Script/GameplayTags.GameplayTagsList]' + NL)
    for t in pv['GameplayTagList']:
        f.write(row(t['Tag'], t.get('DevComment', '')))
with open(cfg + r'\DefaultGameplayTags.ini', 'w', encoding='utf8') as f:
    f.write('[/Script/GameplayTags.GameplayTagsSettings]' + NL + 'ImportTagsFromConfig=True' + NL + 'WarnOnInvalidTags=True' + NL)
    for r in pv['GameplayTagRedirects']:
        f.write('+GameplayTagRedirects=(OldTagName="%s",NewTagName="%s")' % (r['OldTagName'], r['NewTagName']) + NL)
print(len(pv['GameplayTagList']), len(pv['GameplayTagRedirects']))
have = {t['Tag'] for t in pv['GameplayTagList']}
extra = set()
for fn in glob.glob(r'C:\Workspace\B_work\native_tests\*.log'):
    for l in open(fn, encoding='utf8', errors='ignore'):
        m = re.search(r'Invalid GameplayTag (\S+) found in property', l)
        if m and m.group(1) not in have:
            extra.add(m.group(1))
with open(cfg + r'\Tags\DBDHarvestedTags.ini', 'w', encoding='utf8') as f:
    f.write('[/Script/GameplayTags.GameplayTagsList]' + NL)
    for t in sorted(extra):
        f.write(row(t, 'harvested from load logs'))
print('harvested', len(extra))
