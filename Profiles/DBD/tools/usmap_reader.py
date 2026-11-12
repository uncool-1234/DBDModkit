"""Minimal .usmap reader (version <= 5, uncompressed only). Used to cross-check the jmap.
load_usmap(path) -> {'enums': {name: [(value, name)]}, 'schemas': {name: {'super': str|None, 'props': [(index, name, array_dim, type)]}}}
A type is (kind, extra...): ('Struct', structName), ('Enum', enumName, underlyingType), ('Array', inner), ('Map', key, value), plain ('Int',) ...
Static arrays: one entry per property (array_dim), indices span the elements (as in the engine schema)."""
import struct

TYPES = ['Byte', 'Bool', 'Int', 'Float', 'Object', 'Name', 'Delegate', 'Double', 'Array', 'Struct', 'Str', 'Text',
         'Interface', 'MulticastDelegate', 'WeakObject', 'LazyObject', 'AssetObject', 'SoftObject', 'UInt64', 'UInt32',
         'UInt16', 'Int64', 'Int16', 'Int8', 'Map', 'Set', 'Enum', 'FieldPath', 'Optional', 'Utf8Str', 'AnsiStr']


class _R:
    def __init__(s, b): s.b, s.o = b, 0
    def u8(s): v = s.b[s.o]; s.o += 1; return v
    def u16(s): v = struct.unpack_from('<H', s.b, s.o)[0]; s.o += 2; return v
    def i32(s): v = struct.unpack_from('<i', s.b, s.o)[0]; s.o += 4; return v
    def u32(s): v = struct.unpack_from('<I', s.b, s.o)[0]; s.o += 4; return v
    def i64(s): v = struct.unpack_from('<q', s.b, s.o)[0]; s.o += 8; return v


def load_usmap(path):
    b = open(path, 'rb').read()
    r = _R(b)
    if r.u16() != 0x30C4: raise ValueError('bad usmap magic')
    ver = r.u8()
    if ver >= 1 and r.u8() != 0: raise ValueError('versioned usmap not supported by this reader')
    comp = r.u32(); csz = r.u32(); dsz = r.u32()  # observed layout for this file: 4-byte compression field
    if comp != 0: raise ValueError('compressed usmap (%d) not supported' % comp)
    r = _R(b[r.o:r.o + dsz])
    names = []
    for _ in range(r.u32()):
        n = r.u16() if ver >= 2 else r.u8()
        names.append(r.b[r.o:r.o + n].decode('utf8')); r.o += n
    nm = lambda i: None if i < 0 else names[i]
    enums = {}
    for _ in range(r.u32()):
        en = nm(r.i32()); cnt = r.u16() if ver >= 3 else r.u8(); vals = []
        for i in range(cnt):
            if ver >= 4: v = r.i64(); vals.append((v, nm(r.i32())))
            else: vals.append((i, nm(r.i32())))
        enums[en] = vals

    def rtype():
        t = r.u8()
        if t == 0xFF: return ('Unknown',)
        k = TYPES[t]
        if k == 'Enum':
            inner = rtype(); return ('Enum', nm(r.i32()), inner)
        if k == 'Struct': return ('Struct', nm(r.i32()))
        if k in ('Array', 'Set', 'Optional'): return (k, rtype())
        if k == 'Map':
            a = rtype(); return ('Map', a, rtype())
        return (k,)
    schemas = {}
    for _ in range(r.u32()):
        n = nm(r.i32()); sup = nm(r.i32()); pc = r.u16(); sc = r.u16(); props = []
        for _ in range(sc):
            idx = r.u16(); dim = r.u8(); pn = nm(r.i32()); props.append((idx, pn, dim, rtype()))
        schemas[n] = {'super': sup, 'props': props, 'prop_count': pc}
    return {'enums': enums, 'schemas': schemas, 'version': ver}
