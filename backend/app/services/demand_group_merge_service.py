from dataclasses import dataclass
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
from typing import Any, Mapping, Optional, Sequence

from app.core.supabase import get_supabase_service_client
from app.services.demand_family_taxonomy import canonical_demand_family


class MergePlanError(ValueError):
    pass


class RedirectIntegrityError(ValueError):
    pass


@dataclass(frozen=True)
class CustomerMembershipPlan:
    customer_id: str
    representative_demand_id: str
    quantity_committed: Decimal
    historical_group_ids: tuple[str, ...]


@dataclass(frozen=True)
class GroupMergePlan:
    survivor_group_id: str
    source_group_id: str
    expected_total_quantity: Decimal
    expected_demand_ids: tuple[str, ...]
    product_family_key: str
    category_key: str
    memberships: tuple[CustomerMembershipPlan, ...]
    proposal_snapshot: Mapping[str, Any]
    idempotency_key: str

    def as_dict(self) -> dict[str, Any]:
        return {
            "status": "ready_for_approval",
            "survivor_group_id": self.survivor_group_id,
            "source_group_id": self.source_group_id,
            "expected_total_quantity": str(self.expected_total_quantity),
            "expected_demand_ids": list(self.expected_demand_ids),
            "product_family_key": self.product_family_key,
            "category_key": self.category_key,
            "memberships": [
                {
                    "customer_id": membership.customer_id,
                    "representative_demand_id": membership.representative_demand_id,
                    "quantity_committed": str(membership.quantity_committed),
                    "historical_group_ids": list(membership.historical_group_ids),
                }
                for membership in self.memberships
            ],
            "proposal_snapshot": self.proposal_snapshot,
            "idempotency_key": self.idempotency_key,
            "database_preconditions_pending": True,
        }


def _quantity(value: Any, reason: str) -> Decimal:
    try:
        quantity = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        raise MergePlanError(reason) from None
    if not quantity.is_finite() or quantity <= 0:
        raise MergePlanError(reason)
    return quantity


def _created_key(row: Mapping[str, Any]) -> tuple[str, str]:
    created_at = row.get("created_at")
    if not created_at:
        raise MergePlanError("created_at_missing")
    return str(created_at), str(row.get("id") or "")


def _snapshot_number(value: Any) -> Optional[str]:
    if value is None:
        return None
    try:
        number = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        raise MergePlanError("snapshot_number_invalid") from None
    if not number.is_finite():
        raise MergePlanError("snapshot_number_invalid")
    return format(number.normalize(), "f")


def _snapshot_timestamp(value: Any) -> Optional[str]:
    if value is None:
        return None
    try:
        parsed = value if isinstance(value, datetime) else datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        raise MergePlanError("snapshot_timestamp_invalid") from None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _snapshot_date(value: Any) -> Optional[str]:
    if value is None:
        return None
    try:
        parsed = value.date() if isinstance(value, datetime) else value
        if not isinstance(parsed, date):
            parsed = date.fromisoformat(str(parsed))
    except ValueError:
        raise MergePlanError("snapshot_date_invalid") from None
    return parsed.isoformat()


def _snapshot_group(group: Mapping[str, Any]) -> dict[str, Optional[str]]:
    numeric_fields = {
        "offers_count", "lowest_offer_price", "threshold_quantity", "total_quantity",
        "total_requested_quantity", "participants_count", "participating_demand_count",
    }
    timestamp_fields = {"created_at", "updated_at", "approved_at", "bidding_start", "bidding_deadline"}
    fields = (
        "id", "created_at", "updated_at", "product_title", "category", "group_status",
        "status", "bidding_status", "approved_at", "approved_by", "bidding_start",
        "bidding_deadline", "offers_count", "lowest_offer_price", "top_offer_merchant",
        "threshold_quantity", "deadline", "currency", "total_quantity",
        "total_requested_quantity", "participants_count", "participating_demand_count",
    )
    snapshot = {}
    for field in fields:
        value = group.get(field)
        if field in numeric_fields:
            snapshot[field] = _snapshot_number(value)
        elif field in timestamp_fields:
            snapshot[field] = _snapshot_timestamp(value)
        elif field == "deadline":
            snapshot[field] = _snapshot_date(value)
        else:
            snapshot[field] = str(value) if value is not None else None
    return snapshot


