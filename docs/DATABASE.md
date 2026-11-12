# MarketTwin Database & Supabase Documentation

## Overview
MarketTwin uses Supabase (PostgreSQL) for relational data, authentication, storage, and realtime updates. The schema is managed through SQL migration files in `backend/sql/migrations`.

## Environment Variables

### Backend (`backend/.env`)
```
PROJECT_NAME="MarketTwin API"
ENVIRONMENT="development"
DEBUG=True
API_V1_STR="/api/v1"
ALLOWED_ORIGINS="http://localhost:5173,http://127.0.0.1:5173,http://10.107.161.106:5173"
SUPABASE_URL="https://<project-ref>.supabase.co"
SUPABASE_KEY="<anon-public-key>"
SUPABASE_SERVICE_ROLE_KEY="<service-role-secret-key>"
```

### Frontend (`frontend/.env`)
```
# Leave empty in development to use the Vite /api proxy.
VITE_API_BASE_URL=
VITE_SUPABASE_URL=https://<project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<anon-public-key>
```

The frontend uses only the anon key. The service-role key is backend-only.

## Migrations
The stable migration sequence in this repository currently ends at
`019_demand_family_groups.sql`. Confirm the target database's applied migration
history before deciding what remains to apply; repository filenames alone do
not establish deployed state. Apply stable migrations in numeric filename order.

The migration directory is the source of truth for the deployed schema.
`backend/sql/schema.sql` is a baseline snapshot and does not include every later
migration.

The numeric-only draft sequence `020_merchant_offers_group_id_draft.sql`,
`021_semantic_group_reconciliation_draft.sql`,
`022_merchant_offer_writes_draft.sql`, `023_offer_acceptance_draft.sql`, and
`024_demand_embeddings_draft.sql` is unapproved and must not be applied.
The sequence replaces the former `019b` filename, which was incompatible with
numeric-only migration version parsers. Stable migrations through 019 do not
add `merchant_offers.group_id`. Migration 020 proposes a nullable UUID reference
to `demand_groups(id)` with
`ON DELETE RESTRICT`, backfills it from linked demands that already have a
group, and adds a `(group_id, merchant_id)` index. Legacy offers with no grouped
demand remain NULL. The 021 draft requires this contract and blocks merges when
either offer group or offer demand references a candidate group. Migrations 022
and 023 add offer-write and acceptance flows. Migration 022 keeps unknown
currency NULL on legacy offers; new submissions require a known currency, and
acceptance rejects unknown or mismatched currency. Migration 023 stores demand
currency and unit with accepted terms and payment records, and converts order
quantities to NUMERIC after duplicate-row preflights. Migration 024 is an atomic,
one-shot embeddings draft: it fails closed if its objects already exist and does
not backfill data.

The 024 embedding draft defines the table and RPC expected by the backend. It
requires pgvector to be installed already, resolves its extension schema without
relocating it, and deliberately uses exact cosine search with a model/version
index instead of assuming an ANN index or pgvector version. It adds no demand
foreign key because demand-deletion behavior for embeddings is not defined by the
application. The draft must be reviewed and validated before embedding-backed
candidate search is deployable.

### Offer RPC Contract
Offer writes use backend service-role RPCs, not direct inserts from the current
Python service. Migration 022 defines `submit_merchant_offer_v1` and
`revise_merchant_offer_v1`; the backend sends the matching named parameters and
stores minimum/quoted quantities as `NUMERIC`. Submission derives currency from
the group's demands and rejects missing or conflicting currency. Revision
recalculates the total from the stored quoted quantity; legacy offers without a
verified group/quoted quantity are retained but are not revisable through this
RPC.

Migration 023 defines `accept_merchant_offer_v1`. It verifies the demand and
offer currency after locking both records, then atomically writes the selection,
order, order item, and payment using the demand's currency and unit. Order and
order-item quantities are `NUMERIC`; the existing selection quantity is already
`NUMERIC`. Unknown legacy offer currency remains `NULL`, is returned as unknown
by the API, and cannot be accepted. Direct offer/selection writes are restricted
in favor of these service-role RPCs.

### Deployment Prerequisites
All migrations 020-024 remain drafts until disposable-database runtime
validation and explicit approval are complete. Before enabling demand submission
or automatic grouping in a deployment:

- Confirm the target database has stable migrations 001-019 and apply reviewed
  drafts 020-024 in numeric order.
- Configure the backend service-role key. The demand and offer RPCs require the
  `service_role`; the demand endpoint falls back to the anon key if the service
  key is absent.
- Keep `DEMAND_PERSISTENCE_ENABLED` false until the migration chain and API have
  passed staging validation. It defaults to false and causes demand submission
  to return 503 while disabled.
- Install pgvector in the database before migration 024. Without the extension
  and the embedding table/RPC, demand submission can be saved but automatic
  grouping will fall back to `needs_review`.

Do not treat matching migration filenames or offline tests as evidence that the
target database has the required schema; verify its applied migration history
and runtime RPC/security contracts in disposable staging first.

