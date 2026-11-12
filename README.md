# MarketTwin – A Demand-Driven Marketplace

MarketTwin is a demand-driven marketplace where buyers aggregate purchasing intent and merchants submit competitive offers. Customers can search for products; if an item is unavailable, they submit demands. The platform identifies similar demands, groups compatible buyers, and invites verified merchants to submit competitive fulfillment proposals. Customers purchase only after explicitly reviewing and approving the winning offer.

## System Architecture & Roles

1. **Customer**
   - Searches catalog and creates product demands.
   - Joins demand groups to unlock bulk pricing.
   - Compares merchant offers and approves purchases explicitly.

2. **Merchant**
   - Views grouped demand pools.
   - Submits competitive offers.
   - Fulfills approved orders.

Only Customer and Merchant roles remain on the platform.

## Technology Stack

### Frontend
- React 18 + TypeScript
- Vite 6
- Tailwind CSS 3
- React Router 6
- Axios
- Ant Design 5
- Supabase JS client

### Backend
- Python 3.10+
- FastAPI
- Pydantic v2
- Uvicorn
- Supabase Python client
- Groq SDK (optional AI features)

### Database & Cloud
- Supabase PostgreSQL
- Supabase Authentication
- Supabase Storage
- Supabase Realtime

## Repository Structure

```
markettwin/
├── README.md
├── docs/
│   └── DATABASE.md
├── backend/
│   ├── .env.example
│   ├── requirements.txt
│   ├── app/
│   │   ├── main.py
│   │   ├── api/v1/
│   │   ├── core/
│   │   ├── schemas/
│   │   └── services/
│   ├── sql/migrations/
│   └── tests/
└── frontend/
    ├── .env.example
    ├── package.json
    ├── vite.config.ts
    ├── tailwind.config.js
    └── src/
        ├── api/
        ├── components/
        ├── context/
        ├── pages/
        ├── services/
        └── router/
```

## Getting Started

### Prerequisites
- Node.js v18+ (v20+ recommended)
- npm v9+
- Python 3.10+
- Git

### Backend Setup

```bash
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1   # Windows
# source .venv/bin/activate     # macOS/Linux
pip install -r requirements.txt
copy .env.example .env          # Windows
# cp .env.example .env          # macOS/Linux
```

Edit `backend/.env` with your Supabase credentials:

```env
PROJECT_NAME="MarketTwin API"
ENVIRONMENT="development"
DEBUG=True
API_V1_STR="/api/v1"
ALLOWED_ORIGINS="http://localhost:5173,http://127.0.0.1:5173,http://10.107.161.106:5173"

SUPABASE_URL="https://your-project-id.supabase.co"
SUPABASE_KEY="your-anon-key"
SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
SUPABASE_JWT_SECRET="your-jwt-secret"
FRONTEND_URL="http://localhost:5173"

GROQ_API_KEY="your-groq-api-key"

AI_PROVIDER="groq"
GROQ_MODEL="llama-3.1-8b-instant"
GROQ_HEALTH_TIMEOUT_SECONDS=2

PAYPAL_CLIENT_ID="your-paypal-client-id"
PAYPAL_CLIENT_SECRET="your-paypal-client-secret"
PAYPAL_MODE="sandbox"
```

For local AI conversations, set `GROQ_API_KEY` to your Groq API key and `GROQ_MODEL` to a supported Groq chat model (e.g., `llama-3.1-8b-instant`). The backend calls the Groq API server-side; no API key is exposed to the frontend. The anonymous conversation endpoint is `POST /api/v1/ai/conversation`. It does not save conversations or create demands.

Run migrations:

```bash
python -c "import psycopg2; print('ok')"
# Apply SQL files in backend/sql/migrations in order
```

Start backend:

```bash
python -m uvicorn app.main:app --reload --port 8000
```

Backend URLs:
- Base: http://localhost:8000
- Health: http://localhost:8000/api/v1/health
- Docs: http://localhost:8000/docs

## PayPal Sandbox Catalogue Checkout

The catalogue purchase flow is available only in PayPal Sandbox mode. Backend
configuration uses `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_MODE`,
and `FRONTEND_URL`. Set `PAYPAL_MODE=sandbox`; Live mode and non-Sandbox
approval links are rejected. Keep PayPal credentials in `backend/.env` only.
Do not add them to frontend environment variables.

The backend re-runs the existing product matcher when quoting and creating an
order. Only a selected exact-match product with all reported mandatory checks
passing can be purchased. The server verifies catalogue price, currency, and
stock, creates a pending internal order, then creates the PayPal order. The
customer is sent to PayPal Sandbox; a return to MarketTwin is not proof of
payment. The authenticated capture endpoint verifies the order and COMPLETED
capture before setting the payment status to `Paid`. Failed, cancelled, or
unverified captures remain unpaid. Capture retries are idempotent and can
reconcile a provider-completed capture if local persistence was temporarily
unavailable.

### Required database changes

Do not run these migrations automatically from the application. Review the
live schema, data, constraints, and RLS policies first, and apply them manually
to a staging database using the Supabase SQL Editor (or an approved SQL
connection), in this order:

1. `backend/sql/migrations/025_paypal_payment_compatibility.sql`
2. `backend/sql/migrations/026_catalogue_paypal_checkout.sql`