def _snapshot_demand(demand: Mapping[str, Any]) -> dict[str, Optional[str]]:
    numeric_fields = {"target_quantity", "target_price", "maximum_budget"}
    timestamp_fields = {"created_at", "updated_at"}
    fields = (
        "id", "group_id", "customer_id", "title", "category", "status",
        "target_quantity", "target_price", "maximum_budget", "created_at", "updated_at",
    )
    return {
        field: (
            _snapshot_number(demand.get(field)) if field in numeric_fields
            else _snapshot_timestamp(demand.get(field)) if field in timestamp_fields
            else str(demand[field]) if demand.get(field) is not None
            else None
        )
        for field in fields
    }


def _snapshot_membership(membership: Mapping[str, Any]) -> dict[str, Optional[str]]:
    numeric_fields = {"quantity_committed", "original_target_price", "original_budget"}
    timestamp_fields = {"joined_at", "removed_at"}
    fields = (
        "group_id", "customer_id", "demand_id", "quantity_committed", "joined_at",
        "original_target_price", "original_budget", "membership_status", "removed_at",
    )
    return {
        field: (
            _snapshot_number(membership.get(field)) if field in numeric_fields
            else _snapshot_timestamp(membership.get(field)) if field in timestamp_fields
            else str(membership[field]) if membership.get(field) is not None
            else None
        )
        for field in fields
    }


def _snapshot_redirect(redirect: Mapping[str, Any]) -> dict[str, Optional[str]]:
    snapshot = {
        field: str(redirect[field]) if redirect.get(field) is not None else None
        for field in ("source_group_id", "target_group_id", "merge_request_id", "merged_by")
    }
    snapshot["merged_at"] = _snapshot_timestamp(redirect.get("merged_at"))
    return snapshot


def _canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _metadata_conflicts(memberships: Sequence[Mapping[str, Any]]) -> bool:
    for field in ("original_target_price", "original_budget"):
        values = set()
        for row in memberships:
            value = row.get(field)
            if value is None:
                continue
            try:
                numeric_value = Decimal(str(value))
            except (InvalidOperation, ValueError, TypeError):
                return True
            if not numeric_value.is_finite():
                return True
            values.add(numeric_value)
        if len(values) > 1:
            return True
    return False


