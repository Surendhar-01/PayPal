import base64
import hashlib
import hmac
import json
import logging
import re
import time
from typing import Any, Dict, List, Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.supabase import get_supabase_client

logger = logging.getLogger("markettwin.security")
bearer_scheme = HTTPBearer(auto_error=False)
_JWT_PATTERN = re.compile(r"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{10,}")
_API_KEY_PATTERN = re.compile(r"\bsb_(?:secret|publishable)_[A-Za-z0-9_-]+\b", re.IGNORECASE)
_TOKEN_DIGEST_PATTERN = re.compile(r"[0-9a-f]{64}")


def _unverified_jwt_claims(token: str) -> Dict[str, Any]:
    claims: Dict[str, Any] = {"iss": None, "aud": None, "exp": None, "role": None}
    try:
        payload_segment = token.split(".")[1]
        payload = json.loads(
            base64.urlsafe_b64decode(payload_segment + "=" * (-len(payload_segment) % 4))
        )
    except (IndexError, TypeError, ValueError, json.JSONDecodeError):
        return claims

    if not isinstance(payload, dict):
        return claims

    issuer = payload.get("iss")
    if isinstance(issuer, str):
        claims["iss"] = re.sub(r"[^A-Za-z0-9._:/-]", "?", issuer)[:160]

    audience = payload.get("aud")
    if isinstance(audience, str):
        claims["aud"] = re.sub(r"[^A-Za-z0-9._:-]", "?", audience)[:80]
    elif isinstance(audience, list):
        claims["aud"] = [
            re.sub(r"[^A-Za-z0-9._:-]", "?", item)[:80]
            for item in audience[:5]
            if isinstance(item, str)
        ]

    expiry = payload.get("exp")
    if isinstance(expiry, (int, float)) and not isinstance(expiry, bool):
        claims["exp"] = expiry

    role = payload.get("role")
    if isinstance(role, str):
        claims["role"] = re.sub(r"[^A-Za-z0-9_-]", "?", role)[:40]
    return claims


def _safe_auth_error_message(exc: Exception) -> str:
    message = getattr(exc, "message", None)
    if not isinstance(message, str):
        message = str(exc)
    message = _JWT_PATTERN.sub("[redacted-jwt]", message)
    message = _API_KEY_PATTERN.sub("[redacted-api-key]", message)
    message = re.sub(r"(?i)Bearer\s+\S+", "Bearer [redacted]", message)
    return re.sub(r"[\r\n\t]+", " ", message)[:240]


def _diagnostic_token_match(request: Optional[Request], token: str) -> Optional[bool]:
    if request is None:
        return None
    client_digest = request.headers.get("x-diagnostic-token-sha256")
    if client_digest is None:
        return None
    if not _TOKEN_DIGEST_PATTERN.fullmatch(client_digest):
        return False
    server_digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
    return hmac.compare_digest(client_digest, server_digest)


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
    request: Request = None,
) -> Dict[str, Any]:
    """Verify a Supabase JWT and return the authenticated user payload."""
    is_checkout_quote = bool(
        request and request.url.path.endswith("/customer/orders/quote")
    )
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token.",
        )

    client = get_supabase_client()
    if client is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Supabase authentication is not configured.",
        )

    auth_started = time.perf_counter()
    try:
        response = client.auth.get_user(credentials.credentials)
    except Exception as exc:
        status_code = getattr(exc, "status", getattr(exc, "status_code", None))
        if not isinstance(status_code, int):
            status_code = None
        error_code = getattr(exc, "code", None)
        if not isinstance(error_code, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", error_code):
            error_code = None
        logger.warning(
            "Supabase get_user failed: exception_class=%s status_code=%s supabase_error_code=%s "
            "error_message=%s bearer_token_received=%s token_transport_match=%s jwt_claims=%s",
            type(exc).__name__,
            status_code,
            error_code,
            _safe_auth_error_message(exc),
            bool(credentials and credentials.credentials),
            _diagnostic_token_match(request, credentials.credentials),
            json.dumps(_unverified_jwt_claims(credentials.credentials), sort_keys=True),
        )
        if is_checkout_quote:
            logger.warning(
                "Checkout quote authentication failed: stage=get_user elapsed_ms=%s",
                round((time.perf_counter() - auth_started) * 1000),
            )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token.",
        ) from exc
    if is_checkout_quote:
        logger.info(
            "Checkout quote authentication stage completed: stage=get_user elapsed_ms=%s",
            round((time.perf_counter() - auth_started) * 1000),
        )

    user = getattr(response, "user", None)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to resolve authenticated user.",
        )

    metadata = getattr(user, "user_metadata", None) or {}
    user_id = str(getattr(user, "id", ""))
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to resolve authenticated user.",
        )

    profile_started = time.perf_counter()
    try:
        profile_res = (
            client.table("profiles")
            .select("role")
            .eq("id", user_id)
            .single()
            .execute()
        )
    except Exception as exc:
        logger.warning("Unable to resolve the authenticated user's profile role.")
        if is_checkout_quote:
            logger.warning(
                "Checkout quote authentication failed: stage=profile_role elapsed_ms=%s",
                round((time.perf_counter() - profile_started) * 1000),
            )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Account role verification is temporarily unavailable.",
        ) from exc
    if is_checkout_quote:
        logger.info(
            "Checkout quote authentication stage completed: stage=profile_role elapsed_ms=%s",
            round((time.perf_counter() - profile_started) * 1000),
        )

    profile = getattr(profile_res, "data", None)
    role = profile.get("role") if isinstance(profile, dict) else None
    if role not in {"customer", "merchant"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="A valid account role could not be verified.",
        )

    profile_status = None
    if role == "merchant":
        try:
            merch_res = (
                client.table("merchant_profiles")
                .select("status")
                .eq("id", user_id)
                .single()
                .execute()
            )
        except Exception as exc:
            logger.warning("Unable to resolve the authenticated merchant's approval status.")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Merchant account verification is temporarily unavailable.",
            ) from exc
        merchant_profile = getattr(merch_res, "data", None)
        if isinstance(merchant_profile, dict):
            profile_status = merchant_profile.get("status")

    return {
        "id": user_id,
        "email": getattr(user, "email", None),
        "email_confirmed_at": getattr(user, "email_confirmed_at", None),
        "role": role,
        "status": profile_status,
        "metadata": metadata,
    }


def require_roles(*allowed_roles: str):
    """Factory returning a dependency that enforces role-based access."""

    def _checker(current_user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
        role = current_user.get("role")
        if role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Role '{role}' is not permitted for this operation.",
            )
        if current_user.get("email_confirmed_at") is None:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email address is not verified.",
            )
        return current_user

    return _checker


def require_approved_merchant(current_user: Dict[str, Any] = Depends(get_current_user)) -> Dict[str, Any]:
    if current_user.get("role") != "merchant":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant role required.")
    if current_user.get("email_confirmed_at") is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Email address is not verified.")
    if current_user.get("status") != "APPROVED":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Merchant account is not approved.")
    return current_user