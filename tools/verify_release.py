"""Verify saved programming files and evidence without connecting to a board."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def verify(root, version):
    manifests = sorted((root / 'releases' / version).glob('*/manifest.json'))
    if not manifests:
        raise ValueError(f'No saved manifest for {version}')
    results = []
    for manifest_path in manifests:
        folder = manifest_path.parent
        manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
        artifacts = []
        for extension in ('bit', 'hex'):
            expected = manifest.get(extension + '_sha256')
            if expected:
                path = folder / f'{version}.{extension}'
                if digest(path) != expected.upper():
                    raise ValueError(f'SHA256 mismatch: {path.relative_to(root)}')
                artifacts.append(path.relative_to(root).as_posix())
        if not artifacts:
            raise ValueError(f'No programming-file hashes in {manifest_path}')
        evidence_count = 0
        inventory = folder / 'evidence-sha256.json'
        if inventory.exists():
            evidence = json.loads(inventory.read_text(encoding='utf-8-sig'))
            for item in evidence['files']:
                path = folder / item['path']
                if digest(path) != item['sha256'].upper() or path.stat().st_size != item['bytes']:
                    raise ValueError(f'Evidence mismatch: {path.relative_to(root)}')
                evidence_count += 1
        results.append({'version': version, 'target': folder.name,
                        'integrity': 'PASS', 'artifacts': artifacts,
                        'evidence_files': evidence_count,
                        'saved_timing_status': manifest.get('timing_status', 'not recorded'),
                        'hardware_acceptance': 'not checked by this command'})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('versions', nargs='*', default=['A15', 'WB03R1'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    results = [result for version in args.versions for result in verify(root, version)]
    print(json.dumps(results, indent=2, ensure_ascii=True))


if __name__ == '__main__':
    main()
