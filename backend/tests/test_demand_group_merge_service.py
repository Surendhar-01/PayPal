from copy import deepcopy
from decimal import Decimal

import pytest

from app.services.demand_group_merge_service import (
    MergePlanError,
    RedirectIntegrityError,
    approve_merge_request,
    create_merge_request,
    execute_approved_merge,
    plan_group_merge,
    resolve_redirect_target,
)


SURVIVOR_ID = "d1a44ed5-f108-40a1-94bc-5158953c056f"
SOURCE_ID = "22155daf-83dd-45b2-9ce0-0f79834bf209"
EARLIER_DEMAND_ID = "434b388d-c91e-484a-a5c1-9c12cd4c71c5"
LATER_DEMAND_ID = "576178d6-3fa1-4c3d-a5ba-114f587de39d"


def _group(group_id, title, created_at, quantity, category="Computers"):
    return {
        "id": group_id,
        "product_title": title,
        "category": category,
        "group_status": "Proposed",
        "status": "Forming",
        "bidding_status": "closed",
        "approved_at": None,
        "approved_by": None,
        "bidding_start": None,
        "bidding_deadline": None,
        "offers_count": 0,
        "lowest_offer_price": None,
        "top_offer_merchant": None,
        "threshold_quantity": 1,
        "deadline": None,
        "currency": None,
        "total_quantity": quantity,
        "total_requested_quantity": quantity,
        "participants_count": 1,
        "participating_demand_count": 1,
        "created_at": created_at,
    }


def _current_pair_data():
    survivor = _group(SURVIVOR_ID, "laptop suitable", "2026-11-08T06:10:00Z", 1)
    source = _group(SOURCE_ID, "reliable laptop", "2026-11-08T07:04:30Z", 2)
    demands = [
        {
            "id": EARLIER_DEMAND_ID,
            "group_id": SURVIVOR_ID,
            "customer_id": "customer-a",
            "target_quantity": 1,
            "status": "Submitted",
            "created_at": "2026-11-08T06:10:00Z",
        },
        {
            "id": LATER_DEMAND_ID,
            "group_id": SOURCE_ID,
            "customer_id": "customer-a",
            "target_quantity": 2,
            "status": "Submitted",
            "created_at": "2026-11-08T07:04:30Z",
        },
    ]
    memberships = [
        {
            "group_id": SURVIVOR_ID,
            "customer_id": "customer-a",
            "demand_id": EARLIER_DEMAND_ID,
            "quantity_committed": 1,
            "membership_status": "active",
            "removed_at": None,
            "joined_at": "2026-11-08T06:10:00Z",
            "original_target_price": None,
            "original_budget": None,
        },
        {
            "group_id": SOURCE_ID,
            "customer_id": "customer-a",
            "demand_id": LATER_DEMAND_ID,
            "quantity_committed": 2,
            "membership_status": "active",
            "removed_at": None,
            "joined_at": "2026-11-08T07:04:30Z",
            "original_target_price": None,
            "original_budget": None,
        },
    ]
    return survivor, source, demands, memberships


def _plan(survivor, source, demands, memberships, blockers=()):
    return plan_group_merge(
        survivor,
        source,
        demands,
        memberships,
        compatibility_status="compatible",
        blockers=blockers,
    )


def test_same_customer_quantities_aggregate_and_representative_is_earliest():
    survivor, source, demands, memberships = _current_pair_data()

    plan = _plan(survivor, source, demands, memberships)

    assert plan.expected_total_quantity == Decimal("3")
    assert plan.expected_demand_ids == (EARLIER_DEMAND_ID, LATER_DEMAND_ID)
    assert len(plan.memberships) == 1
    assert plan.memberships[0].quantity_committed == Decimal("3")
    assert plan.memberships[0].representative_demand_id == EARLIER_DEMAND_ID
    assert plan.memberships[0].historical_group_ids == tuple(sorted((SURVIVOR_ID, SOURCE_ID)))


