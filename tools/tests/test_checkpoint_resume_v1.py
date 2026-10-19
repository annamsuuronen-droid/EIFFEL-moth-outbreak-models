"""Synthetic only: no Hmsc, R, scientific inputs or historical paths are opened."""
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "eiffel_checkpoint_v1.py"
sys.path.insert(0, str(MODULE.parent))
import eiffel_checkpoint_v1 as cp


def panel():
    return {"sample_ids": ["synthetic_A_2020", "synthetic_B_2021"],
            "cv_year_folds": [1, 2], "response_sha256": "a" * 64,
            "offset_sha256": "b" * 64}


def specification():
    return {"run_id": "synthetic_run", "species": ["Lymantria monacha"],
            "mode": "predictive", "stage": "S1a",
            "inputs": {"fixture": hashlib.sha256(b"synthetic input").hexdigest()},
            "code": {"fixture_adapter": hashlib.sha256(b"synthetic code").hexdigest()},
            "software": {"R": "SYNTHETIC_NOT_USED", "Hmsc": "NOT_LOADED",
                         "dependencies": {"python": "stdlib_fixture"}},
            "model": {"response": "synthetic integer count", "offset": "log(effort_days/7)",
                      "distribution": "synthetic-only metadata", "priors": {"fixture": True},
                      "variables": ["fixture_weather"], "seeds": {"fixture": 7},
                      "profile": {"samples": 0, "model_calls": 0},
                      "preprocessing": "synthetic frozen contract", "random_levels": [],
                      "forecast_scope": "NOT_VALIDATED_SYNTHETIC"}}


def graph():
    # Predeclared decisions, NOT a new selection method. Four forward records
    # prove no implicit stop at the first/two groups; no metrics are optimized.
    kinds = [("fit_ref", "fit"), ("fit_cand", "fit"), ("cv", "evaluation"),
             ("pair", "ref_cand"), ("screen", "screening_decision"),
             ("confirm_rejected", "confirmation_decision"),
             ("confirm_accepted", "confirmation_decision"),
             ("forward_1", "forward_step"), ("forward_2", "forward_step"),
             ("forward_3", "forward_step"), ("forward_4", "forward_step"),
             ("backward", "backward_step")]
    tasks = []
    for name, kind in kinds:
        tasks.append({"task_id": name, "kind": kind,
                      "requires": [tasks[-1]["task_id"]] if tasks else [],
                      "contract": {"panel": panel()} if kind == "ref_cand" else
                                  {"fixture_decision": "KEEP_HISTORICAL_RULE"}})
    return tasks


def producer(counter, *, pause_run=None):
    def produce(attempt):
        counter.append(attempt.task_id)
        evidence = {"scientific_approval": False}
        if attempt.task_id == "pair":
            evidence.update(reference=panel(), candidate=panel())
        if attempt.task_id in {"screen", "confirm_accepted", "confirm_rejected"}:
            evidence["accepted"] = attempt.task_id != "confirm_rejected"
        (attempt.workdir / "result.json").write_bytes(cp.canonical({"fixture": attempt.task_id}))
        if pause_run is not None:
            pause_run.request_pause()
        return {"result.json": "json"}, evidence
    return produce


