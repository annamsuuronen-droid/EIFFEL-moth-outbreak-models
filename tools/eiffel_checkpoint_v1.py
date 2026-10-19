"""Local, single-writer checkpoints. No scientific backend or executable CLI.

Importing this module performs no IO. See project_state/checkpoint_resume_v1.
Only a reviewed adapter may supply scientific task implementations in the future.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import stat
import time
import uuid
from dataclasses import dataclass
from typing import Callable, Mapping


class CheckpointError(RuntimeError):
    pass


class Paused(CheckpointError):
    pass


class NeedsReview(CheckpointError):
    pass


def canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=False, allow_nan=False).encode("utf-8")


def digest(value) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def identifier(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", value):
        raise CheckpointError("Invalid logical identifier")
    return value


def artifact_name(value: str) -> str:
    if (not isinstance(value, str) or PureWindowsPath(value).drive or
            not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,119}", value) or
            value.endswith(".") or value == "MANIFEST.json" or
            value.split(".")[0].upper() in
            {"CON", "PRN", "AUX", "NUL", *[f"COM{i}" for i in range(1, 10)],
             *[f"LPT{i}" for i in range(1, 10)]}):
        raise CheckpointError("Artifact must have an ordinary portable leaf filename")
    return value


def ordinary(path: Path, *, file=False):
    """Reject links/junctions in an owned tree, including existing ancestors.

    This is not an adversarial-filesystem sandbox: the root must be private and
    stable. OS locks coordinate cooperating processes, not outside file editors.
    """
    path = Path(path)
    for part in reversed((path, *path.parents)):
        s = part.lstat()
        if stat.S_ISLNK(s.st_mode) or getattr(s, "st_file_attributes", 0) & 0x400:
            raise CheckpointError("Reparse points/symlinks are forbidden")
    if file and not stat.S_ISREG(path.lstat().st_mode):
        raise CheckpointError("Expected regular file")


def sha256_file(path: Path) -> str:
    ordinary(path, file=True)
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_json(path: Path):
    ordinary(path, file=True)
    if path.stat().st_size > 4 * 1024 * 1024:
        raise CheckpointError("JSON metadata exceeds reviewed 4 MiB bound")

    def unique(pairs):
        out = {}
        for k, v in pairs:
            if k in out:
                raise CheckpointError("Duplicate JSON key")
            out[k] = v
        return out

    def invalid(_):
        raise CheckpointError("Nonfinite JSON value")

    with path.open(encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=unique, parse_constant=invalid)


def _sync_directory(path: Path):
    # Windows has no portable stdlib directory fsync. Network FS durability is
    # deployment-specific even when this call succeeds. Do not certify power loss.
    if os.name != "nt":
        fd = os.open(path, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def write_json(path: Path, value, *, replace=False):
    ordinary(path.parent)
    data = canonical(value)
    if len(data) > 4 * 1024 * 1024:
        raise CheckpointError("JSON metadata exceeds reviewed bound")
    temporary = path.parent / (".part_" + uuid.uuid4().hex)
    with temporary.open("xb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    # All publications are under the writer/admission lock. No replacement of
    # immutable result records. Interrupted temporary files are preserved.
    if path.exists() and not replace:
        raise CheckpointError("Refusing existing immutable record")
    if replace:
        ordinary(path, file=True) if path.exists() else None
        os.replace(temporary, path)
    else:
        os.rename(temporary, path)
    _sync_directory(path.parent)


class FileLock:
    """Nonblocking kernel lock; never unlink a lock inode or steal a live lock."""
    def __init__(self, path: Path):
        ordinary(path, file=True)
        self.stream = path.open("r+b")
        try:
            if os.name == "nt":
                import msvcrt
                self.stream.seek(0)
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.stream.close()
            raise CheckpointError("Another process holds the checkpoint lock") from error

    def close(self):
        if not self.stream.closed:
            if os.name == "nt":
                import msvcrt
                self.stream.seek(0)
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_UN)
            self.stream.close()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def validate_pair(reference, candidate):
    """Exact rows/order/folds AND observed-response/offset identity, not just N."""
    required = {"sample_ids", "cv_year_folds", "response_sha256", "offset_sha256"}
    for panel in (reference, candidate):
        if not isinstance(panel, dict) or set(panel) != required:
            raise CheckpointError("Panel evidence needs explicit keys, order, folds, Y and offset hashes")
        ids, folds = panel["sample_ids"], panel["cv_year_folds"]
        if (not isinstance(ids, list) or not ids or
                any(not isinstance(x, str) or not x for x in ids) or
                len(set(ids)) != len(ids) or not isinstance(folds, list) or
                len(folds) != len(ids) or
                any(type(f) is not int or f < 1 for f in folds)):
            raise CheckpointError("Invalid ordered panel/fold map")
        for key in ("response_sha256", "offset_sha256"):
            if not re.fullmatch(r"[a-f0-9]{64}", panel[key]):
                raise CheckpointError("Invalid scientific identity hash")
    if canonical(reference) != canonical(candidate):
        raise CheckpointError("REF/CAND rows, order, folds, response or offset differ")


KINDS = {"fit", "evaluation", "ref_cand", "screening_decision",
         "confirmation_decision", "forward_step", "backward_step"}


def validate_spec(spec, tasks):
    if set(spec) != {"run_id", "species", "mode", "stage", "inputs", "code", "software", "model"}:
        raise CheckpointError("Explicit run compatibility contract required")
    identifier(spec["run_id"])
    if (spec["stage"] != "S1a" or spec["mode"] not in {"explanatory", "predictive"} or
            not isinstance(spec["species"], list) or not spec["species"] or
            any(not isinstance(s, str) or not s for s in spec["species"])):
        raise CheckpointError("Explicit species/mode/S1a scope required")
    for field in ("inputs", "code"):
        if not isinstance(spec[field], dict) or not spec[field]:
            raise CheckpointError("Input/code fingerprints required")
        for name, value in spec[field].items():
            identifier(name)
            if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
                raise CheckpointError("Expected SHA-256")
    if (not isinstance(spec["software"], dict) or
            not {"R", "Hmsc", "dependencies"} <= spec["software"].keys() or
            any(not spec["software"][k] for k in ("R", "Hmsc", "dependencies"))):
        raise CheckpointError("Software/dependency identity required")
    if not isinstance(spec["model"], dict) or not {
        "response", "offset", "distribution", "priors", "variables", "seeds",
        "profile", "preprocessing", "random_levels", "forecast_scope"
    } <= spec["model"].keys():
        raise CheckpointError("Model/offset/seed/profile compatibility contract missing")
    for key in ("response", "offset", "distribution", "preprocessing", "forecast_scope"):
        if not isinstance(spec["model"][key], str) or not spec["model"][key].strip():
            raise CheckpointError("Explicit model definitions required")
    for key in ("priors", "seeds", "profile"):
        if not isinstance(spec["model"][key], dict) or not spec["model"][key]:
            raise CheckpointError("Explicit priors/seeds/profile required")
    for key in ("variables", "random_levels"):
        if not isinstance(spec["model"][key], list):
            raise CheckpointError("Explicit variable/random-level lists required")
    if not isinstance(tasks, list) or not tasks:
        raise CheckpointError("An explicit task graph is required")
    seen = set()
    for task in tasks:
        if set(task) != {"task_id", "kind", "requires", "contract"}:
            raise CheckpointError("Invalid task descriptor")
        name = identifier(task["task_id"])
        if (name in seen or task["kind"] not in KINDS or
                not isinstance(task["requires"], list) or
                len(set(task["requires"])) != len(task["requires"]) or
                not set(task["requires"]) <= seen or not isinstance(task["contract"], dict)):
            raise CheckpointError("Graph must have unique tasks in dependency order")
        if task["kind"] == "ref_cand":
            panel = task["contract"].get("panel")
            validate_pair(panel, panel)
        seen.add(name)
    canonical([spec, tasks])  # Reject non-JSON/nonfinite values before writing.


@dataclass(frozen=True)
class Resources:
    """Admission only. No automatic OS memory cap, monitoring or cancellation."""
    max_parallel_tasks: int = 1  # Architectural single-worker bound, not a hardware estimate.
    memory_budget_bytes: int | None = None
    min_free_bytes: int | None = None
    task_time_budget_s: float | None = None
    checkpoint_margin_s: float | None = None

    def check(self, root, *, memory_bytes=None, estimated_s=None, remaining_s=None):
        if self.max_parallel_tasks != 1:
            raise CheckpointError("v1 permits one heavy task at a time")
        for v in (self.memory_budget_bytes, self.min_free_bytes, self.task_time_budget_s,
                  self.checkpoint_margin_s, memory_bytes, estimated_s, remaining_s):
            if v is not None and (type(v) not in (int, float) or not math.isfinite(v) or v < 0):
                raise CheckpointError("Invalid resource budget/observation")
        if self.memory_budget_bytes is not None and (
                memory_bytes is None or memory_bytes >= self.memory_budget_bytes):
            raise CheckpointError("Memory observation missing or budget exhausted")
        if self.min_free_bytes is not None and shutil.disk_usage(root).free < self.min_free_bytes:
            raise CheckpointError("Disk budget exhausted")
        if self.task_time_budget_s is not None and (
                estimated_s is None or estimated_s > self.task_time_budget_s):
            raise CheckpointError("Task duration missing or exceeds budget")
        if remaining_s is not None and (
                estimated_s is None or self.checkpoint_margin_s is None or
                estimated_s + self.checkpoint_margin_s > remaining_s):
            raise CheckpointError("Insufficient/unknown remaining walltime margin")


class Run:
    def __init__(self, root, spec, tasks, source_bindings):
        self.root = Path(root)
        if not self.root.is_absolute():
            raise CheckpointError("Use an explicit native absolute checkpoint root")
        ordinary(self.root)
        validate_spec(spec, tasks)
        self.spec, self.tasks = json.loads(canonical(spec)), json.loads(canonical(tasks))
        self.source_bindings = source_bindings
        self.engine_sha256 = sha256_file(Path(__file__))
        self.contract_sha256 = digest([self.spec, self.tasks, self.engine_sha256])
        self.check_compatibility()

    def check_compatibility(self):
        # Explicit reviewed paths only: no searching or source reconstruction.
        if not isinstance(self.source_bindings, dict) or set(self.source_bindings) != {"inputs", "code"}:
            raise CheckpointError("Explicit current input/code path bindings required")
        for kind in ("inputs", "code"):
            if set(self.source_bindings[kind]) != set(self.spec[kind]):
                raise CheckpointError("Source path bindings differ from contract")
            for key, path in self.source_bindings[kind].items():
                if not Path(path).is_absolute():
                    raise CheckpointError("Source bindings require native absolute paths")
                if sha256_file(Path(path)) != self.spec[kind][key]:
                    raise CheckpointError("Current source bytes differ from reviewed contract")
        if sha256_file(Path(__file__)) != self.engine_sha256:
            raise CheckpointError("Checkpoint engine changed")
        saved = read_json(self.root / "RUN.json")
        if saved != {"schema": 1, "spec": self.spec, "tasks": self.tasks,
                     "engine_sha256": self.engine_sha256,
                     "contract_sha256": self.contract_sha256}:
            raise CheckpointError("Run input/code/settings/software/graph incompatibility")

    @classmethod
    def create(cls, root, spec, tasks, source_bindings):
        validate_spec(spec, tasks)
        root = Path(root)
        if not root.is_absolute():
            raise CheckpointError("Absolute root required")
        ordinary(root.parent)
        root.mkdir(mode=0o700, exist_ok=False)  # Never initialize an existing historical tree.
        for name in ("tasks", "pause_requests", "resume_ack"):
            (root / name).mkdir()
        for name in (".writer.lock", ".admission.lock"):
            with (root / name).open("xb") as stream:
                stream.write(b"0")
                stream.flush()
                os.fsync(stream.fileno())
        engine_hash = sha256_file(Path(__file__))
        write_json(root / "RUN.json", {"schema": 1, "spec": spec, "tasks": tasks,
                                      "engine_sha256": engine_hash,
                                      "contract_sha256": digest([spec, tasks, engine_hash])})
        run = cls(root, spec, tasks, source_bindings)
        for task in tasks:
            p = root / "tasks" / task["task_id"]
            p.mkdir()
            write_json(p / "STATE.json", {"state": "pending", "attempt_id": None})
        return run

    def writer(self):
        return Writer(self)

    def request_pause(self):
        # A safe stop request must remain possible if a source changes mid-task.
        # New work/publication will independently fail its compatibility checks.
        with FileLock(self.root / ".admission.lock"):
            request = {"request_id": uuid.uuid4().hex, "run_id": self.spec["run_id"],
                       "at": time.time()}
            write_json(self.root / "pause_requests" / (request["request_id"] + ".json"), request)
            write_json(self.root / "PAUSE.json", request, replace=True)
            return request["request_id"]

    def pause_id(self):
        p = self.root / "PAUSE.json"
        if not p.exists():
            return None
        request = read_json(p)
        if request.get("run_id") != self.spec["run_id"]:
            raise CheckpointError("Pause request belongs to another run")
        token = identifier(request["request_id"])
        ack = self.root / "resume_ack" / (token + ".json")
        if ack.exists():
            if read_json(ack).get("request_id") != token:
                raise CheckpointError("Invalid resume acknowledgement")
            return None
        return token

    def status(self):
        states = {t["task_id"]: read_json(self.root / "tasks" / t["task_id"] / "STATE.json")["state"]
                  for t in self.tasks}
        active = "running" in states.values()
        return {"run_state": ("pause_requested" if active else "paused") if self.pause_id()
                else "complete" if all(s == "complete" for s in states.values()) else "ready",
                "tasks": states, "integrity_verified": False, "scientific_approval": False}


@dataclass(frozen=True)
class Attempt:
    task_id: str
    attempt_id: str
    workdir: Path
    owner: str


class Writer:
    def __init__(self, run: Run):
        run.check_compatibility()
        self.run = run
        self.root = run.root
        self.pid = os.getpid()
        self.token = uuid.uuid4().hex
        self.active = False
        self.lock = FileLock(self.root / ".writer.lock")
        try:
            self.active = True
            write_json(self.root / "OWNER.json", {"token": self.token, "pid": self.pid}, replace=True)
            for task in run.tasks:
                state = self.state(task["task_id"])
                if state["state"] == "running":
                    self._state(task["task_id"], {**state, "state": "needs_review",
                                                "reason": "previous_writer_left_running"})
        except BaseException:
            self.close()
            raise

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        self.active = False
        self.lock.close()

    def assert_owner(self):
        if (not self.active or self.pid != os.getpid() or self.lock.stream.closed or
                read_json(self.root / "OWNER.json")["token"] != self.token):
            raise CheckpointError("Stale/foreign writer cannot mutate or publish")

    def task(self, task_id):
        identifier(task_id)
        for task in self.run.tasks:
            if task["task_id"] == task_id:
                return task
        raise CheckpointError("Task is not in reviewed graph")

    def state(self, task_id):
        self.task(task_id)
        return read_json(self.root / "tasks" / task_id / "STATE.json")

    def _state(self, task_id, state):
        self.assert_owner()
        write_json(self.root / "tasks" / task_id / "STATE.json", state, replace=True)

    def _manifest(self, task, attempt_id):
        directory = self.root / "tasks" / task["task_id"] / identifier(attempt_id)
        manifest = read_json(directory / "MANIFEST.json")
        if (set(manifest) != {"task_sha256", "run_sha256", "attempt_id", "artifacts", "evidence",
                              "execution",
                              "dependency_manifests",
                              "technical_complete", "scientific_approval"} or
                manifest["task_sha256"] != digest(task) or
                manifest["run_sha256"] != self.run.contract_sha256 or
                manifest["attempt_id"] != attempt_id or
                manifest["technical_complete"] is not True or
                manifest["scientific_approval"] is not False or not manifest["artifacts"]):
            raise CheckpointError("Checkpoint manifest incompatible/incomplete")
        artifacts = manifest["artifacts"]
        expected = {"MANIFEST.json", *artifacts}
        if {p.name for p in directory.iterdir()} != expected:
            raise CheckpointError("Checkpoint directory membership differs")
        for name, record in artifacts.items():
            artifact_name(name)
            p = directory / name
            if p.stat().st_size != record["bytes"] or sha256_file(p) != record["sha256"]:
                raise CheckpointError("Checkpoint artifact missing/corrupt")
            self._structure(p, record["kind"])
        self._evidence(task, manifest["evidence"])
        if set(manifest["dependency_manifests"]) != set(task["requires"]):
            raise CheckpointError("Incomplete dependency bindings")
        return manifest

    def verified(self, task_id):
        self.assert_owner()
        self.run.check_compatibility()
        task, state = self.task(task_id), self.state(task_id)
        if state["state"] != "complete":
            return None
        try:
            manifest = self._manifest(task, state["attempt_id"])
            if digest(manifest) != state["manifest_sha256"]:
                raise CheckpointError("Manifest identity differs from committed state")
            for dependency in task["requires"]:
                parent = self.verified(dependency)
                if parent is None or digest(parent) != manifest["dependency_manifests"][dependency]:
                    raise CheckpointError("Checkpoint dependency unavailable")
            return manifest
        except (OSError, ValueError, KeyError, TypeError, CheckpointError) as error:
            self._state(task_id, {**state, "state": "needs_review", "reason": "integrity_or_dependency"})
            raise NeedsReview("Completed checkpoint failed verification") from error

    def begin(self, task_id, resources=Resources(), **observations):
        self.assert_owner()
        self.run.check_compatibility()
        task = self.task(task_id)
        with FileLock(self.root / ".admission.lock"):
            if self.run.pause_id():
                raise Paused("Pause requested; no new task admitted")
            if any(self.state(t["task_id"])["state"] == "running" for t in self.run.tasks):
                raise CheckpointError("A task is already running")
            state = self.state(task_id)
            if state["state"] != "pending":
                raise NeedsReview("Task is not pending; verify or explicitly review it")
            for dep in task["requires"]:
                if self.verified(dep) is None:
                    raise CheckpointError("Unfinished dependency")
            resources.check(self.root, **observations)
            aid = uuid.uuid4().hex
            stage = self.root / "tasks" / task_id / (aid + ".stage")
            stage.mkdir(exist_ok=False)
            self._state(task_id, {"state": "running", "attempt_id": aid, "owner": self.token,
                                  "started_at": time.time(), "resources": resources.__dict__,
                                  "observations": observations})
            return Attempt(task_id, aid, stage, self.token)

    @staticmethod
    def _structure(path, kind):
        ordinary(path, file=True)
        if path.stat().st_size == 0:
            raise CheckpointError("Empty artifact")
        if kind == "json":
            if not isinstance(read_json(path), (dict, list)):
                raise CheckpointError("JSON artifact needs object/array structure")
        elif kind != "opaque":
            raise CheckpointError("Only JSON or opaque adapter output supported")
        # Opaque files are only checked as nonempty regular bytes. This is NOT
        # validation of an Hmsc object; adapter-specific schema review is pending.

    @staticmethod
    def _evidence(task, evidence):
        if not isinstance(evidence, dict):
            raise CheckpointError("Task evidence must be an object")
        if task["kind"] == "ref_cand":
            validate_pair(evidence.get("reference"), evidence.get("candidate"))
            if evidence["reference"] != task["contract"]["panel"]:
                raise CheckpointError("Pair differs from planned panel")
        if task["kind"] in {"screening_decision", "confirmation_decision"}:
            if type(evidence.get("accepted")) is not bool:
                raise CheckpointError("Frozen adapter must record explicit accepted/rejected decision")
        if evidence.get("scientific_approval", False) is not False:
            raise CheckpointError("Technical checkpoints cannot certify science")

    def complete(self, attempt: Attempt, artifacts: Mapping[str, str], evidence=None):
        self.assert_owner()
        self.run.check_compatibility()
        task = self.task(attempt.task_id)
        state = self.state(attempt.task_id)
        expected_stage = self.root / "tasks" / attempt.task_id / (attempt.attempt_id + ".stage")
        if (attempt.owner != self.token or state["state"] != "running" or
                state["attempt_id"] != attempt.attempt_id or attempt.workdir != expected_stage):
            raise CheckpointError("Attempt is not owned by this active writer")
        evidence = {} if evidence is None else evidence
        self._evidence(task, evidence)
        if not artifacts or {p.name for p in attempt.workdir.iterdir()} != set(artifacts):
            raise CheckpointError("Explicit exact artifact inventory required")
        records = {}
        for name, kind in artifacts.items():
            artifact_name(name)
            p = attempt.workdir / name
            self._structure(p, kind)
            # These are NEW adapter-produced staging artifacts, never inputs.
            # Windows FlushFileBuffers requires a write-capable owned handle.
            with p.open("r+b") as stream:
                os.fsync(stream.fileno())
            records[name] = {"kind": kind, "bytes": p.stat().st_size, "sha256": sha256_file(p)}
        dependency_manifests = {}
        for dep in task["requires"]:
            parent = self.verified(dep)
            if parent is None:
                raise CheckpointError("Dependency changed during task")
            dependency_manifests[dep] = digest(parent)
        manifest = {"task_sha256": digest(task), "run_sha256": self.run.contract_sha256,
                    "attempt_id": attempt.attempt_id, "artifacts": records, "evidence": evidence,
                    "dependency_manifests": dependency_manifests,
                    "execution": {"started_at": state["started_at"], "completed_at": time.time(),
                                  "owner": self.token, "pid": self.pid,
                                  "resources": state["resources"], "observations": state["observations"]},
                    "technical_complete": True, "scientific_approval": False}
        write_json(attempt.workdir / "MANIFEST.json", manifest)
        self.assert_owner()  # Fence immediately before publication, not just at admission.
        final = self.root / "tasks" / attempt.task_id / attempt.attempt_id
        if final.exists():
            raise CheckpointError("Refusing prior attempt overwrite")
        os.rename(attempt.workdir, final)
        _sync_directory(final.parent)
        self._state(attempt.task_id, {"state": "complete", "attempt_id": attempt.attempt_id,
                                     "manifest_sha256": digest(manifest)})
        return self.verified(attempt.task_id)

    def retry_after_review(self, task_id, attempt_id):
        self.assert_owner()
        state = self.state(task_id)
        if state["state"] != "needs_review" or state["attempt_id"] != attempt_id:
            raise CheckpointError("Explicit matching needs_review attempt required")
        write_json(self.root / "tasks" / task_id / (uuid.uuid4().hex + ".review.json"),
                   {"reviewed_attempt": attempt_id, "previous_state": state,
                    "action": "authorize_new_attempt", "at": time.time()})
        self._state(task_id, {"state": "pending", "attempt_id": None})

    def adopt_after_review(self, task_id, attempt_id, manifest_sha256):
        self.assert_owner()
        state = self.state(task_id)
        if state["state"] != "needs_review" or state["attempt_id"] != attempt_id:
            raise CheckpointError("Explicit matching review required")
        manifest = self._manifest(self.task(task_id), attempt_id)
        if digest(manifest) != manifest_sha256:
            raise CheckpointError("Reviewed manifest hash differs")
        for dep in self.task(task_id)["requires"]:
            parent = self.verified(dep)
            if parent is None or digest(parent) != manifest["dependency_manifests"][dep]:
                raise CheckpointError("Unfinished dependency")
        write_json(self.root / "tasks" / task_id / (uuid.uuid4().hex + ".review.json"),
                   {"reviewed_attempt": attempt_id, "manifest_sha256": manifest_sha256,
                    "action": "adopt_published_checkpoint", "at": time.time()})
        self._state(task_id, {"state": "complete", "attempt_id": attempt_id,
                             "manifest_sha256": manifest_sha256})

    def resume(self, request_id):
        self.assert_owner()
        self.run.check_compatibility()
        identifier(request_id)
        with FileLock(self.root / ".admission.lock"):
            if self.run.pause_id() != request_id:
                raise CheckpointError("Explicit current pause request acknowledgement required")
            write_json(self.root / "resume_ack" / (request_id + ".json"),
                       {"request_id": request_id, "owner": self.token, "at": time.time()})

    def run_task(self, task_id, producer: Callable[[Attempt], tuple[dict, dict]],
                 resources=Resources(), **observations):
        """Adapter boundary only; NO Hmsc adapter is shipped. Preserve failures."""
        self.assert_owner()
        if self.verified(task_id) is not None:
            return "REUSED"
        attempt = self.begin(task_id, resources, **observations)
        try:
            artifacts, evidence = producer(attempt)
            self.complete(attempt, artifacts, evidence)
            return "COMPLETE"
        except BaseException:
            self._state(task_id, {"state": "needs_review", "attempt_id": attempt.attempt_id,
                                  "reason": "adapter_or_publication_failed"})
            raise
