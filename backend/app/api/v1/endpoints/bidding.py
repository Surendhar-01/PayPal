import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import get_current_user, require_roles
from app.schemas.bidding import MerchantOfferListResponse, MerchantOfferResponse, OfferReviseRequest, OfferSubmitRequest
from app.services.bidding_service import (
    get_active_demand,
    get_group,
    list_active_demands,
    list_merchant_offers,
    list_open_groups,
    merchant_is_approved,
    submit_demand_offer,
    submit_offer,
    revise_offer,
    OfferConflict,
)

logger = logging.getLogger("markettwin.api.bidding")
router = APIRouter()


@router.get("/merchant/demands")
async def merchant_available_demands(current_user=Depends(require_roles("merchant"))):
    """List every active customer demand visible to registered merchants."""
    return {"items": list_active_demands()}


@router.get("/merchant/demands/{demand_id}")
async def merchant_demand_detail(demand_id: str, current_user=Depends(require_roles("merchant"))):
    demand = get_active_demand(demand_id)
    if not demand:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Demand not found or no longer available.",
        )
    return {"demand": demand}


@router.post(
    "/merchant/demands/{demand_id}/offers",
    status_code=status.HTTP_201_CREATED,
    response_model=MerchantOfferResponse,
)
async def merchant_submit_demand_offer(
    demand_id: str,
    payload: OfferSubmitRequest,
    current_user=Depends(require_roles("merchant")),
):
    try:
        return submit_demand_offer(current_user["id"], demand_id, payload.model_dump())
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except OfferConflict as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Offer submission is unavailable. Refresh My Offers before retrying.",
        )


@router.get("/merchant/demand-groups")
async def merchant_demand_groups(current_user=Depends(require_roles("merchant"))):
    if not merchant_is_approved(current_user["id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant account is not approved.")
    return {"items": list_open_groups()}


@router.get("/merchant/demand-groups/{group_id}")
async def merchant_demand_group_detail(group_id: str, current_user=Depends(require_roles("merchant"))):
    if not merchant_is_approved(current_user["id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant account is not approved.")
    group = get_group(group_id)
    if not group or group.get("bidding_status") != "open":
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bidding opportunity not found.")
    return {"group": group}


@router.post("/merchant/demand-groups/{group_id}/offers", status_code=status.HTTP_201_CREATED, response_model=MerchantOfferResponse)
async def merchant_submit_offer(group_id: str, payload: OfferSubmitRequest, current_user=Depends(require_roles("merchant"))):
    if not merchant_is_approved(current_user["id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant account is not approved.")
    try:
        offer = submit_offer(current_user["id"], group_id, payload.model_dump())
        return offer
    except OfferConflict as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Offer submission is unavailable. Refresh My Offers before retrying.")


@router.patch("/merchant/offers/{offer_id}", response_model=MerchantOfferResponse)
async def merchant_revise_offer(offer_id: str, payload: OfferReviseRequest, current_user=Depends(require_roles("merchant"))):
    if not merchant_is_approved(current_user["id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant account is not approved.")
    try:
        return revise_offer(current_user["id"], offer_id, payload.model_dump())
    except OfferConflict as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc))
    except Exception:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Offer revision is unavailable. Refresh My Offers before retrying.")


@router.get("/merchant/offers", response_model=MerchantOfferListResponse)
async def merchant_offers(current_user=Depends(require_roles("merchant"))):
    if not merchant_is_approved(current_user["id"]):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant account is not approved.")
    return {"items": list_merchant_offers(current_user["id"])}