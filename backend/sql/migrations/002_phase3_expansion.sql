-- Phase 3: expanded production-oriented schema and RLS

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Ensure user_roles table for explicit RBAC
CREATE TABLE IF NOT EXISTS public.user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role user_role NOT NULL,
    granted_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, role)
);

-- Categories
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Product images
CREATE TABLE IF NOT EXISTS public.product_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    alt_text TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Rename offers -> merchant_offers (safe, only if target does not exist)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'offers'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'merchant_offers'
    ) THEN
        ALTER TABLE public.offers RENAME TO merchant_offers;
    END IF;
END $$;

-- Demand requirements (one row per structured requirement)
CREATE TABLE IF NOT EXISTS public.demand_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    demand_id UUID NOT NULL REFERENCES public.demands(id) ON DELETE CASCADE,
    requirement_key TEXT NOT NULL,
    requirement_value TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Demand group additions
ALTER TABLE public.demand_groups ADD COLUMN IF NOT EXISTS group_name TEXT;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS max_budget NUMERIC(12,2);
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS required_delivery_time INT;
ALTER TABLE public.demands ADD COLUMN IF NOT EXISTS custom_requirements TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.categories(id);

-- Merchant management
CREATE TABLE IF NOT EXISTS public.merchant_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'Pending',
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewed_by UUID REFERENCES public.profiles(id),
    reviewed_at TIMESTAMPTZ,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS public.merchant_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, category_id)
);

-- Offer items
CREATE TABLE IF NOT EXISTS public.offer_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id UUID NOT NULL REFERENCES public.merchant_offers(id) ON DELETE CASCADE,
    item_name TEXT NOT NULL,
    description TEXT,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(12,2) NOT NULL,
    total_price NUMERIC(12,2) NOT NULL,
    specs JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Offer eligibility per customer
CREATE TABLE IF NOT EXISTS public.offer_eligibility (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    offer_id UUID NOT NULL REFERENCES public.merchant_offers(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    eligible BOOLEAN NOT NULL DEFAULT FALSE,
    reason TEXT,
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (offer_id, customer_id)
);

-- Order expansion
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS accepted_offer_id UUID REFERENCES public.merchant_offers(id);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS accepted_terms JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS fulfillment_status TEXT NOT NULL DEFAULT 'Not Started';

CREATE TABLE IF NOT EXISTS public.order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    demand_id UUID REFERENCES public.demands(id) ON DELETE SET NULL,
    product_name TEXT,
    quantity INT NOT NULL DEFAULT 1,
    unit_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    status TEXT NOT NULL DEFAULT 'Pending',
    provider TEXT,
    provider_reference TEXT,
    refund_status TEXT NOT NULL DEFAULT 'None',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.fulfillment_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    milestone TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Pending',
    completed_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Platform management
CREATE TABLE IF NOT EXISTS public.platform_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL DEFAULT '{}'::jsonb,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT,
    entity_id UUID,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_roles_user ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_product_images_product ON public.product_images(product_id);
CREATE INDEX IF NOT EXISTS idx_demand_requirements_demand ON public.demand_requirements(demand_id);
CREATE INDEX IF NOT EXISTS idx_merchant_verifications_merchant ON public.merchant_verifications(merchant_id);
CREATE INDEX IF NOT EXISTS idx_merchant_categories_merchant ON public.merchant_categories(merchant_id);
CREATE INDEX IF NOT EXISTS idx_offer_items_offer ON public.offer_items(offer_id);
CREATE INDEX IF NOT EXISTS idx_offer_eligibility_offer ON public.offer_eligibility(offer_id);
CREATE INDEX IF NOT EXISTS idx_offer_eligibility_customer ON public.offer_eligibility(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_order ON public.payments(order_id);
CREATE INDEX IF NOT EXISTS idx_fulfillment_milestones_order ON public.fulfillment_milestones(order_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(actor_id);

-- Seed categories (idempotent)
INSERT INTO public.categories (name, description)
VALUES
  ('Office Furniture', 'Office furniture and workspace equipment'),
  ('Renewable Energy', 'Solar and renewable energy systems'),
  ('Commercial Kitchen', 'Commercial kitchen and food service equipment'),
  ('Electronics', 'Electronic devices and AV equipment'),
  ('Food & Beverage', 'Food and beverage supplies'),
  ('Industrial Equipment', 'Industrial machinery and equipment')
ON CONFLICT (name) DO NOTHING;

-- Enable RLS for new tables
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demand_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.merchant_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offer_eligibility ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fulfillment_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- Policies: user_roles
DROP POLICY IF EXISTS user_roles_select ON public.user_roles;
CREATE POLICY user_roles_select ON public.user_roles FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS user_roles_write ON public.user_roles;

-- categories (public read)
DROP POLICY IF EXISTS categories_select ON public.categories;
CREATE POLICY categories_select ON public.categories FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS categories_write ON public.categories;
CREATE POLICY categories_write ON public.categories FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- product_images (public read, admin write)
-- product_images (public read)
DROP POLICY IF EXISTS product_images_select ON public.product_images;
CREATE POLICY product_images_select ON public.product_images FOR SELECT USING (TRUE);

-- demand_requirements
DROP POLICY IF EXISTS demand_requirements_select ON public.demand_requirements;
CREATE POLICY demand_requirements_select ON public.demand_requirements FOR SELECT USING (auth.uid() IS NOT NULL);
DROP POLICY IF EXISTS demand_requirements_write ON public.demand_requirements;
CREATE POLICY demand_requirements_write ON public.demand_requirements FOR ALL USING (
    EXISTS (SELECT 1 FROM public.demands d WHERE d.id = demand_requirements.demand_id AND d.customer_id = auth.uid())
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.demands d WHERE d.id = demand_requirements.demand_id AND d.customer_id = auth.uid())
);

-- merchant_verifications
DROP POLICY IF EXISTS merchant_verifications_select ON public.merchant_verifications;
CREATE POLICY merchant_verifications_select ON public.merchant_verifications FOR SELECT USING (merchant_id = auth.uid());
DROP POLICY IF EXISTS merchant_verifications_write ON public.merchant_verifications;
CREATE POLICY merchant_verifications_write ON public.merchant_verifications FOR ALL USING (merchant_id = auth.uid()) WITH CHECK (merchant_id = auth.uid());

-- merchant_categories
DROP POLICY IF EXISTS merchant_categories_select ON public.merchant_categories;
CREATE POLICY merchant_categories_select ON public.merchant_categories FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS merchant_categories_write ON public.merchant_categories;
CREATE POLICY merchant_categories_write ON public.merchant_categories FOR ALL USING (merchant_id = auth.uid()) WITH CHECK (merchant_id = auth.uid());

-- offer_items (visible where parent offer visible)
DROP POLICY IF EXISTS offer_items_select ON public.offer_items;
CREATE POLICY offer_items_select ON public.offer_items FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = offer_items.offer_id AND (
        o.merchant_id = auth.uid() OR EXISTS (SELECT 1 FROM public.demands d WHERE d.id = o.demand_id AND d.customer_id = auth.uid())
    ))
);
DROP POLICY IF EXISTS offer_items_write ON public.offer_items;
CREATE POLICY offer_items_write ON public.offer_items FOR ALL USING (
    EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = offer_items.offer_id AND (o.merchant_id = auth.uid()))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = offer_items.offer_id AND (o.merchant_id = auth.uid()))
);