def plan_group_merge(
    survivor_group: Mapping[str, Any],
    source_group: Mapping[str, Any],
    demands: Sequence[Mapping[str, Any]],
    memberships: Sequence[Mapping[str, Any]],
    compatibility_status: str,
    blockers: Sequence[str] = (),
    redirects: Sequence[Mapping[str, Any]] = (),
) -> GroupMergePlan:
    """Build a non-mutating merge proposal after application-level validation."""
    survivor_id = str(survivor_group.get("id") or "")
    source_id = str(source_group.get("id") or "")
    if not survivor_id or not source_id or survivor_id == source_id:
        raise MergePlanError("distinct_group_ids_required")
    if blockers:
        raise MergePlanError("blocking_reference:" + ",".join(sorted(set(blockers))))
    if compatibility_status != "compatible":
        raise MergePlanError("compatibility_not_approved")

    if _created_key(survivor_group) > _created_key(source_group):
        raise MergePlanError("survivor_must_be_earliest_created")

    for group in (survivor_group, source_group):
        if (
            group.get("group_status") != "Proposed"
            or group.get("status") != "Forming"
            or group.get("bidding_status") != "closed"
            or group.get("approved_at") is not None
            or group.get("approved_by") is not None
            or group.get("bidding_start") is not None
            or group.get("bidding_deadline") is not None
            or group.get("offers_count") != 0
            or group.get("lowest_offer_price") is not None
            or group.get("top_offer_merchant") is not None
        ):
            raise MergePlanError("group_lifecycle_or_offer_state_blocks_merge")
    for field in ("threshold_quantity", "deadline", "currency"):
        if survivor_group.get(field) != source_group.get(field):
            raise MergePlanError("group_metadata_conflict:" + field)

    survivor_family = canonical_demand_family(
        str(survivor_group.get("product_title") or ""),
        str(survivor_group.get("category") or ""),
    )
    source_family = canonical_demand_family(
        str(source_group.get("product_title") or ""),
        str(source_group.get("category") or ""),
    )
    if survivor_family is None or source_family is None:
        raise MergePlanError("canonical_family_needs_review")
    if survivor_family != source_family:
        raise MergePlanError("canonical_family_mismatch")

    group_ids = {survivor_id, source_id}
    redirect_rows = [
        row for row in redirects
        if str(row.get("source_group_id") or "") in group_ids
        or str(row.get("target_group_id") or "") in group_ids
    ]
    if any(str(row.get("source_group_id") or "") in group_ids for row in redirect_rows):
        raise MergePlanError("blocking_reference:redirect")
    demand_rows = [row for row in demands if str(row.get("group_id")) in group_ids]
    if not demand_rows or any(not row.get("id") or not row.get("customer_id") for row in demand_rows):
        raise MergePlanError("demand_link_or_customer_missing")
    if any(row.get("status") not in {"Submitted", "Under Review"} for row in demand_rows):
        raise MergePlanError("demand_status_blocks_merge")
    demand_ids = [str(row["id"]) for row in demand_rows]
    if len(set(demand_ids)) != len(demand_ids):
        raise MergePlanError("duplicate_demand_id")

    demand_groups: dict[str, dict[str, list[Mapping[str, Any]]]] = {
        survivor_id: {},
        source_id: {},
    }
    for row in demand_rows:
        quantity = _quantity(row.get("target_quantity"), "demand_quantity_invalid")
        customer_id = str(row["customer_id"])
        demand_groups[str(row["group_id"])].setdefault(customer_id, []).append(
            {**row, "_quantity": quantity}
        )

    membership_index: dict[tuple[str, str], list[Mapping[str, Any]]] = {}
    for membership in memberships:
        group_id = str(membership.get("group_id") or "")
        customer_id = str(membership.get("customer_id") or "")
        if group_id in group_ids and customer_id:
            membership_index.setdefault((group_id, customer_id), []).append(membership)

    group_totals: dict[str, Decimal] = {survivor_id: Decimal(0), source_id: Decimal(0)}
    memberships_by_customer: dict[str, list[Mapping[str, Any]]] = {}
    for group_id, customers in demand_groups.items():
        for customer_id, rows in customers.items():
            rows.sort(key=_created_key)
            quantity = sum((row["_quantity"] for row in rows), Decimal(0))
            group_totals[group_id] += quantity
            member_rows = membership_index.get((group_id, customer_id), [])
            if len(member_rows) != 1:
                raise MergePlanError("membership_missing_or_duplicated")
            membership = member_rows[0]
            if (
                membership.get("membership_status") != "active"
                or membership.get("removed_at") is not None
                or str(membership.get("demand_id") or "") != str(rows[0]["id"])
            ):
                raise MergePlanError("membership_state_or_representative_mismatch")
            if _quantity(membership.get("quantity_committed"), "membership_quantity_invalid") != quantity:
                raise MergePlanError("membership_quantity_mismatch")
            memberships_by_customer.setdefault(customer_id, []).append(membership)

    expected_keys = {
        (group_id, customer_id)
        for group_id, customers in demand_groups.items()
        for customer_id in customers
    }
    if set(membership_index) != expected_keys:
        raise MergePlanError("unexpected_or_orphan_membership")

    expected_total = group_totals[survivor_id] + group_totals[source_id]
    if _quantity(survivor_group.get("total_quantity"), "group_quantity_invalid") != group_totals[survivor_id]:
        raise MergePlanError("survivor_group_quantity_mismatch")
    if _quantity(source_group.get("total_quantity"), "group_quantity_invalid") != group_totals[source_id]:
        raise MergePlanError("source_group_quantity_mismatch")
    if (
        survivor_group.get("participants_count") != len(demand_groups[survivor_id])
        or source_group.get("participants_count") != len(demand_groups[source_id])
        or survivor_group.get("participating_demand_count") != sum(map(len, demand_groups[survivor_id].values()))
        or source_group.get("participating_demand_count") != sum(map(len, demand_groups[source_id].values()))
    ):
        raise MergePlanError("group_counters_mismatch")

    customer_plans = []
    for customer_id, rows in sorted(memberships_by_customer.items()):
        if _metadata_conflicts(rows):
            raise MergePlanError("original_membership_metadata_conflict")
        customer_demands = [
            row
            for group_rows in demand_groups.values()
            for row in group_rows.get(customer_id, [])
        ]
        customer_demands.sort(key=_created_key)
        customer_plans.append(CustomerMembershipPlan(
            customer_id=customer_id,
            representative_demand_id=str(customer_demands[0]["id"]),
            quantity_committed=sum((row["_quantity"] for row in customer_demands), Decimal(0)),
            historical_group_ids=tuple(sorted({str(row["group_id"]) for row in rows})),
        ))

    expected_demand_ids = tuple(
        str(row["id"]) for row in sorted(demand_rows, key=_created_key)
    )
    proposal_snapshot = {
        "canonical_family": {
            "product_family_key": survivor_family.product_family_key,
            "category_key": survivor_family.category_key,
        },
        "groups": sorted((_snapshot_group(group) for group in (survivor_group, source_group)), key=lambda row: row["id"] or ""),
        "demands": sorted(
            (_snapshot_demand(row) for row in demand_rows),
            key=lambda row: row["id"] or "",
        ),
        "memberships": sorted(
            (_snapshot_membership(member) for member_rows in membership_index.values() for member in member_rows),
            key=lambda row: (row["group_id"] or "", row["customer_id"] or ""),
        ),
        "redirects": sorted(
            (_snapshot_redirect(row) for row in redirect_rows),
            key=lambda row: row["source_group_id"] or "",
        ),
        "review_ids": [],
        "offer_ids": [],
        "selection_ids": [],
        "order_ids": [],
    }
    idempotency_payload = {
        "proposal_snapshot": proposal_snapshot,
        "expected_total_quantity": str(expected_total),
        "expected_demand_ids": list(expected_demand_ids),
        "product_family_key": survivor_family.product_family_key,
        "category_key": survivor_family.category_key,
    }
    idempotency_key = hashlib.sha256(_canonical_json(idempotency_payload).encode("utf-8")).hexdigest()
    return GroupMergePlan(
        survivor_group_id=survivor_id,
        source_group_id=source_id,
        expected_total_quantity=expected_total,
        expected_demand_ids=expected_demand_ids,
        product_family_key=survivor_family.product_family_key,
        category_key=survivor_family.category_key,
        memberships=tuple(customer_plans),
        proposal_snapshot=proposal_snapshot,
        idempotency_key=idempotency_key,
    )


