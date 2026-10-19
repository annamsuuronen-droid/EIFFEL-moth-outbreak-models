"""Synthetic decision records only: no files, R, Hmsc, RNG draws or model calls."""
import copy
from dataclasses import FrozenInstanceError, replace
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import eiffel_s1a_selection_state_v1 as sm


def specification():
    return {"schema": 1, "selection_id": "SYNTHETIC_SELECTION", "mode": "predictive",
            "species_id": "SYNTHETIC_SPECIES", "code": {"fixture": "a" * 64},
            "inputs": {"fixture": "b" * 64},
            "groups": [{"id": g, "variables": [g.lower() + "1", g.lower() + "2"]}
                       for g in ("A", "B", "C", "D")],
            "rules": {"policy_id": "SYNTHETIC_EXPLICIT_FLAGS_AND_RANKS",
                      "max_forward_groups": None,
                      "allowed_forward_stops": sorted(sm.FORWARD_REASONS),
                      "backward_required": True, "minimum_variables_per_group": 1},
            "profiles": {"screen": {"label": "SYNTHETIC_SCREEN"},
                         "confirm": {"label": "SYNTHETIC_CONFIRM"},
                         "backward": {"label": "SYNTHETIC_BACKWARD"}},
            "software": {"Python": "SYNTHETIC_METADATA", "R": "NOT_LOADED", "Hmsc": "NOT_LOADED"},
            "rng": {"policy_id": "SYNTHETIC_REFERENCES_ONLY", "required": True,
                    "initial": {"id": "synthetic_initial", "sha256": "c" * 64,
                                "source_id": "synthetic_rng_source"}}}


def prepared(h, payload, status="complete"):
    p = sm.plan(h.base, h.state).data
    before = h.state.data["rng"]
    after = before
    if status != "complete":
        after = None
    elif before is not None and p["slot"] in {"screen", "confirm", "backward_round"}:
        # Fake opaque references, not a Python/R/Hmsc random-number generator.
        after = {"id": "synthetic_after", "sha256": sm.sha({"after": p["source_id"]}),
                 "source_id": p["source_id"]}
    source = sm.result(p["source_id"], status, payload, before, after)
    return sm.decision(h.base, h.state, source), source


def emit(h, payload, status="complete"):
    return h.apply(*prepared(h, payload, status))


def screening(h, accepted, order=None):
    s = h.state.data
    order = s["remaining"] if order is None else order
    groups = {g["id"]: g["variables"] for g in h.base.data["groups"]}
    rows = [{"group": g, "accepted": g in accepted, "rank": i,
             "variables": list(dict.fromkeys(s["variables"] + groups[g]))}
            for i, g in enumerate(order)]
    return {"rows": rows}


def confirm(h, accepted=True):
    s = h.state.data
    row = next(row for row in s["screening"] if row["group"] == s["queue"][0])
    return emit(h, {"group": row["group"], "accepted": accepted, "variables": row["variables"]})


def choose(h, group):
    return confirm(emit(h, screening(h, [group])))


def forward_end(h):
    return emit(h, {"reason": h.state.data["pending_reason"]})


def backward_start(h):
    s = h.state.data
    required = h.base.data["rules"]["backward_required"]
    applicable = required and len(s["variables"]) >= 2
    reason = None if applicable else "disabled_in_contract" if not required else "fewer_than_two_variables"
    return emit(h, {"applicable": applicable, "reason": reason})


def removal_rows(h, accepted=(), blocked=(), order=None):
    order = h.state.data["variables"] if order is None else order
    return {"rows": [{"variable": v, "rank": i, "accepted": v in accepted,
                      "guard_allows": v not in blocked} for i, v in enumerate(order)]}


def finish(h):
    if h.state.data["next"] == "screen":
        h = emit(h, screening(h, []))
    h = backward_start(forward_end(h))
    if h.state.data["next"] == "backward_round":
        h = emit(h, removal_rows(h))  # Two variables per selected fixture group.
    return emit(h, {"reason": h.state.data["pending_reason"]})


def rewritten(record, **changes):
    value = record.data
    value.update(changes)
    if "id" in value:
        value["id"] = sm.sha({k: v for k, v in value.items() if k != "id"})
    return sm.Record.of(value)