### Local Draft Validation
The current workstation has no PostgreSQL binaries/service, Supabase CLI, or
Supabase project config. Docker is installed but its daemon is unavailable, so
no isolated PostgreSQL server or migration-test harness is currently usable.
The related SQL files have only been parsed with `pglast`; PL/pgSQL and runtime
behavior have not been server-validated.

After separate authorization, validate only in a clean disposable local
Supabase project with locally generated keys and no production environment:

1. Install/start the local Supabase CLI and Docker stack in a temporary project.
2. Ensure pgvector is installed in the disposable database, then stage migrations
  001-019, followed by numeric drafts 020-024 in the temporary project's
  migration directory. Confirm the migration runner recognizes each numeric
  version in this exact order; preflight duplicate data and test reruns for
  020-023. Migration 024 is intentionally one-shot and should abort atomically
  when its objects already exist.
3. Run `supabase db reset --local` and `supabase db lint --local` against that
  local stack only; never use the production project URL or credentials.
4. Add local pgTAP/API tests for RPC signatures and security settings, RLS and
  direct-DML denial, proposal idempotency, approval authorization, redirects,
  offer blockers, stale snapshots, lock contention, and rollback after a
  forced merge postcondition failure.
5. Run `supabase test db` and inspect `pg_proc`, `pg_policies`, and
  `pg_constraint` in the disposable database. Do not promote the drafts until
  all checks pass, the remaining offer columns are reconciled, and the embedding
  table/RPC contract is implemented and tested.

## Core Tables
User management:
- `profiles` (extends `auth.users`)
- `customer_profiles`
- `merchant_profiles`
- `user_roles`

Product management:
- `categories`
- `products`
- `product_images`

Demand management:
- `demands`
- `demand_requirements`
- `demand_groups`
- `demand_group_members`

Merchant management:
- `merchant_verifications`
- `merchant_categories`

Offer management:
- `merchant_offers`
- `offer_items`
- `offer_eligibility`

Order management:
- `orders`
- `order_items`
- `payments`
- `fulfillment_milestones`

Platform management:
- `notifications`
- `platform_settings`
- `audit_logs`

## Key Relationships
- `profiles.id` references `auth.users.id`
- `customer_profiles.id` and `merchant_profiles.id` reference the same profile
  and Supabase Auth user ID
- `demands.customer_id` references `profiles.id`
- `demands.group_id` references `demand_groups.id`
- `demand_group_members` links customers to demand groups
- `merchant_offers.demand_id` references `demands.id`
- `merchant_offers.merchant_id` references `profiles.id`
- `offer_eligibility` links offers to customers
- `orders.accepted_offer_id` references `merchant_offers.id`
- `order_items.order_id` references `orders.id`
- `payments.order_id` references `orders.id`
- `fulfillment_milestones.order_id` references `orders.id`

## Security
- RLS is enabled on all application tables.
- Customers can access only their own profile, demands, orders, payments, and authorized offers.
- Merchants can access their own private merchant profile and manage only their own offers and fulfillment records.
- Only Customer and Merchant roles are supported; no Admin access paths remain.
- Service-role key is never exposed to the frontend.

## Auth Integration
- Supabase Auth manages users.
- `handle_new_user` trigger creates `profiles` and role-specific profile rows on signup.
- Frontend auth helpers: `frontend/src/services/authService.ts`
- Backend JWT verification: `backend/app/core/security.py` (`get_current_user`, `require_roles`)

## Storage
Buckets:
- `product-images` (public)
- `demand-specs` (private)

## Realtime
Enabled for:
- `demands`
- `demand_groups`
- `merchant_offers`
- `orders`
- `notifications`

## Backend Integration
- Supabase client: `backend/app/core/supabase.py`
- Auth dependency: `backend/app/core/security.py`
- Profile service: `backend/app/services/profile_service.py`
- Current user endpoint: `GET /api/v1/users/me`

## Frontend Integration
Reusable service modules:
- `frontend/src/services/supabase.ts`
- `frontend/src/services/authService.ts`
- `frontend/src/services/productService.ts`
- `frontend/src/services/demandService.ts`

Existing UI pages are preserved; mock data remains until each module is migrated to live queries.

The shared auth context verifies the active Supabase user with `auth.getUser()`,
then loads that user's `profiles` row by the same ID under RLS. The role in
`profiles.role` is authoritative; user metadata is only a display-name and
profile-image fallback. Customer and merchant details come from their matching
role-specific profile rows. There is no separate admin profile table.

## Email Configuration (Supabase Auth)

To avoid the default Supabase email rate limit, configure a custom SMTP provider in the Supabase Dashboard:

1. Go to **Authentication -> SMTP Settings** in your Supabase project.
2. Enable **Custom SMTP**.
3. Enter your SMTP host, port, username, password, and sender email.
4. Save and test email delivery.

Store SMTP credentials only in Supabase Dashboard or backend environment variables. Never expose them in frontend code.
