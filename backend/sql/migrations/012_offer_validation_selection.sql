CREATE TABLE IF NOT EXISTS public.customer_offer_eligibility (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    demand_id UUID NOT NULL REFERENCES public.demands(id) ON DELETE CASCADE,
    offer_id UUID NOT NULL REFERENCES public.merchant_offers(id) ON DELETE CASCADE,
    eligibility_status TEXT NOT NULL DEFAULT 'Requires Review',
    validation_details JSONB NOT NULL DEFAULT '{}'::jsonb,
    validation_version TEXT NOT NULL DEFAULT 'v1',
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (customer_id, demand_id, offer_id)
);

CREATE TABLE IF NOT EXISTS public.customer_offer_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    selection_reference TEXT UNIQUE NOT NULL,
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    demand_id UUID NOT NULL REFERENCES public.demands(id) ON DELETE CASCADE,
    group_id UUID REFERENCES public.demand_groups(id) ON DELETE SET NULL,
    offer_id UUID NOT NULL REFERENCES public.merchant_offers(id) ON DELETE RESTRICT,
    merchant_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    selected_quantity NUMERIC NOT NULL,
    selected_unit TEXT NOT NULL,
    agreed_unit_price NUMERIC NOT NULL,
    currency TEXT NOT NULL DEFAULT 'USD',
    agreed_taxes NUMERIC NOT NULL DEFAULT 0,
    agreed_shipping_cost NUMERIC NOT NULL DEFAULT 0,
    agreed_additional_charges NUMERIC NOT NULL DEFAULT 0,
    estimated_total NUMERIC NOT NULL DEFAULT 0,
    delivery_terms_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    product_terms_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    compliance_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    selection_status TEXT NOT NULL DEFAULT 'Selected',
    customer_confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.offer_comparison_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    demand_id UUID NOT NULL REFERENCES public.demands(id) ON DELETE CASCADE,
    compared_offer_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coe_customer ON public.customer_offer_eligibility(customer_id);
CREATE INDEX IF NOT EXISTS idx_cos_customer ON public.customer_offer_selections(customer_id);
CREATE INDEX IF NOT EXISTS idx_och_customer ON public.offer_comparison_history(customer_id);

ALTER TABLE public.customer_offer_eligibility ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_offer_selections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offer_comparison_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS coe_select ON public.customer_offer_eligibility;
CREATE POLICY coe_select ON public.customer_offer_eligibility FOR SELECT USING (customer_id = auth.uid());

DROP POLICY IF EXISTS coe_write ON public.customer_offer_eligibility;
CREATE POLICY coe_write ON public.customer_offer_eligibility FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS cos_select ON public.customer_offer_selections;
CREATE POLICY cos_select ON public.customer_offer_selections FOR SELECT USING (customer_id = auth.uid());

DROP POLICY IF EXISTS cos_insert ON public.customer_offer_selections;
CREATE POLICY cos_insert ON public.customer_offer_selections FOR INSERT WITH CHECK (customer_id = auth.uid());

DROP POLICY IF EXISTS och_select ON public.offer_comparison_history;
CREATE POLICY och_select ON public.offer_comparison_history FOR SELECT USING (customer_id = auth.uid());

DROP POLICY IF EXISTS och_insert ON public.offer_comparison_history;
CREATE POLICY och_insert ON public.offer_comparison_history FOR INSERT WITH CHECK (customer_id = auth.uid());