def test_different_customers_remain_separate_memberships():
    survivor = _group("group-a", "laptop suitable", "2026-01-01T00:00:00Z", 1)
    source = _group("group-b", "reliable laptop", "2026-01-02T00:00:00Z", 2)
    demands = [
        {"id": "demand-a", "group_id": "group-a", "customer_id": "customer-a", "target_quantity": 1, "status": "Submitted", "created_at": "2026-01-01T00:00:00Z"},
        {"id": "demand-b", "group_id": "group-b", "customer_id": "customer-b", "target_quantity": 2, "status": "Submitted", "created_at": "2026-01-02T00:00:00Z"},
    ]
    memberships = [
        {"group_id": "group-a", "customer_id": "customer-a", "demand_id": "demand-a", "quantity_committed": 1, "membership_status": "active", "removed_at": None},
        {"group_id": "group-b", "customer_id": "customer-b", "demand_id": "demand-b", "quantity_committed": 2, "membership_status": "active", "removed_at": None},
    ]

    plan = _plan(survivor, source, demands, memberships)

    assert {member.customer_id for member in plan.memberships} == {"customer-a", "customer-b"}
    assert {member.quantity_committed for member in plan.memberships} == {Decimal("1"), Decimal("2")}


def test_source_membership_is_retained_as_history_and_retries_are_stable():
    survivor, source, demands, memberships = _current_pair_data()

    first = _plan(survivor, source, demands, memberships)
    second = _plan(survivor, source, demands, memberships)

    assert SOURCE_ID in first.memberships[0].historical_group_ids
    assert first.idempotency_key == second.idempotency_key
    assert first.expected_total_quantity == second.expected_total_quantity == Decimal("3")


def test_group_and_membership_snapshot_changes_create_new_idempotency_keys():
    survivor, source, demands, memberships = _current_pair_data()
    original = _plan(survivor, source, demands, memberships)

    changed_survivor = deepcopy(survivor)
    changed_source = deepcopy(source)
    changed_survivor["threshold_quantity"] = 2
    changed_source["threshold_quantity"] = 2
    group_changed = _plan(changed_survivor, changed_source, demands, memberships)

    changed_memberships = deepcopy(memberships)
    changed_memberships[0]["original_budget"] = Decimal("100")
    changed_memberships[1]["original_budget"] = Decimal("100")
    membership_changed = _plan(survivor, source, demands, changed_memberships)

    assert original.idempotency_key != group_changed.idempotency_key
    assert original.idempotency_key != membership_changed.idempotency_key


def test_general_quantities_are_aggregated_without_pilot_pair_limits():
    survivor, source, demands, memberships = _current_pair_data()
    survivor["total_quantity"] = survivor["total_requested_quantity"] = 4
    source["total_quantity"] = source["total_requested_quantity"] = 5
    demands[0]["target_quantity"] = 4
    demands[1]["target_quantity"] = 5
    memberships[0]["quantity_committed"] = 4
    memberships[1]["quantity_committed"] = 5

    plan = _plan(survivor, source, demands, memberships)

    assert plan.expected_total_quantity == Decimal("9")
    assert plan.memberships[0].quantity_committed == Decimal("9")


@pytest.mark.parametrize("blocker", ["active_offer", "selection", "order", "review", "unexpected_reference"])
def test_downstream_blockers_reject_the_plan(blocker):
    survivor, source, demands, memberships = _current_pair_data()

    with pytest.raises(MergePlanError, match="blocking_reference"):
        _plan(survivor, source, demands, memberships, blockers=[blocker])


def test_inconsistent_quantity_or_missing_demand_link_rejects_the_plan():
    survivor, source, demands, memberships = _current_pair_data()
    bad_quantity = deepcopy(memberships)
    bad_quantity[1]["quantity_committed"] = 9
    with pytest.raises(MergePlanError, match="membership_quantity_mismatch"):
        _plan(survivor, source, demands, bad_quantity)

    missing_link = deepcopy(memberships)
    missing_link[0]["demand_id"] = None
    with pytest.raises(MergePlanError, match="membership_state_or_representative_mismatch"):
        _plan(survivor, source, demands, missing_link)


def test_conflicting_original_membership_metadata_rejects_the_plan():
    survivor, source, demands, memberships = _current_pair_data()
    memberships[0]["original_target_price"] = "100.00"
    memberships[1]["original_target_price"] = "110.00"

    with pytest.raises(MergePlanError, match="original_membership_metadata_conflict"):
        _plan(survivor, source, demands, memberships)


def test_lifecycle_mismatch_or_non_earliest_survivor_rejects_the_plan():
    survivor, source, demands, memberships = _current_pair_data()
    source["bidding_status"] = "open"
    with pytest.raises(MergePlanError, match="lifecycle"):
        _plan(survivor, source, demands, memberships)

    survivor, source, demands, memberships = _current_pair_data()
    with pytest.raises(MergePlanError, match="earliest_created"):
        _plan(source, survivor, demands, memberships)