-- offer_eligibility
DROP POLICY IF EXISTS offer_eligibility_select ON public.offer_eligibility;
CREATE POLICY offer_eligibility_select ON public.offer_eligibility FOR SELECT USING (
    customer_id = auth.uid() OR EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = offer_eligibility.offer_id AND o.merchant_id = auth.uid())
);
DROP POLICY IF EXISTS offer_eligibility_write ON public.offer_eligibility;
CREATE POLICY offer_eligibility_write ON public.offer_eligibility FOR ALL USING (EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = offer_eligibility.offer_id AND o.merchant_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.merchant_offers o WHERE o.id = offer_eligibility.offer_id AND o.merchant_id = auth.uid()));

-- order_items
DROP POLICY IF EXISTS order_items_select ON public.order_items;
CREATE POLICY order_items_select ON public.order_items FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_items.order_id AND (o.customer_id = auth.uid() OR o.merchant_id = auth.uid()))
);
DROP POLICY IF EXISTS order_items_write ON public.order_items;
CREATE POLICY order_items_write ON public.order_items FOR ALL USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_items.order_id AND (o.merchant_id = auth.uid()))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_items.order_id AND (o.merchant_id = auth.uid()))
);

-- payments (customer read)
DROP POLICY IF EXISTS payments_select ON public.payments;
CREATE POLICY payments_select ON public.payments FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = payments.order_id AND (o.customer_id = auth.uid()))
);
DROP POLICY IF EXISTS payments_write ON public.payments;
CREATE POLICY payments_write ON public.payments FOR ALL USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = payments.order_id AND (o.merchant_id = auth.uid()))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = payments.order_id AND (o.merchant_id = auth.uid()))
);

-- fulfillment_milestones
DROP POLICY IF EXISTS fulfillment_milestones_select ON public.fulfillment_milestones;
CREATE POLICY fulfillment_milestones_select ON public.fulfillment_milestones FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = fulfillment_milestones.order_id AND (o.customer_id = auth.uid() OR o.merchant_id = auth.uid()))
);
DROP POLICY IF EXISTS fulfillment_milestones_write ON public.fulfillment_milestones;
CREATE POLICY fulfillment_milestones_write ON public.fulfillment_milestones FOR ALL USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = fulfillment_milestones.order_id AND (o.merchant_id = auth.uid()))
) WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = fulfillment_milestones.order_id AND (o.merchant_id = auth.uid()))
);

-- platform_settings (removed)
DROP POLICY IF EXISTS platform_settings_admin ON public.platform_settings;

-- audit_logs (removed)
DROP POLICY IF EXISTS audit_logs_select ON public.audit_logs;
DROP POLICY IF EXISTS audit_logs_insert ON public.audit_logs;