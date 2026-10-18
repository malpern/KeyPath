#!/usr/bin/env python3
"""Build offline HTML and a versioned, file-hashed update manifest from the web guides."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parent.parent

def build(output, app_version):
    if not shutil.which('pandoc'):
        raise SystemExit('pandoc is required to build offline help (brew install pandoc)')
    output.mkdir(parents=True, exist_ok=True)
    files = {}
    def put(path, data):
        target = output / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        files[path] = hashlib.sha256(data).hexdigest()
    put('assets/help-theme.css', (ROOT / 'assets/css/help-theme.css').read_bytes())
    sources = list((ROOT / 'guides').glob('*.md')) + list((ROOT / 'migration').glob('*.md'))
    names = {p.stem for p in sources}
    topics = set(re.findall(r'resource: \"([^\"]+)\"', (ROOT / 'Sources/KeyPathAppKit/UI/Help/HelpBrowserView.swift').read_text()))
    if not topics.issubset(names):
        raise SystemExit('Missing offline topics: ' + ', '.join(sorted(topics - names)))
    missing = set()
    for source in sorted(sources):
        text = source.read_text()
        # Jekyll's front matter and relative_url filter are build-time syntax.
        header, text = re.match(r'\A---\n(.*?)\n---\n(.*)\Z', text, re.S).groups()
        text = re.sub(r"\{\{\s*['\"]([^'\"]+)['\"]\s*\|\s*relative_url\s*\}\}", r'\1', text)
        header_image = re.search(r'^header_image:\s*(.+)$', header, re.M)
        if header_image:
            text = f'![Guide illustration](/images/help/{header_image.group(1).strip()})\n\n' + text
        fragment = subprocess.check_output(['pandoc', '--from=gfm', '--to=html5', '--wrap=none'], input=text, text=True)
        def image(match):
            raw = html.unescape(match.group(1))
            name = Path(raw).name
            candidates = [ROOT / raw.lstrip('/'), ROOT / 'images/help' / name,
                          ROOT / 'Sources/KeyPathAppKit/Resources' / name]
            local = next((p for p in candidates if p.is_file()), None)
            if local is None:
                missing.add(raw)
                return match.group(0)
            path = 'assets/' + name
            if path in files and files[path] != hashlib.sha256(local.read_bytes()).hexdigest():
                raise ValueError('Duplicate image name with different contents: ' + name)
            put(path, local.read_bytes())
            return 'src="../' + path + '"'
        fragment = re.sub(r'src="([^"]+)"', image, fragment)
        def link(match):
            raw = html.unescape(match.group(1))
            if raw.startswith(('http:', 'https:', 'mailto:', '#', 'keypath:')):
                return match.group(0)
            raw = raw.replace('/getting-started/installation/', '/guides/installation-wizard/')
            resource = raw.removeprefix('help:').removeprefix('//').split('#')[0].rstrip('/').split('/')[-1].removesuffix('.md')
            anchor = '#' + raw.split('#', 1)[1] if '#' in raw else ''
            if resource in names:
                return 'href="help://' + resource + anchor + '"'
            # References outside the built-in guide set still open on the website.
            if raw.startswith('/'):
                return 'href="https://malpern.github.io/KeyPath' + raw + '"'
            missing.add('link:' + raw)
            return match.group(0)
        fragment = re.sub(r'href="([^"]+)"', link, fragment)
        fragment = fragment.replace('<img ', '<img class="help-img" ')
        title = re.search(r'^title:\s*[\"\']?(.*?)[\"\']?$', header, re.M).group(1)
        csp = "default-src 'none'; img-src file: data:; style-src file: 'unsafe-inline'; font-src file:; base-uri 'none'; form-action 'none'"
        page = f'<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><meta http-equiv="Content-Security-Policy" content="{csp}"><title>{html.escape(title)}</title><link rel="stylesheet" href="../assets/help-theme.css"></head><body>{fragment}</body></html>'
        put('articles/' + source.stem + '.html', page.encode())
    if missing:
        raise SystemExit('Unresolved offline help references:\n' + '\n'.join(sorted(missing)))
    manifest = {'schema': 1, 'appVersion': app_version, 'files': dict(sorted(files.items()))}
    manifest['revision'] = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
    (output / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
    print(f'Offline help: {len(sources)} guides, {len(files)} files, revision {manifest["revision"][:12]}')
    return manifest

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    version = plistlib.loads((ROOT / 'Sources/KeyPathApp/Info.plist').read_bytes())['CFBundleShortVersionString']
    p.add_argument('--publish-root', type=Path, help='Also stage an immutable update revision under this root')
    p.add_argument('--app-version', default='.'.join(version.split('.')[:2]), help='Compatible app major.minor version')
    args = p.parse_args()
    manifest = build(args.output, args.app_version)
    if args.publish_root:
        version_root = args.publish_root / args.app_version
        revision_root = version_root / manifest['revision']
        if not revision_root.exists():
            shutil.copytree(args.output, revision_root)
        version_root.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.output / 'manifest.json', version_root / 'manifest.json')