def resolve_redirect_target(group_id: str, redirects: Mapping[str, str]) -> str:
    """Resolve one flat redirect and reject corrupt chains or cycles."""
    target = redirects.get(group_id)
    if target is None:
        return group_id
    if target == group_id or target in redirects:
        raise RedirectIntegrityError("redirect_chain_or_cycle")
    return target


def resolve_group_id(group_id: str, client: Any = None) -> str:
    return resolve_group_ids([group_id], client=client)[str(group_id)]


def resolve_group_ids(group_ids: Sequence[str], client: Any = None) -> dict[str, str]:
    requested_ids = sorted({str(group_id) for group_id in group_ids})
    if not requested_ids:
        return {}
    if client is None:
        client = get_supabase_service_client()
    if client is None:
        raise RuntimeError("service_role_client_unavailable")
    response = (
        client.table("demand_group_redirects")
        .select("source_group_id,target_group_id")
        .in_("source_group_id", requested_ids)
        .execute()
    )
    redirects = {
        str(row["source_group_id"]): str(row["target_group_id"])
        for row in (getattr(response, "data", None) or [])
        if row.get("source_group_id") and row.get("target_group_id")
    }
    possible_targets = sorted(set(redirects.values()) - set(requested_ids))
    if possible_targets:
        downstream = (
            client.table("demand_group_redirects")
            .select("source_group_id,target_group_id")
            .in_("source_group_id", possible_targets)
            .execute()
        )
        if getattr(downstream, "data", None):
            raise RedirectIntegrityError("redirect_chain_or_cycle")
    return {
        group_id: resolve_redirect_target(group_id, redirects)
        for group_id in requested_ids
    }


