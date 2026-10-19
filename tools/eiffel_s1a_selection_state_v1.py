"""Pure synthetic S1a decision states. No IO, RNG draws, fitting or checkpoint imports.

Acceptance and ranking are explicit adapter inputs, never inferred from metrics.
selected_groups records forward acceptance history, not current representation.
Use Selection.group_summary() for the derived representation and plan(selection)
for history-verified planning. Serialized schema 1 remains unchanged.
See project_state/s1a_selection_state_v1/README.md for the unimplemented boundary.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import math
import re


class SelectionError(ValueError):
    pass


class Conflict(SelectionError):
    pass


def require(condition, message):
    if not condition:
        raise SelectionError(message)


def canonical(value):
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"),
                          ensure_ascii=False, allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise SelectionError("Canonical finite JSON required") from error


def sha(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def decode(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "Duplicate JSON key")
            result[key] = value
        return result

    def finite(text):
        value = float(text)
        require(math.isfinite(value), "Nonfinite JSON")
        return value

    def invalid(_):
        raise SelectionError("Nonfinite JSON")

    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_float=finite,
                          parse_constant=invalid)
    except (TypeError, ValueError, UnicodeError) as error:
        raise SelectionError("Invalid JSON record") from error


@dataclass(frozen=True)
class Record:
    """Immutable canonical bytes; data always returns a detached copy."""
    raw: bytes

    def __post_init__(self):
        require(type(self.raw) is bytes, "Record requires immutable bytes")
        require(canonical(decode(self.raw)) == self.raw, "Noncanonical record")

    @classmethod
    def of(cls, value):
        return cls(canonical(value))

    @property
    def data(self):
        return decode(self.raw)

    @property
    def sha256(self):
        return hashlib.sha256(self.raw).hexdigest()


def keys(value, expected):
    require(isinstance(value, dict) and set(value) == set(expected.split()),
            "Unexpected or missing fields")


def text(value):
    require(isinstance(value, str) and bool(value.strip()), "Nonempty text required")


def fingerprint(value):
    require(isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value), "SHA-256 required")


def names(values):
    require(isinstance(values, list) and all(isinstance(v, str) and v for v in values),
            "Ordered names required")
    require(len(values) == len(set(values)), "Duplicate name")


def rng_ref(value):
    keys(value, "id sha256 source_id")
    text(value["id"]); text(value["source_id"]); fingerprint(value["sha256"])


FORWARD_REASONS = {"no_candidates", "no_screening_acceptance",
                   "no_confirmation_acceptance", "configured_limit"}


def contract(value):
    record = Record.of(value)
    c = record.data
    keys(c, "schema selection_id mode species_id code inputs groups rules profiles software rng")
    require(type(c["schema"]) is int and c["schema"] == 1, "Unsupported contract schema")
    text(c["selection_id"]); text(c["species_id"])
    require(c["mode"] in {"predictive", "explanatory"}, "Explicit research mode required")
    for field in ("code", "inputs"):
        require(isinstance(c[field], dict) and bool(c[field]), "Source fingerprints required")
        for name, digest in c[field].items():
            text(name); fingerprint(digest)
    require(isinstance(c["groups"], list), "Ordered groups required")
    group_ids = []
    for group in c["groups"]:
        keys(group, "id variables"); text(group["id"]); names(group["variables"])
        require(bool(group["variables"]), "Empty group")
        group_ids.append(group["id"])
    names(group_ids)
    require(len({g.casefold() for g in group_ids}) == len(group_ids), "Ambiguous group IDs")
    rules = c["rules"]
    keys(rules, "policy_id max_forward_groups allowed_forward_stops backward_required minimum_variables_per_group")
    text(rules["policy_id"])
    limit = rules["max_forward_groups"]
    require(limit is None or (type(limit) is int and limit > 0), "Invalid explicit group limit")
    names(rules["allowed_forward_stops"])
    require(bool(rules["allowed_forward_stops"]) and
            set(rules["allowed_forward_stops"]) <= FORWARD_REASONS, "Invalid stop reasons")
    require(type(rules["backward_required"]) is bool, "Explicit backward policy required")
    require(type(rules["minimum_variables_per_group"]) is int and
            rules["minimum_variables_per_group"] >= 1, "Explicit positive group guard required")
    keys(c["profiles"], "screen confirm backward")
    for profile in c["profiles"].values():
        require(isinstance(profile, dict) and bool(profile), "Explicit profiles required")
    require(isinstance(c["software"], dict) and bool(c["software"]), "Software identities required")
    for name, version in c["software"].items():
        text(name); text(version)
    keys(c["rng"], "policy_id required initial")
    text(c["rng"]["policy_id"])
    require(type(c["rng"]["required"]) is bool, "Explicit RNG policy required")
    if c["rng"]["required"]:
        rng_ref(c["rng"]["initial"])
    else:
        require(c["rng"]["initial"] is None, "RNG-free contract must not declare a state")
    return record


def initial(base):
    c = base.data
    return Record.of({"version": 0, "parent_sha256": None, "contract_sha256": base.sha256,
                      "phase": "forward", "next": "screen" if c["groups"] else "forward_end", "forward_step": 1,
                      "backward_step": 0, "selected_groups": [], "variables": [],
                      "remaining": [g["id"] for g in c["groups"]], "screening": [],
                      "queue": [], "rejections": [], "forward_reason": None,
                      "pending_reason": None if c["groups"] else "no_candidates", "backward_status": None,
                      "backward_reason": None, "issue": None, "decision_ref": None,
                      "rng": c["rng"]["initial"]})


def plan(selection):
    """Verify the complete history before returning a fixed input descriptor.

    This does not provide coordinator locking or atomic task publication.
    """
    require(type(selection) is Selection, "Planning requires a Selection history")
    state = selection.verify()
    return _plan_for_state(selection.base, state)


def _plan_for_state(base, state):
    """Private replay/event helper; callers must use plan(selection)."""
    s = state.data
    require(s["contract_sha256"] == base.sha256, "Wrong base contract")
    require(s["next"] is not None, "Terminal state has no next task")
    items = (s["remaining"] if s["next"] == "screen" else
             s["queue"][:1] if s["next"] == "confirm" else
             s["variables"] if s["next"] == "backward_round" else [])
    p = {"contract_sha256": base.sha256, "parent_sha256": state.sha256,
         "slot": s["next"], "items": items, "rng_before": s["rng"],
         "variables": s["variables"], "selected_groups": s["selected_groups"],
         "profile": base.data["profiles"].get(
             "backward" if s["next"] == "backward_round" else s["next"]),
         "forward_step": s["forward_step"], "backward_step": s["backward_step"]}
    p["source_id"] = "source_" + sha(p)
    return Record.of(p)


def result(source_id, status, payload, rng_before, rng_after):
    """Caller supplies synthetic/adapter evidence; no scientific evaluation here."""
    return Record.of({"source_id": source_id, "status": status, "payload": payload,
                      "rng_before": rng_before, "rng_after": rng_after})


def decision(base, state, source):
    """Build an event only; apply() still verifies history before accepting it."""
    p = _plan_for_state(base, state).data
    e = source.data
    d = {"contract_sha256": base.sha256, "parent_sha256": state.sha256,
         "slot": p["slot"], "source_id": e["source_id"],
         "source_sha256": source.sha256, "payload_sha256": sha(e["payload"])}
    d["id"] = sha(d)
    return Record.of(d)


def check_evidence(base, d, source):
    keys(d, "contract_sha256 parent_sha256 slot source_id source_sha256 payload_sha256 id")
    require(d["contract_sha256"] == base.sha256, "Wrong contract")
    fingerprint(d["parent_sha256"])
    require(d["id"] == sha({k: v for k, v in d.items() if k != "id"}), "Wrong decision ID")
    e = source.data
    keys(e, "source_id status payload rng_before rng_after")
    require(d["source_id"] == e["source_id"] and d["source_sha256"] == source.sha256,
            "Wrong source identity or digest")
    require(d["payload_sha256"] == sha(e["payload"]), "Wrong decision content digest")
    require(e["status"] in {"complete", "incomplete", "technical_error"}, "Unknown result status")
    return e


def ranked_rows(rows, expected, item_key):
    require(isinstance(rows, list) and len(rows) == len(expected), "Incomplete decision batch")
    require(all(isinstance(row, dict) and item_key in row and "rank" in row for row in rows),
            "Missing ranked row")
    ids = [row[item_key] for row in rows]
    names(ids)
    require(set(ids) == set(expected), "Wrong candidate set")
    require(all(type(row["rank"]) is int for row in rows) and
            sorted(row["rank"] for row in rows) == list(range(len(rows))),
            "Explicit unique adapter ranks required; no metric-based ranking")
    return sorted(rows, key=lambda row: row["rank"])


def _advance(base, previous, d, source):
    e = check_evidence(base, d, source)
    s, c = previous.data, base.data
    p = _plan_for_state(base, previous).data
    require(d["parent_sha256"] == previous.sha256 and d["slot"] == s["next"],
            "Wrong parent or decision order")
    require(e["source_id"] == p["source_id"], "Result belongs to a different batch")
    require(e["rng_before"] == s["rng"], "Wrong or missing input RNG state")
    if c["rng"]["required"]:
        rng_ref(e["rng_before"])
    else:
        require(e["rng_after"] is None, "RNG policy cannot change")
    action, payload = s["next"], e["payload"]
    if e["status"] != "complete":
        require(action != "review", "Review must be completed explicitly")
        keys(payload, "detail"); text(payload["detail"])
        require(e["rng_after"] is None, "Interrupted result has no certified RNG-after state")
        s["issue"] = {"status": e["status"], "source_sha256": source.sha256,
                      "resume": action, "detail": payload["detail"]}
        s["next"] = "review"
    else:
        if action in {"screen", "confirm", "backward_round"}:
            if c["rng"]["required"]:
                rng_ref(e["rng_after"])
                require(e["rng_after"]["source_id"] == e["source_id"], "Wrong RNG-after provenance")
        else:
            require(e["rng_after"] == s["rng"], "Metadata-only transition must preserve RNG")
        _completed(c, s, action, payload, source.sha256)
        s["rng"] = e["rng_after"]
    _check_group_state(c, s)
    s["version"] += 1
    s["parent_sha256"] = previous.sha256
    s["decision_ref"] = {"id": d["id"], "source_id": e["source_id"],
                         "source_sha256": source.sha256}
    return Record.of(s)


def _represented_groups(c, s):
    """Derived contract-order view, including overlapping group definitions."""
    variables = set(s["variables"])
    return [g["id"] for g in c["groups"] if variables.intersection(g["variables"])]


def _check_group_state(c, s):
    groups = {g["id"]: set(g["variables"]) for g in c["groups"]}
    names(s["selected_groups"]); names(s["variables"])
    require(set(s["selected_groups"]) <= set(groups), "Unknown accepted group")
    allowed = {v for g in s["selected_groups"] for v in groups[g]}
    require(set(s["variables"]) <= allowed, "Variables lack an accepted-group origin")
    require(not s["selected_groups"] or bool(s["variables"]), "Accepted history has no represented group")


def _completed(c, s, action, payload, source_hash):
    groups = {g["id"]: g["variables"] for g in c["groups"]}
    rules = c["rules"]
    if action == "screen":
        keys(payload, "rows")
        rows = ranked_rows(payload["rows"], s["remaining"], "group")
        for row in rows:
            keys(row, "group accepted rank variables")
            require(type(row["accepted"]) is bool, "Explicit screening decision required")
            names(row["variables"])
            require(set(row["variables"]) <= set(s["variables"] + groups[row["group"]]),
                    "Unexpected candidate variables")
        s["screening"] = rows
        s["queue"] = [row["group"] for row in rows if row["accepted"]]
        s["rejections"] = [{"item": row["group"], "reason": "screening_rejected",
                             "source_sha256": source_hash} for row in rows if not row["accepted"]]
        s["next"] = "confirm" if s["queue"] else "forward_end"
        s["pending_reason"] = None if s["queue"] else "no_screening_acceptance"
    elif action == "confirm":
        keys(payload, "group accepted variables")
        require(type(payload["accepted"]) is bool and payload["group"] == s["queue"][0],
                "Wrong confirmation candidate")
        row = next(row for row in s["screening"] if row["group"] == payload["group"])
        require(payload["variables"] == row["variables"], "Confirmation variables changed")
        s["queue"] = s["queue"][1:]
        if payload["accepted"]:
            require(bool(set(payload["variables"]) & set(groups[payload["group"]])),
                    "Accepted forward group must be represented at confirmation")
            s["selected_groups"].append(payload["group"])
            s["variables"] = payload["variables"]
            s["remaining"].remove(payload["group"])
            s["screening"], s["queue"], s["rejections"] = [], [], []
            s["forward_step"] += 1
            limit = rules["max_forward_groups"]
            s["pending_reason"] = ("configured_limit" if limit is not None and
                                   len(s["selected_groups"]) >= limit else
                                   "no_candidates" if not s["remaining"] else None)
            s["next"] = "forward_end" if s["pending_reason"] else "screen"
        else:
            s["rejections"].append({"item": payload["group"], "reason": "confirmation_rejected",
                                    "source_sha256": source_hash})
            s["next"] = "confirm" if s["queue"] else "forward_end"
            s["pending_reason"] = None if s["queue"] else "no_confirmation_acceptance"
    elif action == "forward_end":
        keys(payload, "reason")
        require(payload["reason"] == s["pending_reason"] and
                payload["reason"] in rules["allowed_forward_stops"], "Unjustified forward stop")
        s["forward_reason"], s["pending_reason"] = payload["reason"], None
        s["next"] = "backward_start"
    elif action == "backward_start":
        keys(payload, "applicable reason")
        applicable = rules["backward_required"] and len(s["variables"]) >= 2
        reason = (None if applicable else "disabled_in_contract" if not rules["backward_required"]
                  else "fewer_than_two_variables")
        require(type(payload["applicable"]) is bool and payload["applicable"] == applicable and
                payload["reason"] == reason, "Unsupported backward applicability")
        s["phase"], s["backward_step"] = "backward", 1
        s["next"] = "backward_round" if applicable else "backward_end"
        s["backward_status"] = "running" if applicable else "not_applicable"
        s["pending_reason"] = reason
        s["screening"], s["queue"], s["rejections"] = [], [], []
    elif action == "backward_round":
        keys(payload, "rows")
        rows = ranked_rows(payload["rows"], s["variables"], "variable")
        represented = set(_represented_groups(c, s))
        for row in rows:
            keys(row, "variable accepted guard_allows rank")
            require(type(row["accepted"]) is bool and type(row["guard_allows"]) is bool,
                    "Explicit removal and group-guard decisions required")
            reduced = [v for v in s["variables"] if v != row["variable"]]
            allowed = all(row["variable"] not in groups[g] or
                          len(set(reduced) & set(groups[g])) >= rules["minimum_variables_per_group"]
                          for g in s["selected_groups"] if g in represented)
            require(row["guard_allows"] == allowed and (not row["accepted"] or allowed),
                    "Group guard contradicts declared removal")
        accepted = [row for row in rows if row["accepted"]]
        s["rejections"] = [{"item": row["variable"], "reason": "removal_rejected" if
                             row["guard_allows"] else "group_guard", "source_sha256": source_hash}
                            for row in rows if not row["accepted"]]
        if accepted:
            s["variables"].remove(accepted[0]["variable"])
            s["backward_step"] += 1
            s["pending_reason"] = "single_variable" if len(s["variables"]) < 2 else None
        else:
            s["pending_reason"] = "no_permitted_removal"
        s["next"] = "backward_end" if s["pending_reason"] else "backward_round"
    elif action == "backward_end":
        keys(payload, "reason")
        require(payload["reason"] == s["pending_reason"], "Unjustified backward stop")
        if s["backward_status"] != "not_applicable":
            s["backward_status"] = "complete"
        s["backward_reason"], s["pending_reason"] = payload["reason"], None
        s["phase"], s["next"] = "complete", None
    elif action == "review":
        keys(payload, "action issue_source_sha256 reason")
        require(payload["action"] == "retry" and
                payload["issue_source_sha256"] == s["issue"]["source_sha256"], "Wrong issue review")
        text(payload["reason"])
        s["next"], s["issue"] = s["issue"]["resume"], None
    else:
        raise SelectionError("Unknown decision slot")


@dataclass(frozen=True)
class Selection:
    base: Record
    states: tuple[Record, ...]
    decisions: tuple[Record, ...] = ()
    sources: tuple[Record, ...] = ()

    @classmethod
    def start(cls, value):
        base = contract(value)
        return cls(base, (initial(base),))

    @property
    def state(self):
        return self.states[-1]

    def group_summary(self):
        """Verified derived view; no extra fields are stored in schema 1.

        History is in acceptance order; representation is in contract order.
        A later confirmed forward result may remove an earlier representation.
        """
        s = self.verify().data
        return Record.of({"accepted_groups_history": s["selected_groups"],
                          "represented_groups": _represented_groups(self.base.data, s)})

    def verify(self):
        require(contract(self.base.data) == self.base, "Invalid base contract")
        require(all(type(v) is tuple for v in (self.states, self.decisions, self.sources)) and
                len(self.states) == len(self.decisions) + 1 == len(self.sources) + 1,
                "Broken chain lengths")
        expected = initial(self.base)
        require(self.states[0] == expected, "Wrong initial state")
        for d, source, state in zip(self.decisions, self.sources, self.states[1:]):
            expected = _advance(self.base, expected, d.data, source)
            require(state == expected, "Corrupt or conflicting state chain")
        return self.state

    def apply(self, d, source):
        self.verify()
        check_evidence(self.base, d.data, source)
        for old in self.decisions:
            if (old.data["parent_sha256"], old.data["slot"]) == (d.data["parent_sha256"], d.data["slot"]):
                if old == d:
                    return self  # Exact replay is idempotent, not another acceptance.
                raise Conflict("Conflicting successor for an already committed decision slot")
        state = _advance(self.base, self.state, d.data, source)
        return Selection(self.base, self.states + (state,), self.decisions + (d,), self.sources + (source,))

    def export(self):
        self.verify()
        return Record.of({"base": self.base.data, "states": [s.data for s in self.states],
                          "decisions": [d.data for d in self.decisions],
                          "sources": [s.data for s in self.sources]})

    @classmethod
    def restore(cls, record):
        value = record.data
        keys(value, "base states decisions sources")
        selection = cls(Record.of(value["base"]), tuple(Record.of(v) for v in value["states"]),
                        tuple(Record.of(v) for v in value["decisions"]),
                        tuple(Record.of(v) for v in value["sources"]))
        selection.verify()
        return selection

    def completion(self):
        s = self.verify().data
        _check_group_state(self.base.data, s)
        require(s["phase"] == "complete" and s["next"] is None and s["issue"] is None and
                s["forward_reason"] in self.base.data["rules"]["allowed_forward_stops"] and
                s["backward_status"] in {"complete", "not_applicable"}, "Selection is unfinished")
        return Record.of({"contract_sha256": self.base.sha256, "terminal_state_sha256": self.state.sha256,
                          "chain_sha256": self.export().sha256, "selected_groups": s["selected_groups"],
                          "variables": s["variables"], "forward_reason": s["forward_reason"],
                          "backward_status": s["backward_status"], "backward_reason": s["backward_reason"],
                          "source_refs": [state.data["decision_ref"] for state in self.states[1:]],
                          "technical_complete": True, "scientific_approval": False,
                          "model_artifacts_verified": False,
                          "evidence_scope": "synthetic_decision_chain_only"})
