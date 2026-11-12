#!/usr/bin/env python3
"""DBD native type baker (milestone M0).

Reads the game's jmap (reflection dump of the shipping process) and writes a compact, deterministic JSON file with every
class / struct / enum that the stock 5.7.4 editor does NOT contain, plus a table of the editor classes whose layout differs
from the game. A later editor plugin generates the UClasses/UScriptStructs/UEnums from it at startup.

Examples
  python dbd_native_baker.py                                   # everything -> data/dbd_native_types.json (+ diffs table)
  python dbd_native_baker.py --roots @data/roots_17_failing.txt --out data/closure_17assets.json
  python dbd_native_baker.py --roots WBP_native_roots --all-refs --out ...   (follow object/class references too)
  python dbd_native_baker.py --roots /Script/DBDUIViewsCore.CorePlayerCardAnimationWidget,/Script/DBDUIViewsCore.DBDImage
Options: --no-interfaces (do not follow interface classes), --no-functions, --cdo-out FILE (CDO default deltas),
         --enum-mode package|source, --validate (cross-check against the usmap, writes data/validation_report.json).
The output has no timestamps: identical inputs give byte-identical output.
"""
import argparse, collections, hashlib, importlib.util, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, 'data')
FORMAT_VERSION = 1


def _load(name):
    sp = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + '.py'))
    m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m


FL = _load('ue_flags')

THIRD_PARTY = re.compile(r'^(AkAudio|Wwise\w*|Houdini\w*|Simplygon\w*|Substance\w*|Sentry\w*|XeSS\w*|Scaleform\w*)$', re.I)
# CPF flags that UProperty creation derives on its own (advisory for the plugin, see legend)
DERIVED_CPF = ('CPF_ZeroConstructor', 'CPF_IsPlainOldData', 'CPF_NoDestructor', 'CPF_HasGetValueTypeHash',
               'CPF_UObjectWrapper', 'CPF_TObjectPtr', 'CPF_ContainsInstancedReference')
CLASS_STRIP = ('CLASS_Native', 'CLASS_Intrinsic', 'CLASS_Constructed', 'CLASS_TokenStreamAssembled', 'CLASS_MatchedSerializers')
LEGEND = {
    'file': 'dbd_native_types', 'format': FORMAT_VERSION,
    'hex': 'all flag fields are hex strings ("0x...") because flags exceed 2^53 (JSON doubles); function flags are plain ints',
    'class': {'p': 'path', 'sup': 'super class path', 'fl': 'class flags (raw from the game)', 'sz': 'properties_size in the game',
              'cast': 'class cast flags names (only if non-empty)', 'within': 'ClassWithin if not Object', 'cdo': 'CDO path',
              'if': 'interfaces [{c: class, o: pointer offset, k2: implemented by K2}]', 'pr': 'properties in game order',
              'fn': 'functions in jmap order', 'so': 'default subobjects [{n, c, fl, outer?}]', 'g': 'group', 'ur': 'unresolved refs'},
    'struct': {'p': 'path', 'sup': 'super', 'fl': 'struct flags', 'sz': 'size', 'al': 'min alignment', 'pr': 'properties', 'sn': '1=SerializeNative', 'at': '1=Atomic', 'g': 'group'},
    'enum': {'p': 'path', 'n': '[[name, value]] as in the game (not prefixed)', 'cpp': 'EnumClass|Regular|Namespaced', 'ct': 'cpp type', 'fl': 'enum flags names', 'g': 'group'},
    'prop': {'n': 'name', 't': 'jmap property type (ObjectProperty, ClassProperty, ...)', 'f': 'CPF flags', 'o': 'offset in game', 's': 'size in game',
             'd': 'array dim if > 1', 'cls': 'property_class (Object/WeakObject/SoftObject/LazyObject/Class/SoftClass)', 'meta': 'meta_class (Class, SoftClass)',
             'st': 'struct path', 'en': 'enum path (ByteProperty/EnumProperty)', 'u': 'EnumProperty underlying property type', 'ic': 'interface class',
             'sg': 'delegate signature function path', 'in': 'inner (Array, Set, Optional)', 'key': 'Map key', 'val': 'Map value',
             'b': 'bool: {fs: field size, bo: byte offset, bm: byte mask, fm: field mask, nat: 1 = native bool}'},
    'func': {'n': 'name', 'k': 'F=function D=delegate S=sparse delegate', 'f': 'FUNC flags (int)', 'pr': 'params in order (CPF_Parm, OutParm, ReturnParm in f)', 'sz': 'params size', 'sup': 'super function if any'},
    'groups': {'game': 'game and character/event modules', 'thirdparty': 'Wwise, Houdini, Simplygon, Substance, Sentry, XeSS, Scaleform',
               'stock_unloaded': 'stock UE module that has a Build.cs in the 5.7.4 tree but is not loaded in the editor: prefer enabling the plugin'},
    'order': 'enums, structs (super and struct members first), classes (super first): safe creation order',
}