Migration 025 adds PayPal order/capture references and service-role-only
payment RPCs. Migration 026 adds catalogue order snapshots, checkout
idempotency, capture claim/recovery RPCs, and cancellation/failure events.
Both preserve existing rows and do not replace RLS policies. The migrations
have not been applied by this implementation. Live Supabase RLS policies and
all live constraints could not be independently verified; review them before
applying either migration.

### Purchase API

- `POST /api/v1/customer/orders/quote` — calculate a verified catalogue quote.
- `POST /api/v1/customer/orders/checkout` — create/reuse an idempotent pending
  catalogue order. Requires `product_id`, `quantity`, `requirements`, and
  `idempotency_key`; price fields are not accepted from the client.
- `GET /api/v1/customer/orders/{order_id}` — get the authenticated customer's
  order.
- `POST /api/v1/customer/orders/{order_id}/payments/paypal/create` — create or
  resume the Sandbox PayPal order; returns an approval URL.
- `POST /api/v1/customer/orders/{order_id}/payments/paypal/capture` — capture
  and verify the PayPal order. Request body contains only `paypal_order_id`.
- `POST /api/v1/customer/orders/{order_id}/payments/paypal/cancel` — record
  checkout cancellation without marking the order paid.

### Manual Sandbox test

1. Apply reviewed migrations 025 and 026 manually in staging/Supabase.
2. In PowerShell, start the backend:
   ```powershell
   cd D:\MarketTwin\PayPal\backend
   .\.venv\Scripts\Activate.ps1
   .\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
   ```
3. In a second PowerShell terminal, start the frontend:
   ```powershell
   cd D:\MarketTwin\PayPal\frontend
   npm run dev
   ```
4. Log in to MarketTwin as a customer and run product matching.
5. Confirm an exact match is shown with all mandatory checks passing. Confirm
   alternatives and any product with a failed/unknown mandatory check have no
   Purchase button.
6. Click **Purchase**, review the verified product, quantity, delivery estimate,
   currency, and total, then click **Continue to PayPal Sandbox**.
7. Confirm the browser navigates to a PayPal Sandbox domain, then sign in using
   the existing Personal Sandbox buyer account and approve the test payment.
   Never use a production PayPal account or real payment credentials.
8. On return, wait for the MarketTwin server-side capture verification. Confirm
   the order shows `Paid` and review its PayPal capture ID in the database.
9. Repeat and cancel at PayPal; verify the order remains unpaid. Refresh the
   success page after a completed test to confirm it does not create a second
   capture. Test a declined payment if supported by the Sandbox buyer flow.

Actual PayPal buyer approval/capture and live RLS behavior must still be
verified manually; automated tests mock PayPal HTTP requests.

### Frontend Setup

```bash
cd frontend
npm install
copy .env.example .env          # Windows
# cp .env.example .env          # macOS/Linux
```

Edit `frontend/.env`:

```env
# Leave empty for local development; Vite proxies /api to localhost:8000.
VITE_API_BASE_URL=
VITE_SUPABASE_URL=https://your-project-id.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

Start frontend:

```bash
npm run dev
```

Frontend URL: http://localhost:5173 (or the host's LAN address on port 5173).
For production, set `VITE_API_BASE_URL` to the reachable backend URL before building.

Production build:

```bash
npm run build
```

## Database Setup

SQL migrations are located in `backend/sql/migrations`. Apply them in order to your Supabase PostgreSQL database.

See `docs/DATABASE.md` for:
- Table relationships
- RLS policies
- Storage buckets
- Realtime configuration
- Environment setup

Migration `015_phase3_atomic_demand_submission.sql` adds the Phase 3 price-range,
fractional-quantity, ownership-policy, and atomic demand create/update contracts.
Review and verify it against a staging database before applying it to production.
Demand submission, editing, and analysis remain disabled by default through
`DEMAND_PERSISTENCE_ENABLED` and `DEMAND_ANALYSIS_ENABLED`; enable them only after
the migration and controlled staging checks succeed.

## Authentication

- Supabase Auth handles registration, login, password reset, and sessions.
- Frontend uses only the anon key.
- Backend verifies JWTs and enforces roles.
- Role-based route protection is enforced in frontend and backend.
- Only Customer and Merchant roles are supported; no Admin accounts or routes remain.

## Core Features

- Product catalogue and search
- Customer demand creation
- Demand requirement extraction and normalization
- Similar demand grouping
- Merchant bidding and offer submission
- Offer validation and customer selection
- Order creation and PayPal payment foundation
- Order fulfillment and delivery tracking

## Security

- No hardcoded secrets in frontend.
- Service-role key is backend-only.
- RLS enabled on application tables.
- Backend validates all protected operations.
- PayPal credentials are server-side only.

## Testing

### Backend

```bash
cd backend
.\.venv\Scripts\python.exe -m pytest -v
```

### Frontend

```bash
cd frontend
npm run build
```

## Deployment Notes

- Use production Supabase project and apply all migrations.
- Configure environment variables for production.
- Enable Supabase SMTP for email delivery.
- Use PayPal sandbox for testing before live credentials.
- Deploy frontend as SPA with routing fallback.
- Deploy backend with Uvicorn/Gunicorn behind HTTPS.
- Verify health checks, RLS, and payment flows before launch.

## License

This project is provided for development and educational use. Add your preferred license as needed.