class SelectionStates(unittest.TestCase):
    def setUp(self):
        self.spec = specification()
        self.h = sm.Selection.start(self.spec)

    def test_more_than_two_groups_and_no_implicit_stop(self):
        h = self.h
        for group in ("A", "B", "C"):
            h = choose(h, group)
        self.assertEqual(h.state.data["selected_groups"], ["A", "B", "C"])
        self.assertEqual(h.state.data["next"], "screen")
        self.assertEqual(h.state.data["remaining"], ["D"])
        completed = finish(h).completion().data
        self.assertEqual(completed["selected_groups"], ["A", "B", "C"])

    def test_rejected_group_reappears_in_next_forward_context(self):
        screened = emit(self.h, screening(self.h, ["B"]))
        self.assertIn("A", [r["item"] for r in screened.state.data["rejections"]])
        h = confirm(screened)
        self.assertIn("A", sm.plan(h.base, h.state).data["items"])
        h = choose(h, "A")
        self.assertEqual(h.state.data["selected_groups"], ["B", "A"])
        self.assertEqual(screened.state.data["selected_groups"], [])

    def test_confirmation_rejection_moves_to_next_ranked_candidate(self):
        payload = screening(self.h, ["A", "B"], ["B", "A", "D", "C"])
        payload["rows"].reverse()  # Input row order does not override explicit ranks.
        h = emit(self.h, payload)
        self.assertEqual(h.state.data["queue"], ["B", "A"])
        h = confirm(h, False)
        self.assertEqual(h.state.data["queue"], ["A"])
        self.assertEqual(h.state.data["rejections"][-1]["reason"], "confirmation_rejected")
        h = confirm(h)
        self.assertEqual(h.state.data["selected_groups"], ["A"])
        self.assertIn("B", h.state.data["remaining"])

    def test_explicit_forward_stop_reasons(self):
        no_screen = emit(self.h, screening(self.h, []))
        no_confirm = confirm(emit(self.h, screening(self.h, ["A"])), False)
        one = specification(); one["groups"] = one["groups"][:1]
        no_candidates = choose(sm.Selection.start(one), "A")
        limited = specification(); limited["rules"]["max_forward_groups"] = 3
        limit = sm.Selection.start(limited)
        for group in ("A", "B", "C"):
            limit = choose(limit, group)
        for h, reason in ((no_screen, "no_screening_acceptance"),
                          (no_confirm, "no_confirmation_acceptance"),
                          (no_candidates, "no_candidates"), (limit, "configured_limit")):
            with self.subTest(reason=reason):
                self.assertEqual(h.state.data["pending_reason"], reason)
                self.assertEqual(forward_end(h).state.data["forward_reason"], reason)

    def test_premature_or_disallowed_forward_end_refused(self):
        d, source = prepared(self.h, {"reason": "configured_limit"})
        with self.assertRaises(sm.SelectionError):
            self.h.apply(d, source)
        spec = specification(); spec["rules"]["allowed_forward_stops"] = ["no_candidates"]
        h = sm.Selection.start(spec); h = emit(h, screening(h, []))
        with self.assertRaises(sm.SelectionError):
            forward_end(h)

    def test_empty_candidate_universe_has_explicit_end_and_no_work(self):
        spec = specification(); spec["groups"] = []
        h = sm.Selection.start(spec)
        self.assertEqual(h.state.data["next"], "forward_end")
        self.assertEqual(sm.plan(h.base, h.state).data["items"], [])
        h = emit(backward_start(forward_end(h)), {"reason": "fewer_than_two_variables"})
        self.assertEqual(h.completion().data["selected_groups"], [])
        self.assertEqual(h.completion().data["forward_reason"], "no_candidates")

    def test_backward_accepted_and_rejected_removals(self):
        spec = specification(); spec["groups"] = spec["groups"][:1]
        h = backward_start(forward_end(choose(sm.Selection.start(spec), "A")))
        h = emit(h, removal_rows(h, accepted=["a2"], order=["a2", "a1"]))
        self.assertEqual(h.state.data["variables"], ["a1"])
        self.assertEqual(h.state.data["pending_reason"], "single_variable")
        self.assertIn("a1", [r["item"] for r in h.state.data["rejections"]])
        h = emit(h, {"reason": "single_variable"})
        self.assertEqual(h.completion().data["variables"], ["a1"])

    def test_group_guard_is_explicit_and_cannot_be_overridden(self):
        spec = specification()
        spec["groups"] = [{"id": "A", "variables": ["a"]},
                          {"id": "B", "variables": ["b1", "b2"]}]
        h = sm.Selection.start(spec)
        h = backward_start(forward_end(choose(choose(h, "A"), "B")))
        with self.assertRaisesRegex(sm.SelectionError, "Group guard"):
            emit(h, removal_rows(h, accepted=["a"]))
        h = emit(h, removal_rows(h, blocked=["a"]))
        self.assertEqual(h.state.data["variables"], ["a", "b1", "b2"])
        self.assertEqual(h.state.data["rejections"][0]["reason"], "group_guard")

    def test_repeated_backward_steps_preserve_groups_and_finish(self):
        h = choose(choose(self.h, "A"), "B")
        h = backward_start(forward_end(emit(h, screening(h, []))))
        h = emit(h, removal_rows(h, accepted=["a1"]))
        self.assertEqual(h.state.data["next"], "backward_round")
        h = emit(h, removal_rows(h, accepted=["b1"], blocked=["a2"]))
        self.assertEqual(h.state.data["variables"], ["a2", "b2"])
        self.assertEqual(h.state.data["backward_step"], 3)
        h = emit(h, removal_rows(h, blocked=["a2", "b2"]))
        h = emit(h, {"reason": "no_permitted_removal"})
        self.assertEqual(h.completion().data["selected_groups"], ["A", "B"])

    def test_backward_inapplicable_requires_structural_reason(self):
        h = forward_end(emit(self.h, screening(self.h, [])))
        with self.assertRaises(sm.SelectionError):
            emit(h, {"applicable": False, "reason": "not_needed"})
        h = backward_start(h)
        h = emit(h, {"reason": "fewer_than_two_variables"})
        self.assertEqual(h.completion().data["backward_status"], "not_applicable")
        h = choose(self.h, "A")
        h = forward_end(emit(h, screening(h, [])))
        with self.assertRaises(sm.SelectionError):
            emit(h, {"applicable": False, "reason": "fewer_than_two_variables"})

    def test_backward_disabled_only_by_immutable_contract(self):
        spec = specification(); spec["rules"]["backward_required"] = False
        h = finish(choose(sm.Selection.start(spec), "A"))
        self.assertEqual(h.completion().data["backward_reason"], "disabled_in_contract")

    def test_wrong_decision_order_and_parent_refused(self):
        d, source = prepared(self.h, screening(self.h, ["A"]))
        with self.assertRaises(sm.SelectionError):
            self.h.apply(rewritten(d, slot="confirm"), source)
        with self.assertRaises(sm.SelectionError):
            self.h.apply(rewritten(d, parent_sha256="0" * 64), source)

    def test_wrong_source_and_content_fingerprints_refused(self):
        d, source = prepared(self.h, screening(self.h, ["A"]))
        for changed in (rewritten(d, source_sha256="0" * 64),
                        rewritten(d, payload_sha256="0" * 64)):
            with self.assertRaises(sm.SelectionError):
                self.h.apply(changed, source)
        wrong = rewritten(source, source_id="wrong_batch")
        with self.assertRaises(sm.SelectionError):
            self.h.apply(sm.decision(self.h.base, self.h.state, wrong), wrong)

    def test_duplicate_decision_is_idempotent(self):
        d, source = prepared(self.h, screening(self.h, ["A"]))
        h = self.h.apply(d, source)
        self.assertIs(h.apply(d, source), h)
        self.assertEqual(len(h.decisions), 1)
        accepted = confirm(h)
        self.assertIs(accepted.apply(d, source), accepted)
        self.assertEqual(accepted.state.data["selected_groups"], ["A"])

    def test_conflicting_successors_are_detected_within_supplied_history(self):
        first = prepared(self.h, screening(self.h, ["A"]))
        other = prepared(self.h, screening(self.h, ["B"]))
        h = self.h.apply(*first)
        with self.assertRaises(sm.Conflict):
            h.apply(*other)
        # Separate pure values can fork; a future coordinator must serialize them.
        alternative = self.h.apply(*other)
        self.assertNotEqual(h.state.sha256, alternative.state.sha256)

    def test_state_chain_corruption_and_missing_records_refused(self):
        h = choose(self.h, "A")
        for changes in ({"version": 999}, {"parent_sha256": "0" * 64},
                        {"variables": ["invented"]}, {"decision_ref": None}):
            states = h.states[:-1] + (rewritten(h.state, **changes),)
            with self.subTest(changes=changes), self.assertRaises(sm.SelectionError):
                replace(h, states=states).verify()
        with self.assertRaises(sm.SelectionError):
            replace(h, sources=h.sources[:-1]).verify()
        with self.assertRaises(sm.SelectionError):
            replace(h, states=h.states[1:]).verify()

    def test_rng_missing_wrong_and_wrong_provenance_refused(self):
        d, source = prepared(self.h, screening(self.h, ["A"]))
        for changes in ({"rng_before": None}, {"rng_after": None},
                        {"rng_before": {"id": "wrong", "sha256": "e" * 64, "source_id": "wrong"}},
                        {"rng_after": {"id": "wrong", "sha256": "e" * 64, "source_id": "wrong"}}):
            bad = rewritten(source, **changes)
            with self.subTest(changes=changes), self.assertRaises(sm.SelectionError):
                self.h.apply(sm.decision(self.h.base, self.h.state, bad), bad)
        spec = specification(); spec["rng"]["initial"] = None
        with self.assertRaises(sm.SelectionError):
            sm.Selection.start(spec)

    def test_metadata_transitions_preserve_rng_and_policy(self):
        h = emit(self.h, screening(self.h, []))
        d, source = prepared(h, {"reason": "no_screening_acceptance"})
        changed = rewritten(source, rng_after={"id": "changed", "sha256": "d" * 64,
                                               "source_id": source.data["source_id"]})
        with self.assertRaises(sm.SelectionError):
            h.apply(sm.decision(h.base, h.state, changed), changed)
        spec = specification(); spec["rng"]["policy_id"] = "DIFFERENT_POLICY"
        other = sm.Selection.start(spec)
        with self.assertRaises(sm.SelectionError):
            other.apply(*prepared(self.h, screening(self.h, [])))

    def test_explicit_rng_free_contract_cannot_acquire_rng(self):
        spec = specification(); spec["rng"] = {"policy_id": "SYNTHETIC_NO_RANDOMNESS",
                                               "required": False, "initial": None}
        h = sm.Selection.start(spec)
        self.assertIsNone(finish(choose(h, "A")).state.data["rng"])
        d, source = prepared(h, screening(h, ["A"]))
        changed = rewritten(source, rng_after={"id": "new", "sha256": "e" * 64, "source_id": "new"})
        with self.assertRaises(sm.SelectionError):
            h.apply(sm.decision(h.base, h.state, changed), changed)

    def test_technical_error_and_incomplete_require_explicit_review(self):
        for status in ("technical_error", "incomplete"):
            with self.subTest(status=status):
                h = emit(self.h, {"detail": "synthetic interruption"}, status)
                self.assertEqual(h.state.data["issue"]["status"], status)
                self.assertEqual(h.state.data["next"], "review")
                with self.assertRaises(sm.SelectionError):
                    h.completion()
                with self.assertRaises(sm.SelectionError):
                    emit(h, screening(self.h, []))
                with self.assertRaises(sm.SelectionError):
                    emit(h, {"action": "retry", "issue_source_sha256": "0" * 64, "reason": "checked"})
                h = emit(h, {"action": "retry", "issue_source_sha256": h.state.data["issue"]["source_sha256"],
                             "reason": "synthetic review; retry whole decision batch"})
                self.assertIsNone(h.state.data["issue"])
                done = finish(choose(h, "A"))
                self.assertEqual(done.sources[0].data["status"], status)
                self.assertTrue(done.completion().data["technical_complete"])

    def test_incomplete_or_forged_terminal_cannot_produce_certificate(self):
        h = choose(self.h, "A")
        for unfinished in (self.h, h, forward_end(emit(h, screening(h, [])))):
            with self.assertRaises(sm.SelectionError):
                unfinished.completion()
        forged = replace(h, states=h.states[:-1] + (rewritten(h.state, phase="complete", next=None),))
        with self.assertRaises(sm.SelectionError):
            forged.completion()

    def test_terminal_certificate_is_traceable_and_not_scientific_approval(self):
        h = finish(choose(self.h, "A"))
        certificate = h.completion().data
        self.assertEqual(certificate["chain_sha256"], h.export().sha256)
        self.assertEqual(certificate["terminal_state_sha256"], h.state.sha256)
        self.assertEqual(len(certificate["source_refs"]), len(h.decisions))
        self.assertIs(certificate["scientific_approval"], False)
        self.assertIs(certificate["model_artifacts_verified"], False)
        with self.assertRaises(sm.SelectionError):
            sm.plan(h.base, h.state)

    def test_interrupted_and_uninterrupted_sequences_are_identical(self):
        continuous, resumed = self.h, self.h
        for group in ("A", "B", "C"):
            continuous = choose(continuous, group)
            resumed = sm.Selection.restore(resumed.export())
            resumed = emit(resumed, screening(resumed, [group]))
            resumed = sm.Selection.restore(resumed.export())
            resumed = confirm(resumed)
        continuous, resumed = finish(continuous), finish(sm.Selection.restore(resumed.export()))
        self.assertEqual(continuous.export().raw, resumed.export().raw)
        self.assertEqual(continuous.completion().raw, resumed.completion().raw)
        self.assertEqual(continuous.state.data["rng"], resumed.state.data["rng"])

    def test_contract_and_previous_states_remain_immutable(self):
        original = self.h.state.raw
        original_plan = sm.plan(self.h.base, self.h.state)
        self.spec["groups"][0]["variables"].append("caller_mutation")
        detached = self.h.state.data; detached["remaining"].clear()
        self.assertEqual(self.h.state.raw, original)
        h = choose(self.h, "A")
        self.assertEqual(h.states[0].raw, original)
        next_plan = sm.plan(h.base, h.state)
        self.assertEqual(original_plan.data["variables"], [])
        self.assertEqual(next_plan.data["variables"], ["a1", "a2"])
        self.assertEqual(original_plan.data["contract_sha256"], next_plan.data["contract_sha256"])
        self.assertNotEqual(original_plan.data["source_id"], next_plan.data["source_id"])
        with self.assertRaises(FrozenInstanceError):
            h.state.raw = b'{}'
        modified = self.h.base.data; modified["inputs"]["fixture"] = "e" * 64
        with self.assertRaises(sm.SelectionError):
            replace(h, base=sm.contract(modified)).verify()

    def test_malformed_batches_and_unapproved_variables_refused(self):
        valid = screening(self.h, ["A"])
        missing = copy.deepcopy(valid); missing["rows"].pop()
        tied = copy.deepcopy(valid); tied["rows"][1]["rank"] = tied["rows"][0]["rank"]
        unknown = copy.deepcopy(valid); unknown["rows"][0]["variables"] = ["not_a_candidate"]
        non_boolean = copy.deepcopy(valid); non_boolean["rows"][0]["accepted"] = 1
        for payload in (missing, tied, unknown, non_boolean):
            with self.subTest(payload=payload), self.assertRaises(sm.SelectionError):
                emit(self.h, payload)
        h = emit(self.h, valid)
        with self.assertRaises(sm.SelectionError):
            emit(h, {"group": "A", "accepted": True, "variables": ["changed_after_screening"]})

    def test_mode_is_bound_and_no_historical_thresholds_are_inferred(self):
        explanatory = specification(); explanatory["mode"] = "explanatory"
        h = finish(choose(sm.Selection.start(explanatory), "A"))
        self.assertTrue(h.completion().data["technical_complete"])
        with self.assertRaises(sm.SelectionError):
            self.h.apply(h.decisions[0], h.sources[0])
        self.assertNotIn("SR2", sm.plan(self.h.base, self.h.state).data)

    def test_json_records_reject_nonfinite_and_noncanonical_content(self):
        for raw in (b'{"x":1e999}', b'{"x":NaN}', b'{"x":1,"x":2}', b'{ "x":1}'):
            with self.subTest(raw=raw), self.assertRaises(sm.SelectionError):
                sm.Record(raw)
        with self.assertRaises(sm.SelectionError):
            sm.Record.of({"x": float("inf")})
        spec = specification(); spec["inputs"]["fixture"] = "not-a-hash"
        with self.assertRaises(sm.SelectionError):
            sm.Selection.start(spec)


if __name__ == "__main__":
    unittest.main(verbosity=2)
