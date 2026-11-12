import sys, re, collections
import xml.etree.ElementTree as ET
if len(sys.argv) < 2:
    print("usage: profile.py <profile.xml> [regex] [incl|under|callers] [symbol] [depth]")
    sys.exit(1)
path = sys.argv[1]
pat = re.compile(sys.argv[2]) if len(sys.argv) > 2 else None
mode = sys.argv[3] if len(sys.argv) > 3 else 'incl'
root = ET.parse(path).getroot()
ids = {}
def reg(e):
    i = e.get('id')
    if i is not None:
        ids[i] = e
    for c in e:
        reg(c)
reg(root)
def res(e):
    r = e.get('ref')
    return ids[r] if r is not None else e
samples = []
for row in root.iter('row'):
    th = row.find('thread'); bt = row.find('tagged-backtrace')
    if bt is None: bt = row.find('backtrace')
    if th is None or bt is None: continue
    th = res(th); bt = res(bt)
    frames = [res(f).get('name') or '?' for f in bt.findall('frame')]
    samples.append((th.get('fmt'), frames))
per_thread = collections.Counter(t for t, _ in samples)
main = None
for t, fr in samples:
    if 'NSApplicationMain' in fr:
        main = t; break
ms = [fr for t, fr in samples if t == main]
print('main', main, 'samples', len(ms), 'total', len(samples))
if mode == 'incl':
    c = collections.Counter()
    for fr in ms:
        for s in set(fr):
            c[s] += 1
    for s, n in c.most_common(5000):
        if pat and not pat.search(s): continue
        print(f'{n:6d} {100*n/len(ms):5.1f}% {s[:170]}')
elif mode == 'under':
    target = sys.argv[4]; depth = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    c = collections.Counter()
    for fr in ms:
        rev = list(reversed(fr))
        if target in rev:
            i = rev.index(target)
            chain = rev[i+1:i+1+depth]
            for d in range(1, len(chain)+1):
                c[' > '.join(chain[:d])] += 1
    for s, n in c.most_common(30):
        print(f'{n:6d} {s[:200]}')
elif mode == 'callers':
    target = sys.argv[4]; depth = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    c = collections.Counter()
    for fr in ms:
        rev = list(reversed(fr))
        if target in rev:
            i = rev.index(target)
            chain = [f for f in rev[max(0, i-depth):i] if not f.startswith('protocol witness')]
            c[' < '.join(reversed(chain))] += 1
    for s, n in c.most_common(30):
        print(f'{n:6d} {s[:220]}')
