from enum import Enum
from typing import Generic, Optional, TypeVar
from pydantic import BaseModel, ConfigDict

T = TypeVar("T")


class UserRoleEnum(str, Enum):
    """Platform user roles."""
    CUSTOMER = "customer"
    MERCHANT = "merchant"


class ApiResponse(BaseModel, Generic[T]):
    """Standardized API response envelope."""
    model_config = ConfigDict(from_attributes=True)

    success: bool = True
    message: Optional[str] = None
    data: Optional[T] = None


class ErrorResponse(BaseModel):
    """Standardized error response payload."""
    success: bool = False
    error: str
    details: Optional[dict] = None
    path: Optional[str] = None
