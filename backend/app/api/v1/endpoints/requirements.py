import logging
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import get_current_user, require_roles
from app.schemas.requirement import NormalizedRequirementResponse, RequirementReviewRequest
from app.services.demand_service import get_demand
from app.services.normalized_requirement_service import extract_and_save, get_normalized, review_normalized

logger = logging.getLogger("markettwin.api.requirements")
router = APIRouter()


def _to_response(row: Dict[str, Any]) -> NormalizedRequirementResponse:
    return NormalizedRequirementResponse(
        id=str(row.get("id")),
        demand_id=str(row.get("demand_id")),
        extraction_version=row.get("extraction_version") or "v1",
        product_type=row.get("product_type"),
        normalized_product_name=row.get("normalized_product_name"),
        normalized_category=row.get("normalized_category"),
        normalized_material=row.get("normalized_material"),
        normalized_specifications=row.get("normalized_specifications") or {},
        normalized_dimensions=row.get("normalized_dimensions") or {},
        mandatory_requirements=row.get("mandatory_requirements") or [],
        optional_preferences=row.get("optional_preferences") or [],
        commercial_constraints=row.get("commercial_constraints") or {},
        delivery_constraints=row.get("delivery_constraints") or {},
        missing_information=row.get("missing_information") or [],
        clarification_questions=row.get("clarification_questions") or [],
        validation_errors=row.get("validation_errors") or [],
        confidence_score=row.get("confidence_score"),
        status=row.get("status") or "Pending",
        reviewed_by=row.get("reviewed_by"),
        reviewed_at=row.get("reviewed_at"),
        created_at=row.get("created_at"),
        updated_at=row.get("updated_at"),
    )


@router.post("/customer/demands/{demand_id}/requirement-status")
async def customer_requirement_status(demand_id: str, current_user=Depends(require_roles("customer"))):
    demand = get_demand(current_user["id"], demand_id)
    if not demand:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Demand not found.")
    row = get_normalized(demand_id)
    if not row:
        return {"status": "Pending", "clarification_questions": []}
    return {
        "status": row.get("status"),
        "clarification_questions": row.get("clarification_questions") or [],
        "missing_information": row.get("missing_information") or [],
    }