"""Synthetic integrity tests; never uses Windows scientific roots."""
import csv
import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('verify_fold5', Path(__file__).parents[1]/'verify_fold5_capture.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CaptureHashes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for relative in module.EXPECTED - {'source_manifest.csv'}:
            file = self.root/relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('SYNTHETIC FIXTURE ONLY\n')
        source_records = []
        for relative in sorted(r for r in module.EXPECTED if r.endswith('.csv2')):
            data = (self.root/relative).read_bytes()
            source_records.append(dict(source_relative_path=relative,action='COPY',status='COPIED_SHA256_VERIFIED',sha256=hashlib.sha256(data).hexdigest(),actual_size=str(len(data))))
        source_records += [dict(source_relative_path='synthetic-extraction',action='EXTRACT',status='READ_ONLY_VERIFIED_NOT_COPIED',sha256='0'*64,actual_size='1')]*3
        self.write('source_manifest.csv', source_records)
        self.inventory = []
        for relative in sorted(module.EXPECTED):
            data = (self.root/relative).read_bytes()
            self.inventory.append(dict(relative_path=relative,size=len(data),sha256=hashlib.sha256(data).hexdigest(),md5=hashlib.md5(data).hexdigest()))
        self.write('artifact_manifest.csv', self.inventory)
    def tearDown(self):
        self.tmp.cleanup()
    def write(self, path, records):
        with (self.root/path).open('w', newline='',encoding='utf-8') as handle:
            writer=csv.DictWriter(handle,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
    def test_success(self):
        module.verify(self.root)
    def test_corrupted_bytes(self):
        (self.root/'checkpoint_verification.csv').write_text('CORRUPTED')
        with self.assertRaises(ValueError): module.verify(self.root)
    def test_tampered_hash(self):
        self.inventory[0]['sha256']='0'*64;self.write('artifact_manifest.csv',self.inventory)
        with self.assertRaises(ValueError): module.verify(self.root)
    def test_traversal(self):
        self.inventory[0]['relative_path']='../escape.csv';self.write('artifact_manifest.csv',self.inventory)
        with self.assertRaises(ValueError): module.verify(self.root)
    def audit_fixture(self):
        directory = self.root/'audit'
        directory.mkdir()
        records = []
        for name in sorted(module.AUDIT_EXPECTED):
            data = b'SYNTHETIC TEST FIXTURE ONLY'
            (directory/name).write_bytes(data)
            records.append(dict(relative_path=name,size=len(data),sha256=hashlib.sha256(data).hexdigest(),md5=hashlib.md5(data).hexdigest()))
        with (directory/'AUDIT_ARTIFACT_MANIFEST.csv').open('w', newline='') as handle:
            writer=csv.DictWriter(handle,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
        return directory
    def test_audit_integrity(self):
        module.verify_audit(self.audit_fixture())
    def test_audit_corruption(self):
        directory = self.audit_fixture()
        (directory/'STATUS.csv').write_bytes(b'CORRUPTED')
        with self.assertRaises(ValueError): module.verify_audit(directory)
    def test_transport_normalization(self):
        data = b'SOURCE WINDOWS TEXT\r\n'
        path = self.root/'checkpoint_verification.csv'
        path.write_bytes(data.replace(b'\r\n',b'\n'))
        record = dict(size=len(data),sha256=hashlib.sha256(data).hexdigest(),md5=hashlib.md5(data).hexdigest())
        with self.assertRaises(ValueError): module.verified_bytes(path,record)
        actual, status = module.verified_bytes(path,record,True)
        self.assertEqual(actual,data);self.assertEqual(status,'VERIFIED_CRLF_RESTORATION')
    def test_transport_cannot_hide_corruption(self):
        data = b'SOURCE WINDOWS TEXT\r\n'
        path = self.root/'checkpoint_verification.csv';path.write_bytes(b'CORRUPTED\n')
        record = dict(size=len(data),sha256=hashlib.sha256(data).hexdigest(),md5=hashlib.md5(data).hexdigest())
        with self.assertRaises(ValueError): module.verified_bytes(path,record,True)
    def test_duplicate(self):
        self.inventory.append(self.inventory[0]);self.write('artifact_manifest.csv',self.inventory)
        with self.assertRaises(ValueError): module.verify(self.root)

if __name__ == '__main__': unittest.main()
