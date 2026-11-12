import logging
from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import require_roles
from app.services.demand_group_merge_service import resolve_group_id, resolve_group_ids
from app.core.supabase import get_supabase_client
from app.services.demand_group_submission_service import try_group_new_demand

logger = logging.getLogger("markettwin.api.grouping")
router = APIRouter()


@router.get("/customer/groups")
async def customer_groups(current_user=Depends(require_roles("customer"))):
    client = get_supabase_client()
    if client is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Supabase is not configured.")
    # Find demand_ids for this customer
    demands = client.table("demands").select("id").eq("customer_id", current_user["id"]).execute()
    demand_ids = [d["id"] for d in (demands.data or [])]
    if not demand_ids:
        return {"items": []}
    members = (
        client.table("demand_group_members")
        .select("group_id")
        .eq("membership_status", "active")
        .in_("demand_id", demand_ids)
        .execute()
    )
    group_ids = sorted({m["group_id"] for m in (members.data or [])})
    if not group_ids:
        return {"items": []}
    canonical_ids = sorted(set(resolve_group_ids(group_ids, client=client).values()))
    groups = client.table("demand_groups").select("*").in_("id", canonical_ids).execute()
    return {"items": groups.data or []}


@router.get("/customer/groups/{group_id}")
async def customer_group_detail(group_id: str, current_user=Depends(require_roles("customer"))):
    client = get_supabase_client()
    if client is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Supabase is not configured.")
    group_id = resolve_group_id(group_id, client=client)
    group = client.table("demand_groups").select("*").eq("id", group_id).single().execute()
    if not group.data:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found.")
    # verify membership
    demands = client.table("demands").select("id").eq("customer_id", current_user["id"]).execute()
    demand_ids = [d["id"] for d in (demands.data or [])]
    members = (
        client.table("demand_group_members")
        .select("*")
        .eq("group_id", group_id)
        .eq("membership_status", "active")
        .in_("demand_id", demand_ids)
        .execute()
    )
    if not members.data:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied.")
    return {"group": group.data, "membership": members.data}