def hx(v): return '0x%X' % v


def mask_of(table, names):
    return sum(table[n] for n in names)


def flags_to_int(s, table, bad):
    v = 0
    if not s: return 0
    for tok in s.split(' | '):
        tok = tok.strip()
        if tok in table: v |= table[tok]
        elif tok.startswith('0x'): v |= int(tok, 16)
        else: bad[tok] += 1
    return v


class Baker:
    def __init__(self, a):
        self.a = a
        j = json.load(open(a.jmap, encoding='utf8'))
        self.meta = j['metadata']; self.o = j['objects']; del j
        self.bad_flags = collections.Counter()
        self.notes = collections.Counter()
        self.load_editor()
        self.classify()

    # ---- what the editor already has -------------------------------------------------------------------------------
    def load_editor(self):
        a = self.a
        self.ed = set(); self.ed_pk = set(); self.ES = {}; self.EP = collections.defaultdict(list)
        short_count = collections.Counter()
        for l in open(a.editor_schemas, encoding='utf8'):
            p = l.rstrip('\r\n').split('\t')
            if p[0] == 'S':
                self.ed.add(p[3] + '.' + p[1]); self.ed_pk.add(p[3]); self.ES[p[1]] = p; short_count[p[1]] += 1
            elif p[0] == 'P': self.EP[p[1]].append((int(p[2]), p[3], p[4], p[5] == '1', p[6] == '1', int(p[7])))
        self.ed_short_dups = {k for k, c in short_count.items() if c > 1}
        fa = json.load(open(os.path.join(DATA, 'fork_additions.json'))) if os.path.exists(os.path.join(DATA, 'fork_additions.json')) else {'types': [], 'members': {}}
        self.fork_types = {t[1:] if len(t) > 1 and t[0] in 'UAFE' and t[1].isupper() else t for t in fa['types']} | set(fa['types'])
        self.fork_members = fa['members']
        self.fork_all_members = set().union(*[set(v) for v in fa['members'].values()]) if fa['members'] else set()
        # fork-added types are present now (stubs added by hand); match by short name inside engine packages
        self.hand_added = set()
        for n, v in self.o.items():
            if v['type'] in ('Class', 'ScriptStruct', 'Enum') and n.split('.')[-1] in self.fork_types: self.hand_added.add(n)
        si = os.path.join(DATA, 'stock_info.json')
        self.stock = json.load(open(si)) if os.path.exists(si) else {'enums': [], 'modules': {}}
        self.stock_enums = set(self.stock['enums']); self.stock_modules = set(self.stock['modules'])

    def classify(self):
        o = self.o
        self.missing = {'Class': set(), 'ScriptStruct': set(), 'Enum': set()}
        self.suspect_enums = []
        for n, v in o.items():
            t = v['type']
            if t in ('Class', 'ScriptStruct'):
                if n not in self.ed and n not in self.hand_added: self.missing[t].add(n)
            elif t == 'Enum':
                pk = n.rsplit('.', 1)[0]
                if n in self.hand_added: continue
                if pk not in self.ed_pk: self.missing['Enum'].add(n)
                elif self.stock_enums and n.split('.')[-1] not in self.stock_enums:
                    self.suspect_enums.append(n)
                    if self.a.enum_mode == 'source': self.missing['Enum'].add(n)

    def group(self, path):
        mod = path.split('.')[0].split('/')[-1]
        if THIRD_PARTY.match(mod): return 'thirdparty'
        if mod in self.stock_modules: return 'stock_unloaded'
        return 'game'

    def is_missing(self, n):
        v = self.o.get(n)
        return bool(v) and n in self.missing.get(v['type'], ())

    # ---- reference walking ------------------------------------------------------------------------------------------
    def refs(self, p, hard, soft, sigs):
        for k in ('struct', 'enum'):
            if p.get(k): hard.add(p[k])
        for k in ('property_class', 'meta_class', 'interface_class'):
            if p.get(k): soft.add(p[k])
        if p.get('signature_function'): sigs.add(p['signature_function'])
        for k in ('inner', 'key_prop', 'value_prop', 'container'):
            if k in p and p[k]: self.refs(p[k], hard, soft, sigs)

    def closure(self, roots, all_refs, interfaces):
        o = self.o
        seen = set(); sigs_seen = set(); stack = list(roots); unresolved_roots = []
        while stack:
            n = stack.pop(); v = o.get(n)
            if n in seen or not v: continue
            if v['type'] == 'Function':
                if n in sigs_seen: continue
                sigs_seen.add(n)
                hard, soft, sigs = set(), set(), set()
                for p in v['properties']: self.refs(p, hard, soft, sigs)
                stack.extend(hard)
                if all_refs: stack.extend(soft); stack.extend(sigs)
                continue
            if v['type'] not in ('Class', 'ScriptStruct', 'Enum') or not self.is_missing(n): continue
            seen.add(n)
            hard, soft, sigs = set(), set(), set()
            if v.get('super_struct'): hard.add(v['super_struct'])
            if v['type'] == 'Class' and interfaces:
                for i in v['interfaces']: hard.add(i['class'])
            for p in v.get('properties') or []: self.refs(p, hard, soft, sigs)
            stack.extend(hard)
            if all_refs:
                stack.extend(soft); stack.extend(sigs)
                if v['type'] == 'Class':  # default subobject classes
                    cdo = v.get('class_default_object')
                    for so in self.subs.get(cdo, ()): stack.append(o[so]['class'])
        return seen, sigs_seen

    def build_indexes(self):
        o = self.o
        self.subs = collections.defaultdict(list)
        for n, v in o.items():
            if v['type'] == 'Object' and v['outer'] in o and o[v['outer']]['type'] == 'Object': self.subs[v['outer']].append(n)
        self.pkg_funcs = collections.defaultdict(list)

    # ---- encoding -----------------------------------------------------------------------------------------------------
    def enc_prop(self, p, with_layout=True):
        r = {'n': p['name'], 't': p['type'], 'f': hx(flags_to_int(p['flags'], FL.CPF, self.bad_flags))}
        if with_layout: r['o'] = p['offset']; r['s'] = p['size']
        if p['array_dim'] != 1: r['d'] = p['array_dim']
        t = p['type']
        if p.get('property_class') and t not in ('ClassProperty', 'SoftClassProperty'): r['cls'] = p['property_class']
        if p.get('meta_class'): r['meta'] = p['meta_class']
        if p.get('struct'): r['st'] = p['struct']
        if p.get('enum'): r['en'] = p['enum']
        if t == 'EnumProperty' and p.get('container'): r['u'] = p['container']['type']
        if p.get('interface_class'): r['ic'] = p['interface_class']
        if p.get('signature_function'): r['sg'] = p['signature_function']
        if t == 'BoolProperty':
            r['b'] = {'fs': p['field_size'], 'bo': p['byte_offset'], 'bm': p['byte_mask'], 'fm': p['field_mask'],
                      'nat': 1 if p['field_mask'] == 255 and p['byte_mask'] == 1 else 0}
        if 'inner' in p and p['inner'] is not None: r['in'] = self.enc_prop(p['inner'], False)
        if 'key_prop' in p and p['key_prop'] is not None: r['key'] = self.enc_prop(p['key_prop'], False)
        if 'value_prop' in p and p['value_prop'] is not None: r['val'] = self.enc_prop(p['value_prop'], False)
        return r

    def enc_func(self, n, v):
        kind = {'/Script/CoreUObject.Function': 'F', '/Script/CoreUObject.DelegateFunction': 'D', '/Script/CoreUObject.SparseDelegateFunction': 'S'}.get(v['class'])
        if kind is None: kind = '?'; self.notes['unknown function class ' + v['class']] += 1
        r = {'n': n.split(':')[-1] if ':' in n else n.split('.')[-1], 'k': kind, 'f': flags_to_int(v['function_flags'], FL.FUNC, self.bad_flags)}
        if v.get('super_struct'): r['sup'] = v['super_struct']
        r['sz'] = v['properties_size']
        r['pr'] = [self.enc_prop(p) for p in v['properties']]
        return r

    def prop_refs(self, props):
        h, s, g = set(), set(), set()
        for p in props: self.refs(p, h, s, g)
        return h, s, g

    def enc_class(self, n, v, with_functions):
        o = self.o
        r = {'p': n, 'sup': v['super_struct'], 'fl': hx(flags_to_int(v['class_flags'], FL.CLASS, self.bad_flags)), 'sz': v['properties_size']}
        if v['class_cast_flags']: r['cast'] = v['class_cast_flags']
        w = v['property_values'].get('ClassWithin')
        if w and w != '/Script/CoreUObject.Object': r['within'] = w
        r['cdo'] = v['class_default_object']
        if v['interfaces']: r['if'] = [{'c': i['class'], 'o': i['pointer_offset'], 'k2': 1 if i['implemented_by_k2'] else 0} for i in v['interfaces']]
        r['pr'] = [self.enc_prop(p) for p in v['properties']]
        if with_functions:
            fns = [c for c in v['children'] if c in o and o[c]['type'] == 'Function']
            if fns: r['fn'] = [self.enc_func(c, o[c]) for c in fns]
        so = []
        cdo = v['class_default_object']
        prefix = cdo + ':'
        for s in self.subs.get(cdo, ()):  # direct children of the CDO; nested ones keep their relative path
            so.append(self.enc_sub(s, prefix))
            for s2 in self.subs.get(s, ()): so.append(self.enc_sub(s2, prefix))
        if so: r['so'] = so
        r['g'] = self.group(n)
        return r

    def enc_sub(self, s, prefix):
        v = self.o[s]
        r = {'n': s[len(prefix):] if s.startswith(prefix) else s, 'c': v['class'], 'fl': v['object_flags'].replace('RF_', '').replace(' | ', '|')}
        if v['outer'] != prefix[:-1] and v['outer'].startswith(prefix): r['outer'] = v['outer'][len(prefix):]
        return r

    def enc_struct(self, n, v):
        sf = flags_to_int(v['struct_flags'], FL.STRUCT, self.bad_flags)
        r = {'p': n, 'sup': v['super_struct'], 'fl': hx(sf), 'sz': v['properties_size'], 'al': v['min_alignment'] & 0xFFFF}
        if sf & FL.STRUCT['STRUCT_SerializeNative']: r['sn'] = 1
        if sf & FL.STRUCT['STRUCT_Atomic']: r['at'] = 1
        r['pr'] = [self.enc_prop(p) for p in v['properties']]
        r['g'] = self.group(n)
        return r

    def enc_enum(self, n, v):
        vals = []
        for name, val in v['names']:
            if abs(val) >= 2 ** 53: self.notes['enum value above 2^53'] += 1; val = str(val)
            vals.append([name, val])
        r = {'p': n, 'n': vals, 'cpp': v['cpp_form'], 'ct': v['cpp_type']}
        if v['enum_flags']: r['fl'] = v['enum_flags']
        r['g'] = self.group(n)
        return r

    # ---- ordering -----------------------------------------------------------------------------------------------------
    def topo(self, paths, deps):
        out, state = [], {}
        def visit(n):
            st = state.get(n)
            if st == 2: return
            if st == 1: self.notes['dependency cycle at ' + n] += 1; return
            state[n] = 1
            for d in sorted(deps(n)):
                if d in paths: visit(d)
            state[n] = 2; out.append(n)
        for n in sorted(paths): visit(n)
        return out

    # ---- main build ---------------------------------------------------------------------------------------------------
    def build(self):
        a, o = self.a, self.o
        self.build_indexes()
        if a.roots:
            roots = self.resolve_roots(a.roots)
            seen, sigs = self.closure(roots, a.all_refs, not a.no_interfaces)
            self.roots = roots
        else:
            seen = {n for t in self.missing.values() for n in t}
            sigs = None; self.roots = []
        enums = sorted(n for n in seen if o[n]['type'] == 'Enum')
        structs_set = {n for n in seen if o[n]['type'] == 'ScriptStruct'}
        classes_set = {n for n in seen if o[n]['type'] == 'Class'}
        def sdeps(n):
            v = o[n]; h, s, g = self.prop_refs(v['properties'])
            return ({v['super_struct']} if v.get('super_struct') else set()) | {x for x in h if x in o and o[x]['type'] == 'ScriptStruct'}
        def cdeps(n):
            v = o[n]; h, s, g = self.prop_refs(v['properties'])
            return {v['super_struct']} if v.get('super_struct') else set()
        structs = self.topo(structs_set, sdeps)
        classes = self.topo(classes_set, cdeps)
        out_set = set(enums) | structs_set | classes_set
        # unresolved references: neither in the editor nor emitted
        def present(x):
            v = o.get(x)
            if not v: return False
            if v['type'] == 'Function': return True
            return not self.is_missing(x) or x in out_set
        self.out_set = out_set
        C = [self.enc_class(n, o[n], not a.no_functions) for n in classes]
        S = [self.enc_struct(n, o[n]) for n in structs]
        E = [self.enc_enum(n, o[n]) for n in enums]
        # unresolved
        unresolved_all = collections.Counter()
        def add_ur(rec, props, extra=()):
            h, s, g = self.prop_refs(props)
            u = sorted(x for x in (h | s) if not present(x))
            if rec.get('sup') and not present(rec['sup']): u.append(rec['sup'])
            u = sorted(set(u))
            if u:
                rec['ur'] = u
                for x in u: unresolved_all[x] += 1
        for rec in C:
            v = o[rec['p']]; props = list(v['properties'])
            for c in v['children']:
                if c in o and o[c]['type'] == 'Function' and not a.no_functions: props += o[c]['properties']
            add_ur(rec, props)
        for rec in S: add_ur(rec, o[rec['p']]['properties'])
        # delegate signatures referenced by emitted types (package-level ones are emitted separately)
        want = set()
        def collect(props):
            h, s, g = self.prop_refs(props); want.update(g)
        for rec in C:
            v = o[rec['p']]; collect(v['properties'])
            if not a.no_functions:
                for c in v['children']:
                    if c in o and o[c]['type'] == 'Function': collect(o[c]['properties'])
        for rec in S: collect(o[rec['p']]['properties'])
        if sigs: want.update(x for x in sigs if o[x]['class'] != '/Script/CoreUObject.Function')
        pending = list(want); done = set()
        while pending:  # signatures referenced by signatures
            x = pending.pop()
            if x in done or x not in o: continue
            done.add(x)
            h, s, g = self.prop_refs(o[x]['properties']); pending.extend(g)
        D = []
        class_fn_owner_emitted = classes_set
        for x in sorted(done):
            v = o[x]
            if ':' in x:
                owner = x.split(':')[0]
                if owner in class_fn_owner_emitted: continue  # emitted with its class
                if not self.is_missing(owner): self.notes['signature on editor-resident class (not emitted)'] += 1; continue
                self.notes['signature on missing class that is not emitted'] += 1; continue
            rec = self.enc_func(x, v); rec['p'] = x
            rec['pe'] = 1 if x.rsplit('.', 1)[0] in self.ed_pk else 0  # package exists in the editor: the plugin must FindObject first
            add_ur(rec, v['properties'])
            D.append(rec)
        src_sha = hashlib.sha1(open(a.jmap, 'rb').read()).hexdigest()
        self.result = {
            'format': FORMAT_VERSION, 'tool': 'dbd_native_baker.py',
            'source': {'jmap': os.path.basename(a.jmap), 'jmap_sha1': src_sha, 'jmap_metadata': self.meta, 'enum_mode': a.enum_mode,
                       'all_refs': bool(a.all_refs), 'interfaces': not a.no_interfaces, 'functions': not a.no_functions,
                       'roots': self.roots},
            'masks': {'class_flags_strip': hx(mask_of(FL.CLASS, CLASS_STRIP)), 'cpf_derived_candidates': hx(mask_of(FL.CPF, DERIVED_CPF))},
            'counts': {'classes': len(C), 'structs': len(S), 'enums': len(E), 'delegate_signatures': len(D),
                       'functions': sum(len(c.get('fn', ())) for c in C), 'properties': sum(len(c['pr']) for c in C) + sum(len(s['pr']) for s in S),
                       'by_group': dict(collections.Counter(r['g'] for r in C + S + E))},
            'legend': LEGEND,
            'enums': E, 'structs': S, 'classes': C, 'delegates': D,
        }
        self.unresolved_all = unresolved_all
        return self.result

    def resolve_roots(self, spec):
        items = []
        for s in spec:
            if s.startswith('@'): items += [l.strip() for l in open(s[1:], encoding='utf8') if l.strip() and not l.startswith('#')]
            else: items += [x.strip() for x in s.split(',') if x.strip()]
        by_short = collections.defaultdict(list)
        for n, v in self.o.items():
            if v['type'] in ('Class', 'ScriptStruct', 'Enum'): by_short[n.split('.')[-1]].append(n)
        out = []
        for it in items:
            if it in self.o: out.append(it)
            elif len(by_short.get(it, ())) == 1: out.append(by_short[it][0])
            else: raise SystemExit('cannot resolve root %r (%s)' % (it, by_short.get(it)))
        return out

    # ---- CDO deltas --------------------------------------------------------------------------------------------------
    def cdo_deltas(self):
        o = self.o; res = {}
        for rec in self.result['classes']:
            v = o[rec['p']]; cdo = o.get(v['class_default_object']); par = o.get(v['super_struct'])
            if not cdo: continue
            pc = o.get(par['class_default_object']) if par else None
            pv = pc['property_values'] if pc else {}
            d = {k: x for k, x in cdo['property_values'].items() if k not in pv or pv[k] != x}
            e = {'values': d}
            subs = {}
            for s in self.subs.get(v['class_default_object'], ()):
                subs[s.split(':', 1)[1]] = o[s]['property_values']
            if subs: e['subobjects'] = subs
            res[rec['p']] = e
        return {'format': FORMAT_VERSION, 'note': 'values that differ from the parent CDO (jmap property_values: enums as EType::Name, structs as dicts, objects as paths); subobject values are complete',
                'classes': res}

    # ---- diff table for engine classes the editor already has -------------------------------------------------------
    @staticmethod
    def nt(t):
        t = t.replace('Property', '')
        return {'Class': 'Object', 'SoftClass': 'SoftObject', 'Enum': 'Byte', 'MulticastInlineDelegate': 'MulticastDelegate',
                'MulticastSparseDelegate': 'MulticastDelegate', 'FUtf8Str': 'Utf8Str', 'AssetObject': 'SoftObject'}.get(t, t)

    def proposal_members(self):
        res = collections.defaultdict(set); cur = None
        f = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'NOTES', 'header-batch-proposal.md')
        if not os.path.exists(f): return res
        for l in open(f, encoding='utf8'):
            m = re.match(r'## (\w+) \(', l)
            if m: cur = m.group(1); continue
            m = re.match(r'- after `[^`]*`: `([^`]*)`', l)
            if m and cur:
                d = re.sub(r'/\*.*?\*/', '', m.group(1)).strip().rstrip(';')
                d = re.sub(r'\s*=.*$', '', d); d = re.sub(r':\d+$', '', d.strip())
                res[cur].add(d.split()[-1].lstrip('*&'))
        return res

    def diff_table(self):
        o = self.o; prop_by_class = self.proposal_members(); out = []
        stats = collections.Counter()
        strip = lambda n: (n[:-11] if n.endswith('_DEPRECATED') else n).lower()  # FName comparison is case-insensitive
        for n, v in o.items():
            if v['type'] not in ('Class', 'ScriptStruct'): continue
            short = n.split('.')[-1]
            if n not in self.ed or short in self.ed_short_dups: continue
            es = self.ES.get(short)
            if not es or es[3] != n.rsplit('.', 1)[0]: continue
            g = [(strip(p['name']), self.nt(p['type']), p['array_dim']) for p in v['properties']]
            e = [(strip(p[1]), self.nt(p[2]), p[5]) for p in sorted(self.EP[short]) if not p[3]]
            eorig = {strip(p[1]): p[1] for p in self.EP[short]}
            stats['compared'] += 1
            if g == e: continue
            gn = [x[0] for x in g]; en = [x[0] for x in e]
            added = {strip(x) for x in set(self.fork_members.get(short, ())) | (prop_by_class.get(short, set()) & self.fork_all_members)}
            gset, eset = set(gn), set(en)
            go = [x for x in g if x[0] not in eset]
            gorig = {strip(p['name']): p['name'] for p in v['properties']}
            batch = [gorig[x[0]] for x in go if x[0] in added]
            go = [x for x in go if x[0] not in added]
            eo = [x for x in e if x[0] not in gset]
            gt = {x[0]: x for x in g}; td = []
            for x in e:
                y = gt.get(x[0])
                if y and (y[1] != x[1] or y[2] != x[2]): td.append({'n': gorig.get(x[0], x[0]), 'game': [y[1], y[2]], 'editor': [x[1], x[2]]})
            common_g = [x for x in gn if x in eset and x not in added]; common_e = [x for x in en if x in gset]
            reorder = common_g != [x for x in common_e if x not in added]
            if batch: stats['members_added_by_hand'] += len(batch)
            if not go and not eo and not td and not reorder:
                stats['fully_resolved_by_hand'] += 1; continue
            rec = {'p': n, 'k': 'class' if v['type'] == 'Class' else 'struct', 'game_n': len(g), 'editor_n': len(e)}
            anchors = {}
            last = None
            for p in v['properties']:
                nm = strip(p['name'])
                if nm in eset and nm not in added: last = p['name']
                elif nm in {x[0] for x in go}: anchors[p['name']] = last
            if go:
                rec['game_only'] = [dict(self.enc_prop(p), after=anchors.get(p['name'])) for p in v['properties'] if strip(p['name']) in {x[0] for x in go}]
            if eo: rec['editor_only'] = [[eorig.get(x[0], x[0]), x[1], x[2]] for x in eo]
            if td: rec['type_diffs'] = td
            if reorder: rec['order_differs'] = True
            if batch: rec['added_by_hand'] = batch
            rec['game_order'] = [[p['name'], p['type'], p['array_dim']] for p in v['properties']]
            rec['game_props'] = [self.enc_prop(p) for p in v['properties']]
            out.append(rec)
        stats['classes_or_structs_with_differences'] = len(out)
        stats['game_only_members'] = sum(len(r.get('game_only', ())) for r in out)
        stats['editor_only_members'] = sum(len(r.get('editor_only', ())) for r in out)
        return {'format': FORMAT_VERSION, 'note': 'editor types (from editor_schemas.tsv, taken before the header batch) whose non-editor-only properties differ from the game; members added by hand in the fork (fork_additions.json + header-batch-proposal.md) are excluded from game_only',
                'stats': dict(stats), 'suspect_enums': sorted(self.suspect_enums), 'types': sorted(out, key=lambda r: r['p'])}

    # ---- usmap cross-check ---------------------------------------------------------------------------------------------
    def validate(self, usmap_path):
        um = _load('usmap_reader').load_usmap(usmap_path)
        o = self.o; rep = {'usmap_version': um['version']}
        ex = collections.defaultdict(list); cnt = collections.Counter()
        def note(k, s):
            cnt[k] += 1
            if len(ex[k]) < 12: ex[k].append(s)
        by_short = collections.defaultdict(list)
        for n, v in o.items():
            if v['type'] in ('Class', 'ScriptStruct'): by_short[n.split('.')[-1]].append(n)
        rep['jmap_short_name_collisions_class_struct'] = sorted(k for k, x in by_short.items() if len(x) > 1)
        enum_short = collections.defaultdict(list)
        for n, v in o.items():
            if v['type'] == 'Enum': enum_short[n.split('.')[-1]].append(n)
        rep['jmap_enum_short_name_collisions'] = sorted(k for k, x in enum_short.items() if len(x) > 1)
        rep['only_in_jmap_class_struct'] = sorted(k for k in by_short if k not in um['schemas'])[:50]
        rep['only_in_usmap_schema'] = sorted(k for k in um['schemas'] if k not in by_short)[:50]
        rep['counts'] = {'jmap_class_struct_short': len(by_short), 'usmap_schemas': len(um['schemas']), 'jmap_enums': len(enum_short), 'usmap_enums': len(um['enums'])}
        def jt(p):
            t = p['type'].replace('Property', '')
            m = {'Class': 'Object', 'SoftClass': 'SoftObject', 'MulticastInlineDelegate': 'MulticastDelegate', 'MulticastSparseDelegate': 'MulticastDelegate',
                 'FUtf8Str': 'Utf8Str', 'AssetObject': 'SoftObject'}
            t = m.get(t, t)
            sh = lambda x: x.split('.')[-1] if x else None
            if t == 'Enum': return ('Enum', sh(p.get('enum')))
            if t == 'Byte' and p.get('enum'): return ('Enum', sh(p['enum']))
            if t == 'Struct': return ('Struct', sh(p['struct']))
            if t == 'Set': return (t, jt(p.get('key_prop') or p['inner']))
            if t in ('Array', 'Optional'): return (t, jt(p['inner']))
            if t == 'Map': return ('Map', jt(p['key_prop']), jt(p['value_prop']))
            return (t,)
        def norm_u(t):
            if t[0] == 'Enum': return ('Enum', t[1])
            if t[0] in ('Array', 'Optional'): return (t[0], norm_u(t[1]))
            if t[0] == 'Set': return ('Set', norm_u(t[1]))
            if t[0] == 'Map': return ('Map', norm_u(t[1]), norm_u(t[2]))
            return t
        for short, paths in sorted(by_short.items()):
            s = um['schemas'].get(short)
            if not s: continue
            up = [(x[1], x[2], norm_u(x[3])) for x in sorted(s['props'])]
            cands = []
            for n in paths:
                v = o[n]
                jp = []
                for p in v['properties']: jp.append((p['name'], p['array_dim'], jt(p)))
                cands.append((n, v, jp))
            ok = False; best = cands[0]
            for n, v, jp in cands:
                if [(x[0], x[1]) for x in jp] == [(x[0], x[1]) for x in up]: ok = True; best = (n, v, jp); break
            n, v, jp = best
            if len(paths) > 1: cnt['colliding short names compared by best match'] += 1
            if not ok:
                note('property name/array_dim sequence differs', '%s jmap=%d usmap=%d' % (n, len(jp), len(up)))
                continue
            cnt['classes/structs with identical property name+dim sequence'] += 1
            for a_, b_ in zip(jp, up):
                if a_[2] != b_[2] and not (a_[2][0] in ('Byte', 'Enum') and b_[2][0] in ('Byte', 'Enum') and (a_[2][1:] == b_[2][1:] or b_[2][0] == 'Byte' or a_[2][0] == 'Byte')):
                    note('property type differs', '%s.%s jmap=%s usmap=%s' % (n, a_[0], a_[2], b_[2]))
            sup_j = v['super_struct'].split('.')[-1] if v.get('super_struct') else None
            if sup_j != s['super']: note('super differs', '%s jmap=%s usmap=%s' % (n, sup_j, s['super']))
        for short, paths in sorted(enum_short.items()):
            e = um['enums'].get(short)
            if e is None: note('enum missing in usmap', short); continue
            for n in paths:
                names = [(x[1], x[0]) for x in o[n]['names']]
                # usmap names are unprefixed enumerators; jmap names may carry the EnumName:: prefix for namespaced/enum class
                un = [(v_, nm_) for v_, nm_ in e]
                jn = [(val, nm.split('::')[-1]) for nm, val in o[n]['names']]
                if jn == un: cnt['enums identical (names+values)'] += 1; break
            else:
                if sorted(jn) == sorted(un): note('enum: same entries, different order', short)
                elif sorted(x[1] for x in jn) == sorted(x[1] for x in un): note('enum: same names, different values', '%s jmap=%s usmap=%s' % (short, sorted(jn)[:4], sorted(un)[:4]))
                else: note('enum: different entries', '%s jmap=%s usmap=%s' % (short, sorted(jn)[:4], sorted(un)[:4]))
        rep['summary'] = dict(cnt); rep['examples'] = dict(ex)
        return rep


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--jmap', default=r'C:\Workspace\DeadByDaylight-Data\DBD-10.2.2.jmap')
    ap.add_argument('--usmap', default=r'C:\Workspace\DeadByDaylight-Data\DBD-10.2.2.usmap')
    ap.add_argument('--editor-schemas', default=r'C:\Workspace\B_work\editor_schemas.tsv')
    ap.add_argument('--out', default=os.path.join(DATA, 'dbd_native_types.json'))
    ap.add_argument('--roots', action='append', help='class paths or short names, comma separated, or @file (repeatable)')
    ap.add_argument('--all-refs', action='store_true', help='with --roots: also follow object/class/interface references, delegate signatures and default subobject classes')
    ap.add_argument('--no-interfaces', action='store_true', help='do not treat implemented interfaces as hard dependencies')
    ap.add_argument('--no-functions', action='store_true')
    ap.add_argument('--enum-mode', choices=('package', 'source'), default='package',
                    help='package (design doc logic): enums of packages the editor has classes in are present; source: only if also found as UENUM in the stock source scan')
    ap.add_argument('--cdo-out'); ap.add_argument('--diff-out', help='editor-class diff table (default data/dbd_editor_diffs.json when no --roots)')
    ap.add_argument('--no-diff', action='store_true'); ap.add_argument('--validate', action='store_true')
    ap.add_argument('--stats', action='store_true'); ap.add_argument('--pretty', action='store_true')
    a = ap.parse_args()
    b = Baker(a)
    res = b.build()
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'w', encoding='utf8', newline='\n') as f:
        json.dump(res, f, separators=None if a.pretty else (',', ':'), indent=1 if a.pretty else None, ensure_ascii=True)
    sz = os.path.getsize(a.out)
    print('wrote %s (%.1f MB): %s' % (a.out, sz / 1e6, res['counts']))
    if b.bad_flags: print('UNKNOWN FLAG NAMES:', dict(b.bad_flags))
    if b.notes: print('notes:', dict(b.notes))
    print('unresolved references (not in editor, not emitted):', len(b.unresolved_all), 'distinct; sample', list(b.unresolved_all.items())[:5])
    if a.cdo_out:
        json.dump(b.cdo_deltas(), open(a.cdo_out, 'w', encoding='utf8', newline='\n'), separators=(',', ':'))
        print('wrote', a.cdo_out, '%.1f MB' % (os.path.getsize(a.cdo_out) / 1e6))
    if not a.roots and not a.no_diff or a.diff_out:
        dt = b.diff_table(); p = a.diff_out or os.path.join(DATA, 'dbd_editor_diffs.json')
        json.dump(dt, open(p, 'w', encoding='utf8', newline='\n'), separators=(',', ':'))
        print('wrote', p, dt['stats'])
    if a.validate:
        rep = b.validate(a.usmap); p = os.path.join(DATA, 'validation_report.json')
        json.dump(rep, open(p, 'w', encoding='utf8', newline='\n'), indent=1)
        print('validation:', rep['summary'])


if __name__ == '__main__':
    main()
