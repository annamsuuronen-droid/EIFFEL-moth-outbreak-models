"""Independent read-only SHA256 verification of the completed-fold capture. No R/models."""
import argparse
import csv
import hashlib
from pathlib import Path, PurePosixPath

PREFIX = 'hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05/'
EXPECTED = {PREFIX+'outer_test_predictions.csv2', PREFIX+'outer_test_metrics.csv2',
            'checkpoint_verification.csv', 'reconstructed_provenance_summary.csv', 'source_manifest.csv'}

def rows(path):
    with path.open(encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))

def verify(snapshot):
    snapshot = Path(snapshot).resolve(strict=True)
    inventory = rows(snapshot/'artifact_manifest.csv')
    names = [r['relative_path'] for r in inventory]
    if len(names) != len(EXPECTED) or set(names) != EXPECTED:
        raise ValueError('Unexpected artifact allow-list')
    for record in inventory:
        relative = record['relative_path']
        if PurePosixPath(relative).is_absolute() or any(p in ('', '.', '..') for p in relative.split('/')) or '\\' in relative:
            raise ValueError('Unsafe artifact path')
        path = snapshot/relative
        for part in [path, *path.parents]:
            if part == snapshot:
                break
            if part.is_symlink():
                raise ValueError('Artifact symlink forbidden')
        actual = path.read_bytes()
        if len(actual) != int(record['size']) or hashlib.sha256(actual).hexdigest() != record['sha256']:
            raise ValueError('Artifact SHA256/size mismatch: '+relative)
        if hashlib.md5(actual).hexdigest() != record['md5']:
            raise ValueError('Artifact MD5 mismatch: '+relative)
    sources = rows(snapshot/'source_manifest.csv')
    if len(sources) != 5:
        raise ValueError('Unexpected source count')
    for source in sources[:2]:
        artifact = next(r for r in inventory if r['relative_path'] == source['source_relative_path'])
        if source['action'] != 'COPY' or source['status'] != 'COPIED_SHA256_VERIFIED' or source['sha256'] != artifact['sha256'] or source['actual_size'] != artifact['size']:
            raise ValueError('Copied-source manifest mismatch')
    print('PASS: all five captured artifacts independently SHA256 verified; no scientific computation.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    verify(parser.parse_args().snapshot)
