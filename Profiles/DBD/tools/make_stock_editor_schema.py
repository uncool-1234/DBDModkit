#!/usr/bin/env python3
"""Turn an editor reflection dump (editor_schemas.tsv) that was taken while the fork still carried hand-added game members into a STOCK
reflection dump, by removing every UPROPERTY the given engine commit(s) added to engine headers and every type those commits added.

  python make_stock_editor_schema.py --repo <engine repo> --commit f398fcb42 [--commit ...] --in editor_schemas.tsv --out editor_schemas_stock.tsv

Members are read from the added lines of `git show <commit>` (UPROPERTY(...) followed by a declaration); the owning class/struct is found by
scanning the post-commit header for the closest preceding class/struct declaration. Types are USTRUCT/UCLASS/UENUM declarations in files
the commit ADDED. Only needed while the baker input dump was taken from a modified fork; with a dump from a stock editor use it directly.
"""
import argparse, collections, re, subprocess, sys


def git(repo, *a):
    return subprocess.run(['git', '-C', repo] + list(a), capture_output=True, text=True, encoding='utf8', errors='replace', check=True).stdout


def owner_of(lines, idx):
    """Closest enclosing class/struct body of lines[idx] (brace tracking, comments and strings ignored)."""
    pat = re.compile(r'^\s*(?:class|struct)\s+(?:\w+_API\s+)?(\w+)\s*(?:final\s*)?(?::[^;(*&]*)?\s*\{?\s*$')
    depth = 0
    for i in range(idx, -1, -1):
        l = re.sub(r'//.*$', '', lines[i])
        l = re.sub(r'"[^"]*"', '""', l)
        for ch in reversed(l):
            if ch == '}': depth += 1
            elif ch == '{':
                if depth > 0: depth -= 1
                else:
                    # opening brace of the scope that encloses idx: its header is on this line or just above
                    for j in range(i, max(-1, i - 4), -1):
                        m = pat.match(re.sub(r'//.*$', '', lines[j]))
                        if m: return m.group(1)
                    break  # not a class scope (function, namespace, enum): keep looking outward
    return None


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--repo', required=True); ap.add_argument('--commit', action='append', required=True)
    ap.add_argument('--marks-out', help='write the members/types as schema/_fork_additions.json (the baker marks these recipe entries fk=1)')
    ap.add_argument('--in', dest='inp', required=True); ap.add_argument('--out', required=True)
    a = ap.parse_args()
    drop = collections.defaultdict(set); types = set()
    for c in a.commit:
        files = git(a.repo, 'show', '--name-status', '--format=', c).split('\n')
        for l in files:
            if not l.strip(): continue
            st, path = l.split('\t')[:2]
            if not path.endswith('.h'): continue
            post = git(a.repo, 'show', '%s:%s' % (c, path)).replace('\r', '').split('\n')
            diff = git(a.repo, 'show', '--format=', '-U0', c, '--', path).replace('\r', '').split('\n')
            # added line numbers in the post-commit file
            added = set(); cur = 0
            for d in diff:
                m = re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', d)
                if m: cur = int(m.group(1)); continue
                if d.startswith('+') and not d.startswith('+++'): added.add(cur); cur += 1
            if st == 'A':
                for l2 in post:
                    m = re.match(r'^\s*(?:struct|class)\s+(?:\w+_API\s+)?([FUA]?\w+)', l2)
                    if m and not l2.rstrip().endswith(';'): types.add(m.group(1)[1:] if m.group(1)[0] in 'FUA' else m.group(1))
                    m = re.match(r'^\s*enum\s+class\s+(\w+)', l2)
                    if m: types.add(m.group(1))
                continue
            for i, l2 in enumerate(post):
                if (i + 1) not in added: continue
                # a member declaration (not UPROPERTY/comment): `Type Name;` or `Type Name = x;` or bitfield `uint8 bName:1;`
                s = l2.strip()
                if not s or s.startswith(('//', 'UPROPERTY', '#', '/*', '*', 'public:', 'protected:', 'private:', '{', '}')): continue
                s = re.sub(r'//.*$', '', s).strip()
                m = re.match(r'^[\w:<>,\s\*&]+?\b(\w+)\s*(?::\s*\d+)?\s*(?:=\s*[^;]+|\{[^;]*\})?;$', s)
                if m:
                    # only if preceded within 3 lines by UPROPERTY
                    if any('UPROPERTY' in post[j] for j in range(max(0, i - 4), i)):
                        own = owner_of(post, i)
                        if own: drop[own[1:] if own[0] in 'FUA' and own[1:2].isupper() else own].add(m.group(1))
    n_drop = sum(len(v) for v in drop.values())
    out = []; removed = 0; typeskip = set()
    for l in open(a.inp, encoding='utf8'):
        p = l.rstrip('\r\n').split('\t')
        if p[0] == 'S' and p[1] in types: typeskip.add(p[1]); removed += 1; continue
        if p[0] == 'P' and (p[1] in typeskip or p[1] in types): removed += 1; continue
        if p[0] == 'P' and p[3] in drop.get(p[1], ()): removed += 1; continue
        out.append(l)
    open(a.out, 'w', encoding='utf8', newline='').write(''.join(out))
    print('dropped %d members in %d types, %d types (%s); removed %d lines' % (n_drop, len(drop), len(types), ','.join(sorted(types)), removed))
    if a.marks_out:
        import json
        json.dump({'base': ','.join(a.commit), 'types': sorted(types - {'TStructOpsTypeTraits'}), 'members': {k: sorted(v) for k, v in sorted(drop.items())}}, open(a.marks_out, 'w'), indent=1)
    for k in sorted(drop): print(' ', k, sorted(drop[k]))


main()
