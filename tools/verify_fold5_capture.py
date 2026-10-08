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

def verified_bytes(path, record, allow_git_eol=False):
    data = path.read_bytes()
    expected = (int(record['size']), record['sha256'], record['md5'])
    def identity(value):
        return len(value), hashlib.sha256(value).hexdigest(), hashlib.md5(value).hexdigest()
    if identity(data) == expected:
        return data, 'EXACT_GIT_BYTES'
    if allow_git_eol and path.suffix.lower() in ('.csv', '.csv2', '.md'):
        lf = data.replace(b'\r\n', b'\n')
        for mode, candidate in [('VERIFIED_LF_RESTORATION', lf), ('VERIFIED_CRLF_RESTORATION', lf.replace(b'\n', b'\r\n'))]:
            if identity(candidate) == expected:
                return candidate, mode
    raise ValueError('Artifact SHA256/MD5/size mismatch: '+str(path))

def verify(snapshot, allow_git_eol=False, report=None):
    snapshot = Path(snapshot).resolve(strict=True)
    inventory = rows(snapshot/'artifact_manifest.csv')
    names = [r['relative_path'] for r in inventory]
    if len(names) != len(EXPECTED) or set(names) != EXPECTED:
        raise ValueError('Unexpected artifact allow-list')
    restored = {}
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
        actual, mode = verified_bytes(path,record,allow_git_eol)
        restored[relative] = actual
        if report is not None:
            report.append(dict(path=str(path),transport_status=mode,git_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source_sha256=record['sha256'],source_md5=record['md5'],source_size=record['size']))
    sources = rows(snapshot/'source_manifest.csv')
    if len(sources) != 5:
        raise ValueError('Unexpected source count')
    for source in sources[:2]:
        artifact = next(r for r in inventory if r['relative_path'] == source['source_relative_path'])
        if source['action'] != 'COPY' or source['status'] != 'COPIED_SHA256_VERIFIED' or source['sha256'] != artifact['sha256'] or source['actual_size'] != artifact['size']:
            raise ValueError('Copied-source manifest mismatch')
    print('PASS: all five captured artifacts verified against source SHA256/MD5/size; no scientific computation.')
    return restored

AUDIT_EXPECTED = {'recomputed_fold_metrics.csv', 'pooled_five_fold_metrics.csv',
                  'equal_weight_fold_metrics.csv', 'fold_coverage.csv', 'STATUS.csv',
                  'INPUT_ARTIFACT_MANIFEST.csv', 'README.md'}

def verify_audit(directory, allow_git_eol=False, report=None):
    directory = Path(directory).resolve(strict=True)
    inventory = rows(directory/'AUDIT_ARTIFACT_MANIFEST.csv')
    if len(inventory) != 7 or {r['relative_path'] for r in inventory} != AUDIT_EXPECTED:
        raise ValueError('Unexpected audit manifest')
    restored = {}
    for record in inventory:
        path = directory/record['relative_path']
        if path.is_symlink():
            raise ValueError('Audit symlink forbidden')
        data, mode = verified_bytes(path,record,allow_git_eol)
        restored[record['relative_path']] = data
        if report is not None:
            report.append(dict(path=str(path),transport_status=mode,git_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),source_sha256=record['sha256'],source_md5=record['md5'],source_size=record['size']))
    print('PASS: all seven published audit artifacts verified against source SHA256/MD5/size.')
    return restored

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--audit', type=Path)
    parser.add_argument('--allow-git-eol-normalization', action='store_true', help='Accept only deterministic LF/CRLF restoration matching all recorded hashes and sizes.')
    parser.add_argument('--restore-to', type=Path, help='Fresh temporary staging directory for hash-exact source bytes; requires --audit.')
    parser.add_argument('--report', type=Path, help='Fresh CSV transport verification report.')
    args = parser.parse_args()
    report = []
    restored = verify(args.snapshot,args.allow_git_eol_normalization,report)
    audit = verify_audit(args.audit,args.allow_git_eol_normalization,report) if args.audit is not None else None
    if audit is not None:
        source_manifest = (args.snapshot/'artifact_manifest.csv').read_bytes().replace(b'\r\n',b'\n')
        if source_manifest != audit['INPUT_ARTIFACT_MANIFEST.csv'].replace(b'\r\n',b'\n'):
            raise ValueError('Archived input manifest differs from captured manifest')
    if args.restore_to is not None:
        if audit is None:
            raise ValueError('--restore-to requires --audit')
        args.restore_to.mkdir(parents=True,exist_ok=False)
        for relative, data in restored.items():
            target = args.restore_to/relative
            target.parent.mkdir(parents=True,exist_ok=True)
            with target.open('xb') as handle:
                handle.write(data)
        with (args.restore_to/'artifact_manifest.csv').open('xb') as handle:
            handle.write(audit['INPUT_ARTIFACT_MANIFEST.csv'])
    if args.report is not None:
        with args.report.open('x',encoding='utf-8',newline='') as handle:
            writer = csv.DictWriter(handle,fieldnames=list(report[0]));writer.writeheader();writer.writerows(report)