def test_redirect_lookup_is_flat_and_rejects_chains_and_cycles():
    assert resolve_redirect_target("source", {"source": "survivor"}) == "survivor"
    assert resolve_redirect_target("survivor", {"source": "survivor"}) == "survivor"
    with pytest.raises(RedirectIntegrityError):
        resolve_redirect_target("source", {"source": "middle", "middle": "survivor"})
    with pytest.raises(RedirectIntegrityError):
        resolve_redirect_target("source", {"source": "source"})


def test_explicit_executor_calls_only_the_approved_merge_rpc():
    class RpcResult:
        data = {"status": "merged", "survivor_group_id": "survivor"}

    class RpcCall:
        def execute(self):
            return RpcResult()

    class FakeClient:
        def __init__(self):
            self.calls = []

        def rpc(self, name, params):
            self.calls.append((name, params))
            return RpcCall()

    client = FakeClient()
    result = execute_approved_merge("request-1", client=client)

    assert result["status"] == "merged"
    assert client.calls == [("merge_demand_group_request_v1", {"p_request_id": "request-1"})]


def test_proposal_and_approval_are_separate_explicit_rpc_calls():
    class RpcResult:
        data = {"id": "request-1", "request_status": "proposed"}

    class RpcCall:
        def execute(self):
            return RpcResult()

    class FakeClient:
        def __init__(self):
            self.calls = []

        def rpc(self, name, params):
            self.calls.append((name, params))
            return RpcCall()

    survivor, source, demands, memberships = _current_pair_data()
    plan = _plan(survivor, source, demands, memberships)
    client = FakeClient()

    proposal = create_merge_request(
        plan,
        "customer-1",
        client=client,
        compatibility_report={
            "status": "compatible",
            "reasons": [],
            "normalized_revisions": [
                {
                    "demand_id": demand_id,
                    "demand_updated_at": "2026-01-01T00:00:00Z",
                    "normalized_updated_at": "2026-01-01T00:00:00Z",
                    "normalized_snapshot": {"demand_id": demand_id, "version": 1},
                }
                for demand_id in plan.expected_demand_ids
            ],
        },
    )
    approval = approve_merge_request("request-1", "customer-2", client=client)

    assert proposal["request_status"] == "proposed"
    assert approval["request_status"] == "proposed"
    assert [name for name, _ in client.calls] == [
        "propose_demand_group_merge_v1",
        "approve_demand_group_merge_v1",
    ]
    assert client.calls[0][1]["p_compatibility_report"]["status"] == "compatible"
    assert client.calls[0][1]["p_proposal_snapshot"] == dict(plan.proposal_snapshot)
    assert "merge_demand_group_request_v1" not in [name for name, _ in client.calls]


def test_revised_snapshot_gets_a_new_stable_proposal_idempotency_key():
    class RpcResult:
        data = {"id": "request-1", "request_status": "proposed"}

    class RpcCall:
        def execute(self):
            return RpcResult()

    class FakeClient:
        def __init__(self):
            self.calls = []

        def rpc(self, name, params):
            self.calls.append((name, params))
            return RpcCall()

    survivor, source, demands, memberships = _current_pair_data()
    plan = _plan(survivor, source, demands, memberships)
    client = FakeClient()
    reports = [
        {
            "status": "compatible",
            "normalized_revisions": [
                {
                    "demand_id": demand_id,
                    "demand_updated_at": "2026-01-01T00:00:00Z",
                    "normalized_updated_at": revision_time,
                    "normalized_snapshot": {"demand_id": demand_id, "revision": revision_hash},
                }
                for demand_id in plan.expected_demand_ids
            ],
        }
        for revision_time, revision_hash in (
            ("2026-01-01T00:00:00Z", "same"),
            ("2026-01-01T00:00:00Z", "changed"),
            ("2026-01-01T00:00:00Z", "changed"),
        )
    ]

    for report in reports:
        create_merge_request(plan, "customer-1", client=client, compatibility_report=report)

    keys = [params["p_idempotency_key"] for _, params in client.calls]
    assert keys[0] != keys[1]
    assert keys[1] == keys[2]


def test_merge_plan_report_contains_reviewable_expected_totals_and_identity():
    survivor, source, demands, memberships = _current_pair_data()

    report = _plan(survivor, source, demands, memberships).as_dict()

    assert report["status"] == "ready_for_approval"
    assert report["expected_total_quantity"] == "3"
    assert report["survivor_group_id"] == SURVIVOR_ID
    assert report["source_group_id"] == SOURCE_ID
    assert report["idempotency_key"]
    assert report["database_preconditions_pending"] is True