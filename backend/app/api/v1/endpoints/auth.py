from typing import Optional

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app.core.supabase import get_supabase_client

router = APIRouter()


class CustomerRegisterRequest(BaseModel):
    email: str
    password: str
    full_name: str
    account_type: str = "personal"
    mobile: Optional[str] = None


class MerchantRegisterRequest(BaseModel):
    email: str
    password: str
    business_name: str
    owner_name: str
    mobile: Optional[str] = None
    business_address: Optional[str] = None
    registration_number: Optional[str] = None
    gst_number: Optional[str] = None
    categories: list[str] = []


def _create_user(email: str, password: str, metadata: dict) -> str:
    client = get_supabase_client()
    if client is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Supabase is not configured.")
    if len(password) < 8:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 8 characters.")
    try:
        response = client.auth.admin.create_user(
            {
                "email": email,
                "password": password,
                "email_confirm": True,
                "user_metadata": metadata,
            }
        )
    except Exception as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    user = getattr(response, "user", None)
    if user is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User creation failed.")
    return str(getattr(user, "id", ""))


@router.post("/register/customer", summary="Register a customer account")
async def register_customer(payload: CustomerRegisterRequest):
    user_id = _create_user(
        payload.email,
        payload.password,
        {
            "full_name": payload.full_name,
            "role": "customer",
            "account_type": payload.account_type,
            "mobile": payload.mobile,
        },
    )
    return {"id": user_id, "email": payload.email, "role": "customer"}


@router.post("/register/merchant", summary="Register a merchant account")
async def register_merchant(payload: MerchantRegisterRequest):
    user_id = _create_user(
        payload.email,
        payload.password,
        {
            "full_name": payload.owner_name,
            "role": "merchant",
            "company": payload.business_name,
            "mobile": payload.mobile,
            "business_address": payload.business_address,
            "registration_number": payload.registration_number,
            "gst_number": payload.gst_number,
            "categories": payload.categories,
        },
    )
    return {"id": user_id, "email": payload.email, "role": "merchant"}