class Checkpoints(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="eiffel_checkpoint_synthetic_")
        self.parent = Path(self.tmp.name)
        input_file, code_file = self.parent / "fixture_input.txt", self.parent / "fixture_code.txt"
        input_file.write_bytes(b"synthetic input"); code_file.write_bytes(b"synthetic code")
        self.bindings = {"inputs": {"fixture": input_file}, "code": {"fixture_adapter": code_file}}
        self.spec, self.tasks = specification(), graph()
        self.run = cp.Run.create(self.parent / "run", self.spec, self.tasks, self.bindings)

    def tearDown(self):
        self.tmp.cleanup()  # Only this test's temporary synthetic tree.

    def finish(self, run):
        calls = []
        with run.writer() as w:
            for t in self.tasks:
                w.run_task(t["task_id"], producer(calls))
            results = [w.verified(t["task_id"])["evidence"] for t in self.tasks]
        return calls, results

    def test_uninterrupted_and_pause_resume_identical_decisions(self):
        calls, expected = self.finish(self.run)
        self.assertEqual(len(calls), len(self.tasks))
        other = cp.Run.create(self.parent / "paused_run", self.spec, self.tasks, self.bindings)
        before = []
        with other.writer() as w:
            w.run_task("fit_ref", producer(before, pause_run=other))
            self.assertEqual(other.status()["run_state"], "paused")
            with self.assertRaises(cp.Paused):
                w.run_task("fit_cand", producer(before))
        pause_id = other.pause_id()
        with other.writer() as w:
            with self.assertRaises(cp.Paused):
                w.run_task("fit_cand", producer(before))
            w.resume(pause_id)
        remaining, actual = self.finish(other)
        self.assertNotIn("fit_ref", remaining)
        self.assertEqual(expected, actual)
        self.assertIn("forward_4", remaining)
        self.assertIn("backward", remaining)
        self.assertEqual(before, ["fit_ref"])

    def test_reuse_never_calls_adapter(self):
        self.finish(self.run)
        calls, _ = self.finish(self.run)
        self.assertEqual(calls, [])

    def test_crash_before_publication_preserves_partial_and_requires_review(self):
        with self.run.writer() as w:
            attempt = w.begin("fit_ref")
            (attempt.workdir / "partial.bin").write_bytes(b"synthetic partial")
        with self.run.writer() as w:
            self.assertEqual(w.state("fit_ref")["state"], "needs_review")
            with self.assertRaises(cp.NeedsReview):
                w.run_task("fit_ref", producer([]))
            w.retry_after_review("fit_ref", attempt.attempt_id)
            w.run_task("fit_ref", producer([]))
            self.assertTrue(attempt.workdir.exists())
            self.assertNotEqual(w.state("fit_ref")["attempt_id"], attempt.attempt_id)

    def test_real_process_exit_releases_lock_not_running_state(self):
        program = """
import os,sys
sys.path.insert(0,sys.argv[1])
import eiffel_checkpoint_v1 as cp
p=cp.Path(sys.argv[2]); saved=cp.read_json(p/'RUN.json')
b={'inputs':{'fixture':p.parent/'fixture_input.txt'},'code':{'fixture_adapter':p.parent/'fixture_code.txt'}}
r=cp.Run(p,saved['spec'],saved['tasks'],b); w=r.writer(); a=w.begin('fit_ref')
(a.workdir/'partial.bin').write_bytes(b'synthetic')
os._exit(23)
"""
        result = subprocess.run([sys.executable, "-B", "-c", program, str(MODULE.parent),
                                 str(self.run.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 23, result.stderr)
        with self.run.writer() as w:
            self.assertEqual(w.state("fit_ref")["state"], "needs_review")

    def test_corrupt_artifact_or_manifest_refused_without_overwrite(self):
        for corrupt_manifest in (False, True):
            with self.subTest(manifest=corrupt_manifest):
                r = cp.Run.create(self.parent / ("corrupt_" + str(corrupt_manifest)), self.spec, self.tasks, self.bindings)
                with r.writer() as w:
                    w.run_task("fit_ref", producer([]))
                    aid = w.state("fit_ref")["attempt_id"]
                    folder = r.root / "tasks" / "fit_ref" / aid
                    target = folder / ("MANIFEST.json" if corrupt_manifest else "result.json")
                    target.write_bytes(b'{"tampered":true}')
                    with self.assertRaises(cp.NeedsReview):
                        w.run_task("fit_ref", producer([]))
                    self.assertEqual(target.read_bytes(), b'{"tampered":true}')
                    self.assertEqual(w.state("fit_ref")["state"], "needs_review")

    def test_changed_contracts_refused(self):
        for field in ("inputs", "code", "software", "model"):
            modified = copy.deepcopy(self.spec)
            if field in {"inputs", "code"}:
                key = next(iter(modified[field])); modified[field][key] = "f" * 64
            elif field == "software":
                modified[field]["Hmsc"] = "CHANGED"
            else:
                modified[field]["offset"] = "CHANGED"
            with self.subTest(field=field), self.assertRaises(cp.CheckpointError):
                cp.Run(self.run.root, modified, self.tasks, self.bindings)
        changed_graph = copy.deepcopy(self.tasks)
        changed_graph[-1]["contract"]["profile"] = "CHANGED"
        with self.assertRaises(cp.CheckpointError):
            cp.Run(self.run.root, self.spec, changed_graph, self.bindings)

    def test_changed_actual_source_bytes_refuse_reuse(self):
        with self.run.writer() as w:
            w.run_task("fit_ref", producer([]))
            for kind in ("inputs", "code"):
                path = next(iter(self.bindings[kind].values()))
                original = path.read_bytes()
                path.write_bytes(b"changed synthetic source")
                with self.subTest(kind=kind), self.assertRaises(cp.CheckpointError):
                    w.run_task("fit_ref", producer([]))
                path.write_bytes(original)
            self.assertEqual(w.run_task("fit_ref", producer([])), "REUSED")

    def test_source_change_during_task_cannot_publish(self):
        with self.run.writer() as w:
            a = w.begin("fit_ref"); (a.workdir / "x.json").write_text('{}')
            self.bindings["inputs"]["fixture"].write_bytes(b"changed during synthetic task")
            self.run.request_pause()  # Safe control remains available with changed input.
            self.assertEqual(self.run.status()["run_state"], "pause_requested")
            with self.assertRaises(cp.CheckpointError):
                w.complete(a, {"x.json": "json"})
            self.assertFalse((a.workdir.parent / a.attempt_id).exists())

    def test_dependency_blocks_incomplete_cv_and_confirmation(self):
        with self.run.writer() as w:
            for name in ("fit_ref", "fit_cand"):
                w.run_task(name, producer([]))
            attempt = w.begin("cv")
            (attempt.workdir / "fold_1.json").write_text('{"synthetic_fold":1}')
        with self.run.writer() as w:
            self.assertEqual(w.state("cv")["state"], "needs_review")
            with self.assertRaises(cp.CheckpointError):
                w.begin("pair")
            self.assertIsNone(w.verified("pair"))

    def test_failed_confirmation_not_decision(self):
        def failure(attempt):
            raise RuntimeError("synthetic interrupted confirmation")
        with self.run.writer() as w:
            for task in self.tasks:
                if task["task_id"] == "confirm_rejected":
                    break
                w.run_task(task["task_id"], producer([]))
            with self.assertRaises(RuntimeError):
                w.run_task("confirm_rejected", failure)
            self.assertEqual(w.state("confirm_rejected")["state"], "needs_review")
            with self.assertRaises(cp.CheckpointError):
                w.begin("confirm_accepted")

    def test_rejected_confirmation_complete_and_reused(self):
        self.finish(self.run)
        with self.run.writer() as w:
            result = w.verified("confirm_rejected")
            self.assertIs(result["evidence"]["accepted"], False)
            self.assertIs(result["scientific_approval"], False)
            self.assertEqual(w.run_task("confirm_rejected", producer([])), "REUSED")

    def test_panel_order_folds_and_observations_must_match(self):
        cp.validate_pair(panel(), panel())
        for key, value in [("sample_ids", list(reversed(panel()["sample_ids"]))),
                           ("sample_ids", ["wrong", "panel"]),
                           ("cv_year_folds", [2, 1]), ("offset_sha256", "f" * 64),
                           ("response_sha256", "f" * 64)]:
            p = panel(); p[key] = value
            with self.subTest(key=key), self.assertRaises(cp.CheckpointError):
                cp.validate_pair(panel(), p)
        with self.run.writer() as w:
            for name in ("fit_ref", "fit_cand", "cv"):
                w.run_task(name, producer([]))
            a = w.begin("pair"); (a.workdir / "x.json").write_text('{}')
            wrong = panel(); wrong["cv_year_folds"] = [2, 1]
            with self.assertRaises(cp.CheckpointError):
                w.complete(a, {"x.json": "json"}, {"reference": panel(), "candidate": wrong})
            self.assertFalse((a.workdir.parent / a.attempt_id).exists())

    def test_single_writer_in_same_and_other_process(self):
        with self.run.writer():
            with self.assertRaises(cp.CheckpointError):
                self.run.writer()
            program = """
import sys
sys.path.insert(0,sys.argv[1]); import eiffel_checkpoint_v1 as cp
p=cp.Path(sys.argv[2]); x=cp.read_json(p/'RUN.json')
b={'inputs':{'fixture':p.parent/'fixture_input.txt'},'code':{'fixture_adapter':p.parent/'fixture_code.txt'}}
r=cp.Run(p,x['spec'],x['tasks'],b)
try: r.writer()
except cp.CheckpointError: sys.exit(0)
sys.exit(5)
"""
            result = subprocess.run([sys.executable, "-B", "-c", program, str(MODULE.parent),
                                     str(self.run.root)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_stale_worker_cannot_publish_after_owner_changes(self):
        old = self.run.writer(); a = old.begin("fit_ref")
        (a.workdir / "x.json").write_text('{}')
        old.close()
        with self.run.writer() as current:
            with self.assertRaises(cp.CheckpointError):
                old.complete(a, {"x.json": "json"})
            self.assertFalse((a.workdir.parent / a.attempt_id).exists())
            self.assertEqual(current.state("fit_ref")["state"], "needs_review")

    def test_interruption_during_publish_not_accepted_as_complete(self):
        with self.run.writer() as w:
            a = w.begin("fit_ref"); (a.workdir / "x.json").write_text('{}')
            with patch.object(cp.os, "rename", side_effect=OSError("synthetic rename failure")):
                with self.assertRaises(OSError):
                    w.complete(a, {"x.json": "json"})
            self.assertEqual(w.state("fit_ref")["state"], "running")
        with self.run.writer() as w:
            self.assertEqual(w.state("fit_ref")["state"], "needs_review")

    def test_published_before_state_commit_requires_explicit_review(self):
        with self.run.writer() as w:
            a = w.begin("fit_ref"); (a.workdir / "x.json").write_text('{}')
            with patch.object(w, "_state", side_effect=OSError("synthetic crash after publication")):
                with self.assertRaises(OSError):
                    w.complete(a, {"x.json": "json"})
        final = a.workdir.parent / a.attempt_id
        h = cp.digest(cp.read_json(final / "MANIFEST.json"))
        with self.run.writer() as w:
            self.assertEqual(w.state("fit_ref")["state"], "needs_review")
            with self.assertRaises(cp.CheckpointError):
                w.adopt_after_review("fit_ref", a.attempt_id, "0" * 64)
            w.adopt_after_review("fit_ref", a.attempt_id, h)
            self.assertIsNotNone(w.verified("fit_ref"))

    def test_dependency_replacement_invalidates_child_checkpoint(self):
        with self.run.writer() as w:
            w.run_task("fit_ref", producer([])); w.run_task("fit_cand", producer([]))
            original = w.state("fit_ref")
            # Synthetic operator review of an upstream result; old artifacts retained.
            w._state("fit_ref", {**original, "state": "needs_review"})
            w.retry_after_review("fit_ref", original["attempt_id"])
            w.run_task("fit_ref", producer([]))
            with self.assertRaises(cp.NeedsReview):
                w.verified("fit_cand")

    def test_portable_names_relocation_and_native_root(self):
        self.finish(self.run)
        moved = self.parent / "relocated"
        shutil.copytree(self.run.root, moved)
        relocated = cp.Run(moved, self.spec, self.tasks, self.bindings)
        calls, _ = self.finish(relocated)
        self.assertEqual(calls, [])
        for name in ("../x", "a/b", "a\\b", "C:\\x", "\\\\host\\x", "NUL.txt",
                     "a:stream", "trailing.", "MANIFEST.json"):
            with self.subTest(name=name), self.assertRaises(cp.CheckpointError):
                cp.artifact_name(name)
        with self.assertRaises(cp.CheckpointError):
            cp.Run.create("relative", self.spec, self.tasks, self.bindings)
        with self.assertRaises(FileExistsError):
            cp.Run.create(self.run.root, self.spec, self.tasks, self.bindings)

    def test_symlink_refusal(self):
        target = self.parent / "target.json"; target.write_text('{}')
        link = self.parent / "link.json"
        try:
            link.symlink_to(target)
        except (OSError, NotImplementedError):
            self.skipTest("Symlink creation not permitted on this Windows runner")
        with self.assertRaises(cp.CheckpointError):
            cp.sha256_file(link)

    def test_resources_admission_no_silent_defaults(self):
        for resources, observations in [
            (cp.Resources(max_parallel_tasks=2), {}),
            (cp.Resources(memory_budget_bytes=100), {}),
            (cp.Resources(memory_budget_bytes=100), {"memory_bytes": 100}),
            (cp.Resources(task_time_budget_s=2), {"estimated_s": 3}),
            (cp.Resources(), {"estimated_s": 3, "remaining_s": 10}),
            (cp.Resources(checkpoint_margin_s=2), {"estimated_s": 9, "remaining_s": 10}),
            (cp.Resources(min_free_bytes=10**30), {}),
            (cp.Resources(task_time_budget_s=float("nan")), {}),
        ]:
            with self.subTest(resources=resources), self.run.writer() as w:
                with self.assertRaises(cp.CheckpointError):
                    w.begin("fit_ref", resources, **observations)
                self.assertEqual(w.state("fit_ref")["state"], "pending")

    def test_duplicate_json_nonfinite_and_missing_contract_refused(self):
        p = self.parent / "invalid.json"
        for text in ('{"x":1,"x":2}', '{"x":NaN}'):
            p.write_text(text)
            with self.assertRaises(cp.CheckpointError):
                cp.read_json(p)
        bad = copy.deepcopy(self.spec); del bad["model"]["offset"]
        with self.assertRaises(cp.CheckpointError):
            cp.Run.create(self.parent / "bad", bad, self.tasks, self.bindings)

    def test_no_science_certification_and_empty_artifact(self):
        with self.run.writer() as w:
            a = w.begin("fit_ref"); (a.workdir / "x.json").write_text('{}')
            with self.assertRaises(cp.CheckpointError):
                w.complete(a, {"x.json": "json"}, {"scientific_approval": True})
            (a.workdir / "x.json").write_bytes(b"")
            with self.assertRaises(cp.CheckpointError):
                w.complete(a, {"x.json": "json"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
