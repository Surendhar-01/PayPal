from fastapi import APIRouter
from app.api.v1.endpoints import ai, auth, bidding, demands, fulfillment, grouping, health, offer_selection, orders, products, requirements, users

api_router = APIRouter()

# Register endpoint routers
api_router.include_router(health.router, tags=["Health & System Diagnostics"])
api_router.include_router(users.router, prefix="/users", tags=["Users & Authentication"])
api_router.include_router(auth.router, prefix="/auth", tags=["Authentication"])
api_router.include_router(products.router, prefix="/products", tags=["Product Catalogue"])
api_router.include_router(demands.router, prefix="/customer/demands", tags=["Customer Demands"])
api_router.include_router(requirements.router, tags=["Requirement Extraction"])
api_router.include_router(ai.router, prefix="/ai", tags=["AI Product Discovery"])
api_router.include_router(grouping.router, tags=["Demand Grouping"])
api_router.include_router(bidding.router, tags=["Merchant Bidding"])
api_router.include_router(offer_selection.router, tags=["Offer Validation and Selection"])
api_router.include_router(orders.router, tags=["Orders and Payments"])
api_router.include_router(fulfillment.router, tags=["Fulfillment and Tracking"])
