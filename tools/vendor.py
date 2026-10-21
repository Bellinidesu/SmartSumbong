"""The portal's browser libraries, kept in admin/assets/vendor and listed in admin/assets/vendor/vendor.json: which npm
package and version each file came from, its licence, how it was made (copied as published, built, or patched) and the
SHA-256 of every file. Standard library only.

    python tools/vendor.py check              every file matches its recorded hash and has its licence beside it (CI)
    python tools/vendor.py outdated [--md F]  newer versions on npm, and known advisories (OSV) for the versions we ship
    python tools/vendor.py fetch NAME [VER]   download a version from npm, check npm's integrity hash, and for a
                                              copied library put the files in place and update vendor.json; for a
                                              built or patched one, unpack it and print the steps in its note
    python tools/vendor.py rehash NAME        record the hashes again after a built or patched library was redone

See docs/UPDATING.md for how this fits with Dependabot and Composer."""
import base64, hashlib, io, json, os, shutil, sys, tarfile, tempfile, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, 'admin', 'assets', 'vendor')
MANIFEST = os.path.join(VENDOR, 'vendor.json')
UA = {'User-Agent': 'SmartSumbong-vendor/1.0'}


def load():
    return json.load(open(MANIFEST, encoding='utf-8'))


def save(m):
    with open(MANIFEST, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(m, f, indent=2, ensure_ascii=False)
        f.write('\n')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 16), b''):
            h.update(chunk)
    return h.hexdigest()


def get_json(url, body=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body else None,
                                 headers={**UA, 'Content-Type': 'application/json'} if body else UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def npm_meta(pkg, version='latest'):
    return get_json('https://registry.npmjs.org/' + pkg.replace('/', '%2F') + '/' + version)


def check():
    m, bad = load(), 0
    for name, lib in m['libraries'].items():
        for rel, f in lib['files'].items():
            p = os.path.join(VENDOR, rel)
            if not os.path.isfile(p):
                print(f'MISSING  {name}: {rel}'); bad += 1
            elif sha256(p) != f['sha256']:
                print(f'CHANGED  {name}: {rel} differs from vendor.json (update it with fetch or rehash)'); bad += 1
        lic = lib.get('licence_file')
        if not lic or not os.path.isfile(os.path.join(VENDOR, lic)):
            print(f'LICENCE  {name}: no licence file beside it'); bad += 1
    listed = {os.path.normpath(r) for lib in m['libraries'].values() for r in list(lib['files']) + [lib.get('licence_file', '')]}
    for d, _, files in os.walk(VENDOR):
        for fn in files:
            rel = os.path.normpath(os.path.relpath(os.path.join(d, fn), VENDOR))
            if rel not in listed and fn not in ('vendor.json', 'README.md', 'PATCH.txt'):
                print(f'UNLISTED {rel}: add it to vendor.json'); bad += 1
    print('ok   every vendored file matches vendor.json' if not bad else f'{bad} problem(s)')
    return 1 if bad else 0


def outdated(md=None):
    m, rows = load(), []
    for name, lib in m['libraries'].items():
        pkg = lib.get('npm')
        if not pkg:
            continue
        try:
            latest = npm_meta(pkg)['version']
        except Exception as e:
            latest = f'? ({e.__class__.__name__})'
        vulns = []
        try:
            r = get_json('https://api.osv.dev/v1/query', {'package': {'name': pkg, 'ecosystem': 'npm'}, 'version': lib['version']})
            vulns = [v['id'] for v in r.get('vulns', [])]
        except Exception:
            vulns = ['(OSV did not answer)']
        if latest != lib['version'] or vulns:
            rows.append((name, pkg, lib['version'], latest, ', '.join(vulns) or '—', lib['how']))
    if not rows:
        print('ok   every vendored library is the latest version with no known advisory')
    else:
        print(f'{"library":14} {"ships":10} {"latest":10} advisories')
        for r in rows:
            print(f'{r[0]:14} {r[2]:10} {r[3]:10} {r[4]}')
    if md:
        with open(md, 'w', encoding='utf-8') as f:
            if rows:
                f.write('Vendored browser libraries with a newer version or a known advisory (`python tools/vendor.py outdated`).\n\n'
                        '| Library | npm | Ships | Latest | Advisories | How it is made |\n|---|---|---|---|---|---|\n')
                for r in rows:
                    f.write(f'| {r[0]} | `{r[1]}` | {r[2]} | {r[3]} | {r[4]} | {r[5]} |\n')
                f.write('\nUpdate with `python tools/vendor.py fetch <library>`; see docs/UPDATING.md.\n')
    return 0


def fetch(name, version=None):
    m = load()
    lib = m['libraries'].get(name) or sys.exit(f'{name} is not in vendor.json')
    meta = npm_meta(lib['npm'], version or 'latest')
    ver, dist = meta['version'], meta['dist']
    with urllib.request.urlopen(urllib.request.Request(dist['tarball'], headers=UA), timeout=60) as r:
        blob = r.read()
    algo, want = dist['integrity'].split('-', 1)
    if algo != 'sha512' or base64.b64encode(hashlib.sha512(blob).digest()).decode() != want:
        sys.exit(f'{lib["npm"]} {ver}: the download does not match npm\'s integrity hash; nothing changed')
    stage = os.path.join(tempfile.gettempdir(), f'vendor-{name}-{ver}')
    shutil.rmtree(stage, ignore_errors=True)
    with tarfile.open(fileobj=io.BytesIO(blob), mode='r:gz') as t:
        t.extractall(stage, filter='data')
    pkgdir = os.path.join(stage, 'package')
    if lib['how'] != 'copy':
        print(f'{lib["npm"]} {ver} checked against npm and unpacked in {pkgdir}\n{lib["how"]}: {lib.get("note", "")}\n'
              f'When the files are in place: python tools/vendor.py rehash {name} {ver}')
        return 0
    for rel, f in lib['files'].items():
        src = os.path.join(pkgdir, f['from'])
        if not os.path.isfile(src):
            sys.exit(f'{ver} has no {f["from"]}; nothing changed')
    for rel, f in lib['files'].items():
        shutil.copyfile(os.path.join(pkgdir, f['from']), os.path.join(VENDOR, rel))
        f['sha256'] = sha256(os.path.join(VENDOR, rel))
    if lib.get('licence_from'):
        shutil.copyfile(os.path.join(pkgdir, lib['licence_from']), os.path.join(VENDOR, lib['licence_file']))
    print(f'{name}: {lib["version"]} -> {ver}')
    lib['version'] = ver
    save(m)
    return 0


def rehash(name, version=None):
    m = load()
    lib = m['libraries'].get(name) or sys.exit(f'{name} is not in vendor.json')
    for rel, f in lib['files'].items():
        f['sha256'] = sha256(os.path.join(VENDOR, rel))
    if version:
        lib['version'] = version
    save(m)
    print(f'{name}: hashes recorded' + (f', version {version}' if version else ''))
    return 0


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] not in ('check', 'outdated', 'fetch', 'rehash'):
        sys.exit(__doc__)
    if a[0] == 'check':
        sys.exit(check())
    if a[0] == 'outdated':
        sys.exit(outdated(a[a.index('--md') + 1] if '--md' in a else None))
    if len(a) < 2:
        sys.exit(__doc__)
    sys.exit((fetch if a[0] == 'fetch' else rehash)(a[1], a[2] if len(a) > 2 else None))