def create_merge_request(
    plan: GroupMergePlan,
    requested_by: str,
    client: Any = None,
    compatibility_report: Optional[Mapping[str, Any]] = None,
) -> dict[str, Any]:
    """Persist a proposal only when explicitly called; this does not merge groups."""
    if (
        not isinstance(compatibility_report, Mapping)
        or compatibility_report.get("status") != "compatible"
        or not isinstance(compatibility_report.get("normalized_revisions"), list)
        or len(compatibility_report["normalized_revisions"]) != len(plan.expected_demand_ids)
        or {
            str(revision.get("demand_id"))
            for revision in compatibility_report["normalized_revisions"]
            if isinstance(revision, Mapping)
            and revision.get("demand_id")
            and revision.get("demand_updated_at")
            and revision.get("normalized_updated_at")
            and isinstance(revision.get("normalized_snapshot"), Mapping)
        } != set(plan.expected_demand_ids)
    ):
        raise MergePlanError("compatibility_revision_snapshot_required")
    if client is None:
        client = get_supabase_service_client()
    if client is None:
        raise RuntimeError("service_role_client_unavailable")
    serialized_report = _canonical_json(dict(compatibility_report))
    request_idempotency_key = hashlib.sha256(
        f"{plan.idempotency_key}|{serialized_report}".encode("utf-8")
    ).hexdigest()
    result = client.rpc("propose_demand_group_merge_v1", {
        "p_survivor_group_id": plan.survivor_group_id,
        "p_source_group_id": plan.source_group_id,
        "p_expected_total_quantity": str(plan.expected_total_quantity),
        "p_expected_demand_ids": list(plan.expected_demand_ids),
        "p_product_family_key": plan.product_family_key,
        "p_category_key": plan.category_key,
        "p_idempotency_key": request_idempotency_key,
        "p_requested_by": requested_by,
        "p_compatibility_report": dict(compatibility_report),
        "p_proposal_snapshot": dict(plan.proposal_snapshot),
    }).execute()
    data = getattr(result, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    if not isinstance(data, Mapping):
        raise RuntimeError("merge_request_creation_failed")
    return dict(data)


def approve_merge_request(
    request_id: str,
    approved_by: str,
    client: Any = None,
) -> dict[str, Any]:
    """Record explicit approval without executing the merge."""
    if client is None:
        client = get_supabase_service_client()
    if client is None:
        raise RuntimeError("service_role_client_unavailable")
    result = client.rpc("approve_demand_group_merge_v1", {
        "p_request_id": request_id,
        "p_approved_by": approved_by,
    }).execute()
    data = getattr(result, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    if not isinstance(data, Mapping):
        raise RuntimeError("merge_request_approval_failed")
    return dict(data)


def execute_approved_merge(request_id: str, client: Any = None) -> dict[str, Any]:
    """Invoke the separately approved, transaction-backed merge RPC."""
    if client is None:
        client = get_supabase_service_client()
    if client is None:
        raise RuntimeError("service_role_client_unavailable")
    result = client.rpc("merge_demand_group_request_v1", {"p_request_id": request_id}).execute()
    data = getattr(result, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    if not isinstance(data, Mapping):
        raise RuntimeError("group_merge_failed")
    return dict(data)