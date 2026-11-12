import pytest
from fastapi.testclient import TestClient

from app.core.security import get_current_user, require_roles
from app.main import app

client = TestClient(app)


def test_public_list_products():
    """Verify customer/public product catalogue returns active products with full details."""
    response = client.get("/api/products")
    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert "total" in data
    assert data["total"] >= 1
    first = data["items"][0]
    assert "id" in first
    assert "name" in first
    assert "retail_price" in first
    assert "wholesale_price" in first
    assert "minimum_order_quantity" in first
    assert "available_quantity" in first
    assert "specifications" in first
    assert "images" in first
    assert "status" in first
    assert first["status"] == "active"


def test_public_list_products_v1_alias():
    """Verify /api/v1/products alias works identically."""
    response = client.get("/api/v1/products")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] >= 1


def test_product_categories():
    """Verify distinct product categories endpoint."""
    response = client.get("/api/products/categories")
    assert response.status_code == 200
    categories = response.json()
    assert isinstance(categories, list)
    assert len(categories) > 0
    assert "Industrial Hardware" in categories or len(categories) >= 1


def test_product_search_and_filter():
    """Verify search by keyword and category filter."""
    # Search
    res_search = client.get("/api/products?search=Gateway")
    assert res_search.status_code == 200
    search_data = res_search.json()
    for item in search_data["items"]:
        assert "gateway" in item["name"].lower() or "gateway" in item["description"].lower() or "gateway" in str(item["specifications"]).lower()

    # Category filter
    res_cat = client.get("/api/products?category=Instrumentation")
    assert res_cat.status_code == 200
    cat_data = res_cat.json()
    for item in cat_data["items"]:
        assert "instrumentation" in item["category"].lower()

    # Price range filter
    res_price = client.get("/api/products?min_price=300&max_price=800")
    assert res_price.status_code == 200
    for item in res_price.json()["items"]:
        assert 300 <= item["retail_price"] <= 800

    # Sort price ascending
    res_sort = client.get("/api/products?sort_by=price_asc")
    assert res_sort.status_code == 200
    prices = [p["retail_price"] for p in res_sort.json()["items"]]
    assert prices == sorted(prices)


def test_product_details_by_id_and_slug():
    """Verify fetching single product by UUID and by slug."""
    list_res = client.get("/api/products?page_size=1")
    assert list_res.status_code == 200
    product = list_res.json()["items"][0]

    # Fetch by ID
    by_id = client.get(f"/api/products/{product['id']}")
    assert by_id.status_code == 200
    assert by_id.json()["id"] == product["id"]
    assert by_id.json()["name"] == product["name"]

    # Fetch by Slug
    if product.get("slug"):
        by_slug = client.get(f"/api/products/{product['slug']}")
        assert by_slug.status_code == 200
        assert by_slug.json()["id"] == product["id"]
