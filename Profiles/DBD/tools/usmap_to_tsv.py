"""Writes the usmap schema dump that Suzie.VerifyNativeTypes reads (data/cache/game_schemas.tsv).
  python -I usmap_to_tsv.py [--usmap <game>.usmap] [--out <file.tsv>] [--local-ini <ModkitLocal.ini>]
The usmap comes from --usmap, env SUZIE_USMAP, or Usmap= of the local ini (--local-ini or env MODKIT_LOCAL_INI).
Default output: data/cache/game_schemas.tsv of the profile.
Lines (tab separated, CRLF, usmap order):
  S  <struct>  <super or empty>  <number of P lines of the struct>
  P  <struct>  <schema index>  <name>  <FProperty class name>  <array dim>     one line per static array element"""
import argparse, configparser, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from usmap_reader import load_usmap


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--usmap', default=os.environ.get('SUZIE_USMAP'))
    ap.add_argument('--out', default=os.path.join(os.path.dirname(HERE), 'data', 'cache', 'game_schemas.tsv'))
    ap.add_argument('--local-ini', default=os.environ.get('MODKIT_LOCAL_INI'))
    a = ap.parse_args()
    if not a.usmap and a.local_ini:
        ini = configparser.ConfigParser(strict=False, interpolation=None, comment_prefixes=(';', '#'))
        ini.optionxform = str
        ini.read(a.local_ini, encoding='utf8')
        a.usmap = ini.get('Local', 'Usmap', fallback=None)
    if not a.usmap: ap.error('no usmap: pass --usmap, set SUZIE_USMAP or Usmap= in ModkitLocal.ini with --local-ini')
    um = load_usmap(a.usmap)
    out = []
    for name, s in um['schemas'].items():
        out.append('S\t%s\t%s\t%d\n' % (name, s['super'] or '', sum(p[2] for p in s['props'])))
        for idx, pn, dim, typ in s['props']:
            for e in range(dim):
                out.append('P\t%s\t%d\t%s\t%sProperty\t%d\n' % (name, idx + e, pn, typ[0], dim))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'w', encoding='utf8', newline='\r\n') as f:
        f.writelines(out)
    print('%d schemas, %d lines -> %s' % (len(um['schemas']), len(out), a.out))


if __name__ == '__main__':
    main()
