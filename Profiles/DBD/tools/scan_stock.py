"""Scans the stock 5.7.4 tree (read only) for UENUM names and module Build.cs files; writes data/stock_info.json.
Usage: python -I scan_stock.py [engine_root]"""
import os, re, sys, json
root = sys.argv[1] if len(sys.argv) > 1 else r'C:\Workspace\UnrealEngine-5.7.4-release'
out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data', 'stock_info.json')
rx = re.compile(r'UENUM\s*\([^)]*\)\s*(?:(?:/\*.*?\*/|//[^\n]*\n)\s*)*(?:enum\s+(?:class\s+)?(?:\w+_API\s+)?(\w+)|namespace\s+(\w+))', re.S)
enums, modules = set(), {}
for base in ('Source', 'Plugins'):
    for d, _, fs in os.walk(os.path.join(root, 'Engine', base)):
        for f in fs:
            if f.endswith('.Build.cs'): modules[f[:-9]] = os.path.relpath(os.path.join(d, f), root).replace(os.sep, '/')
            elif f.endswith('.h'):
                try: t = open(os.path.join(d, f), encoding='utf8', errors='ignore').read()
                except OSError: continue
                if 'UENUM' not in t: continue
                for m in rx.finditer(t): enums.add(m.group(1) or m.group(2))
json.dump({'engine_root_name': os.path.basename(root), 'enums': sorted(enums), 'modules': dict(sorted(modules.items()))}, open(out, 'w'), indent=0)
print(len(enums), 'enums', len(modules), 'modules')
